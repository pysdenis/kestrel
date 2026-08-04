import SwiftUI
import AppKit
import ServiceManagement
import KestrelCore

// Scan state lives in these controllers (owned by AppModel), not in the section views.
// Because they outlive navigation, a scan started in one module keeps running and keeps
// its results when you switch away and back — nothing is torn down or cancelled.

// MARK: - Cleanup

@MainActor final class CleanupController: ObservableObject {
    @Published var choice: CleanupChoice = .dev
    @Published var root = FileManager.default.homeDirectoryForCurrentUser
    @Published var scanning = false
    @Published var applying = false
    @Published var plan: CleanupPlan?
    @Published var message: String?
    @Published var messageIsError = false
    @Published var aiReview: String?
    @Published var reviewing = false
    @Published var scanStatus = ""

    /// Categories the user has unchecked — excluded from the apply. Empty = clean everything.
    @Published var excluded: Set<KestrelCore.Category> = []
    /// Individual files the user has unchecked within an otherwise-included category.
    @Published var excludedItems: Set<URL> = []

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    func toggle(_ category: KestrelCore.Category) {
        if excluded.contains(category) { excluded.remove(category) } else { excluded.insert(category) }
    }
    func isIncluded(_ category: KestrelCore.Category) -> Bool { !excluded.contains(category) }

    func toggleItem(_ url: URL) {
        if excludedItems.contains(url) { excludedItems.remove(url) } else { excludedItems.insert(url) }
    }
    func isItemIncluded(_ url: URL) -> Bool { !excludedItems.contains(url) }

    /// The plan filtered to the currently-included categories and individual files.
    func selectedPlan(_ plan: CleanupPlan) -> CleanupPlan {
        CleanupPlan(items: plan.items.filter { !excluded.contains($0.category) && !excludedItems.contains($0.entry.url) })
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url; plan = nil; message = nil }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; plan = nil; message = nil; messageIsError = false; aiReview = nil; scanStatus = ""; excluded = []; excludedItems = []
        let root = self.root
        let categories = choice.categories
        Task.detached { [weak self] in
            do {
                let classified = try ScanCoordinator().scan(root: root) { count, url in
                    let name = url.lastPathComponent
                    Task { @MainActor in self?.scanStatus = "Scanned \(count) files · \(name)" }
                }
                let result = Planner().plan(classified, categories: categories)
                await MainActor.run { [weak self] in self?.plan = result; self?.scanning = false }
            } catch {
                // Surface the real reason instead of a misleading empty "nothing to clean".
                await MainActor.run { [weak self] in
                    self?.scanning = false
                    self?.messageIsError = true
                    self?.message = "Couldn't finish scanning \(root.lastPathComponent) — \((error as NSError).localizedDescription). Full Disk Access may be required."
                }
            }
        }
    }

    func review(assistant: AIAssistant?) {
        guard let plan, let assistant, !reviewing else { return }
        reviewing = true; aiReview = nil
        Task { [weak self] in
            let text = (try? await assistant.review(plan: plan)) ?? "AI review failed. Check your key and connection."
            await MainActor.run { [weak self] in self?.aiReview = text; self?.reviewing = false }
        }
    }

    func apply() {
        guard let plan, !applying else { return }
        applying = true
        let toMove = selectedPlan(plan)   // only the checked categories
        let vaultURL = paths.vault
        let auditURL = paths.auditLog
        Task.detached { [weak self] in
            let executor = CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL))
            let result = try? executor.execute(toMove, apply: true)
            await MainActor.run { [weak self] in
                self?.messageIsError = (result == nil)
                self?.message = result.map { "Moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable).\($0.failureSuffix)" } ?? "Cleanup failed."
                self?.plan = nil
                self?.applying = false
            }
        }
    }
}

// MARK: - Smart Care (one honest orchestrated pass)

@MainActor final class SmartCareController: ObservableObject {
    enum StepState { case pending, running, done, skipped }
    enum Step: String, CaseIterable, Identifiable {
        case cleanup, protection, malware, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cleanup: return "Reclaimable space"
            case .protection: return "macOS protection"
            case .malware: return "Malware scan"
            case .updates: return "App updates"
            }
        }
        var icon: String {
            switch self {
            case .cleanup: return "sparkles"; case .protection: return "checkmark.shield"
            case .malware: return "shield.checkerboard"; case .updates: return "arrow.triangle.2.circlepath"
            }
        }
    }

    @Published var running = false
    @Published var finished = false
    @Published var cleanupStep: StepState = .pending
    @Published var protectionStep: StepState = .pending
    @Published var malwareStep: StepState = .pending
    @Published var updatesStep: StepState = .pending
    @Published var status = ""
    /// Which steps to run. All on by default; the user can trim the pass before starting.
    @Published var enabledSteps: Set<Step> = Set(Step.allCases)

    @Published var plan: CleanupPlan?
    @Published var protection: GatekeeperStatus?
    @Published var report: ScanReport?
    @Published var updates: [OutdatedCask] = []
    @Published var applying = false
    @Published var message: String?

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    func isStepOn(_ s: Step) -> Bool { enabledSteps.contains(s) }
    func toggleStep(_ s: Step) {
        guard !running else { return }
        if enabledSteps.contains(s) { enabledSteps.remove(s) } else { enabledSteps.insert(s) }
    }

    /// Runs the chosen honest checks in sequence — reclaimable space (safe categories only),
    /// macOS protection status, a Downloads malware scan, and outdated apps — reporting live
    /// progress. Nothing is deleted; the cleanup plan is inert until the user applies it.
    func run(home: URL, downloads: URL) {
        guard !running, !enabledSteps.isEmpty else { return }
        running = true; finished = false; message = nil
        plan = nil; protection = nil; report = nil; updates = []
        let steps = enabledSteps
        cleanupStep = steps.contains(.cleanup) ? .running : .skipped
        protectionStep = steps.contains(.protection) ? .pending : .skipped
        malwareStep = steps.contains(.malware) ? .pending : .skipped
        updatesStep = steps.contains(.updates) ? .pending : .skipped
        status = steps.contains(.cleanup) ? "Scanning for reclaimable space…" : "Starting…"

        Task.detached { [weak self] in
            if steps.contains(.cleanup) {
                let classified = (try? ScanCoordinator().scan(root: home) { count, url in
                    Task { @MainActor in self?.status = "Scanned \(count) files · \(url.lastPathComponent)" }
                }) ?? []
                let plan = Planner().plan(classified)
                await MainActor.run { [weak self] in self?.plan = plan; self?.cleanupStep = .done }
            }
            if steps.contains(.protection) {
                await MainActor.run { [weak self] in self?.protectionStep = .running; self?.status = "Checking macOS protection…" }
                let protection = SystemProtectionReader().status()
                await MainActor.run { [weak self] in self?.protection = protection; self?.protectionStep = .done }
            }
            if steps.contains(.malware) {
                await MainActor.run { [weak self] in self?.malwareStep = .running; self?.status = "Scanning Downloads for malware…" }
                let report = AntivirusEngine().scan(root: downloads) { done, total, url in
                    Task { @MainActor in self?.status = "Malware scan \(done)/\(total) · \(url.lastPathComponent)" }
                }
                await MainActor.run { [weak self] in self?.report = report; self?.malwareStep = .done }
            }
            if steps.contains(.updates) {
                await MainActor.run { [weak self] in self?.updatesStep = .running; self?.status = "Checking for app updates…" }
                let updates = AppUpdater().outdatedCasks()
                await MainActor.run { [weak self] in self?.updates = updates; self?.updatesStep = .done }
            }
            await MainActor.run { [weak self] in
                self?.running = false; self?.finished = true; self?.status = ""
            }
        }
    }

    func apply() {
        guard let plan, !applying else { return }
        applying = true
        let vaultURL = paths.vault
        let auditURL = paths.auditLog
        Task.detached { [weak self] in
            let executor = CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL))
            let result = try? executor.execute(plan, apply: true)
            await MainActor.run { [weak self] in
                self?.message = result.map { "Moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable).\($0.failureSuffix)" } ?? "Cleanup failed."
                self?.plan = nil
                self?.applying = false
            }
        }
    }
}

// MARK: - Dashboard (forecast + protection)

@MainActor final class DashboardController: ObservableObject {
    @Published var trend: SpaceTrend?
    @Published var usedSeries: [Double] = []      // recent used-bytes, for the forecast sparkline
    @Published var protection: GatekeeperStatus?

    @Published var insight: String?
    @Published var insightLoading = false

    private let paths: KestrelPaths
    private var loadedProtection = false
    init(paths: KestrelPaths) { self.paths = paths }

    /// On-demand only (invariant #7): asks the opt-in assistant for one honest insight,
    /// sending just the metadata summary — never file contents.
    func getInsight(assistant: AIAssistant?, context: String) {
        guard let assistant, !insightLoading else { return }
        insightLoading = true
        Task { [weak self] in
            let prompt = "In one or two sentences, give the single most useful, honest, practical insight about this Mac's storage and health right now. Be specific."
            let text = (try? await assistant.ask(prompt, context: context)) ?? "Couldn't reach the assistant — check your key and connection."
            await MainActor.run { [weak self] in self?.insight = text; self?.insightLoading = false }
        }
    }

    /// Load the storage forecast and macOS protection status. Also records today's
    /// snapshot (disk capacity only — no directory walk, so it never prompts for access
    /// and never overwrites a richer snapshot the CLI may have written today), so the
    /// forecast becomes real on its own over a few days.
    func load(disk: DiskSpace?) {
        let dir = paths.snapshots
        Task.detached { [weak self] in
            let store = SnapshotStore(directory: dir)
            var snapshots = (try? store.all()) ?? []
            if let disk, !Self.hasSnapshotToday(snapshots) {
                try? store.save(DiskSnapshot(date: Date(), space: disk, breakdown: [:]))
                snapshots = (try? store.all()) ?? snapshots
            }
            let trend = try? store.trend()
            let series = snapshots.suffix(30).map { Double($0.space.used) }
            await MainActor.run { [weak self] in
                self?.trend = trend
                self?.usedSeries = series
            }
        }

        guard !loadedProtection else { return }
        loadedProtection = true
        Task.detached { [weak self] in
            let status = SystemProtectionReader().status()
            await MainActor.run { [weak self] in self?.protection = status }
        }
    }

    private nonisolated static func hasSnapshotToday(_ snapshots: [DiskSnapshot]) -> Bool {
        guard let last = snapshots.last else { return false }
        return Calendar.current.isDateInToday(last.date)
    }
}

// MARK: - Security

@MainActor final class SecurityController: ObservableObject {
    @Published var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var scanning = false
    @Published var report: ScanReport?
    @Published var status: GatekeeperStatus?
    @Published var orphans: [LaunchItem] = []
    @Published var extensions: [SystemExtension] = []
    @Published var quarantine: [QuarantineInfo] = []
    @Published var posture: SecurityPosture?
    @Published var scanProgress: Double = 0
    @Published var scanStatus = ""
    @Published var explanations: [String: String] = [:]   // finding key → AI explanation
    @Published var explaining: Set<String> = []
    private var loadedMeta = false

    static func findingKey(_ f: ScanFinding) -> String { "\(f.path)|\(f.rule)" }

    /// On-demand only (invariant #7): ask the opt-in assistant to explain a finding in
    /// plain language. Sends just the finding metadata (rule/path/evidence), never file
    /// contents.
    func explain(_ finding: ScanFinding, assistant: AIAssistant?) {
        guard let assistant else { return }
        let key = Self.findingKey(finding)
        guard explanations[key] == nil, !explaining.contains(key) else { return }
        explaining.insert(key)
        Task { [weak self] in
            let text = (try? await assistant.explainFinding(finding)) ?? "Couldn't reach the assistant — check your key and connection."
            await MainActor.run { [weak self] in self?.explanations[key] = text; self?.explaining.remove(key) }
        }
    }

    func loadMeta() {
        guard !loadedMeta else { return }
        loadedMeta = true
        status = SystemProtectionReader().status()
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        Task.detached { [weak self] in
            let orphaned = LaunchAgentAuditor().orphans()
            let exts = SystemExtensionAuditor().list()
            let quarantined = QuarantineReader().scan(root: downloads)
            let posture = SecurityPostureReader().read()
            await MainActor.run { [weak self] in
                self?.orphans = orphaned; self?.extensions = exts
                self?.quarantine = quarantined; self?.posture = posture
            }
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url; report = nil }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; report = nil; scanProgress = 0; scanStatus = ""
        let root = self.root
        Task.detached { [weak self] in
            let result = AntivirusEngine().scan(root: root) { done, total, url in
                let name = url.lastPathComponent
                let fraction = total > 0 ? Double(done) / Double(total) : 0
                Task { @MainActor in
                    self?.scanProgress = fraction
                    self?.scanStatus = "\(done) / \(total) files · \(name)"
                }
            }
            await MainActor.run { [weak self] in self?.report = result; self?.scanning = false }
        }
    }
}

// MARK: - Space

@MainActor final class SpaceController: ObservableObject {
    @Published var tree: DirNode?
    @Published var path: [DirNode] = []
    @Published var loading = false
    @Published var scanDone = 0
    @Published var scanTotal = 0
    @Published var scanStatus = ""
    @Published var message: String?
    @Published var driveHealth: DriveHealth?

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    /// Read the boot drive's SMART status once — honest hardware signal, read-only.
    func loadDriveHealth() {
        guard driveHealth == nil else { return }
        Task.detached { [weak self] in
            let health = DriveHealth.read()
            await MainActor.run { [weak self] in self?.driveHealth = health }
        }
    }

    /// Move a block from the map to the vault (undoable, audited). Refuses protected
    /// locations via SafetyGuard, then rescans so the map reflects reality.
    func moveToVault(_ node: DirNode) {
        guard !loading else { return }
        guard !SafetyGuard.isProtected(node.url) else {
            message = "“\(node.name)” is a protected location — Kestrel won't move it."
            return
        }
        let entry = FileEntry(url: node.url, size: node.size, modified: Date(), isDirectory: node.isDirectory)
        let plan = CleanupPlan(items: [CleanupItem(entry: entry, category: .largeOld, reason: "Removed from the Space map")])
        let vaultURL = paths.vault, auditURL = paths.auditLog, name = node.name
        Task.detached { [weak self] in
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run { [weak self] in
                self?.message = (result?.movedCount ?? 0) > 0 ? "Moved “\(name)” to the vault (undoable). Rescanning…" : "Couldn't move “\(name)”."
                self?.load()
            }
        }
    }

    func load() {
        guard !loading else { return }
        loading = true; path = []; scanStatus = ""; scanDone = 0; scanTotal = 0
        let home = paths.home
        Task.detached { [weak self] in
            let measured = DiskMap().measure(home, maxDepth: 3) { done, total, name in
                Task { @MainActor in
                    self?.scanDone = done; self?.scanTotal = total
                    self?.scanStatus = "Measured \(name) · \(done)/\(total)"
                }
            }
            await MainActor.run { [weak self] in self?.tree = measured; self?.loading = false }
        }
    }
}

// MARK: - Assistant (chat)

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

@MainActor final class AssistantController: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var thinking = false
    @Published var draft = ""
    @Published var analyzeRoot = FileManager.default.homeDirectoryForCurrentUser

    func clear() { messages.removeAll() }

    func send(_ text: String, assistant: AIAssistant?, context: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let assistant, !q.isEmpty, !thinking else { return }
        messages.append(ChatMessage(role: .user, text: q))
        draft = ""
        thinking = true
        Task { [weak self] in
            let reply = (try? await assistant.ask(q, context: context)) ?? "The request failed. Check your API key and connection."
            await MainActor.run { [weak self] in self?.messages.append(ChatMessage(role: .assistant, text: reply)); self?.thinking = false }
        }
    }

    func analyze(assistant: AIAssistant?, disk: DiskSpace?) {
        guard let assistant, !thinking else { return }
        let target = analyzeRoot
        messages.append(ChatMessage(role: .user, text: "Analyze “\(target.lastPathComponent)” and tell me what I can safely reclaim."))
        thinking = true
        Task.detached { [weak self] in
            let classified = (try? ScanCoordinator().scan(root: target)) ?? []
            let plan = Planner().plan(classified)
            let reply = (try? await assistant.summarize(plan: plan, disk: disk)) ?? "The request failed. Check your API key and connection."
            await MainActor.run { [weak self] in self?.messages.append(ChatMessage(role: .assistant, text: reply)); self?.thinking = false }
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = analyzeRoot
        if panel.runModal() == .OK, let url = panel.url { analyzeRoot = url }
    }
}

// MARK: - Settings (vault management)

@MainActor final class SettingsController: ObservableObject {
    @Published var sessions: [VaultSession] = []
    @Published var busy = false
    @Published var message: String?

    /// Preferences. `launchAtLogin` mirrors the real login-item state (SMAppService);
    /// `retentionDays` drives the vault purge window.
    @Published var launchAtLogin = false
    @Published var retentionDays = 14
    let retentionOptions = [7, 14, 30, 90]

    /// The user allowlist — paths Kestrel must never touch. Mirrors SafetyGuard.userExclusions.
    @Published var exclusions: [String] = []

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    private var exclusionStore: ExclusionStore { ExclusionStore(url: paths.exclusions) }

    private func syncExclusions(_ list: [String]) {
        exclusions = list
        SafetyGuard.userExclusions = Set(list)
    }

    func addExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.prompt = L("Exclude")
        guard panel.runModal() == .OK else { return }
        var list = exclusionStore.load()
        for url in panel.urls { list.append(url.path) }
        exclusionStore.save(list)
        syncExclusions(exclusionStore.load())
    }

    func removeExclusion(_ path: String) {
        syncExclusions(exclusionStore.remove(path))
    }

    func load() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        syncExclusions(exclusionStore.load())
        let vaultURL = paths.vault
        Task.detached { [weak self] in
            let sessions = (try? VaultService(vaultRoot: vaultURL).listSessions()) ?? []
            await MainActor.run { [weak self] in self?.sessions = sessions }
        }
    }

    /// Register/unregister the login item, then snap the published value back to the real
    /// OS state so the toggle can never drift from the truth.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Couldn't change the login item — this needs the packaged app."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    @Published var lastRestoreOK = true

    func undo(_ id: String) {
        guard !busy else { return }
        busy = true; message = nil
        let vaultURL = paths.vault
        Task.detached { [weak self] in
            var text: String
            var ok = true
            do {
                let outcome = try VaultService(vaultRoot: vaultURL).undo(session: id)
                var parts = ["Restored \(outcome.restored) item(s)"]
                if !outcome.skippedExisting.isEmpty {
                    parts.append("\(outcome.skippedExisting.count) already in place (kept in vault)")
                }
                if !outcome.failed.isEmpty {
                    ok = false
                    let reason = outcome.failed.first?.reason ?? ""
                    parts.append("\(outcome.failed.count) couldn't be restored — \(reason). Grant Full Disk Access if these are in Trash/Library.")
                }
                text = parts.joined(separator: " · ")
                if outcome.restored == 0 && outcome.skippedExisting.isEmpty && outcome.failed.isEmpty {
                    text = "Nothing to restore — the vault copies were already gone."
                }
            } catch {
                ok = false
                text = "Restore failed: \((error as NSError).localizedDescription)"
            }
            let sessions = (try? VaultService(vaultRoot: vaultURL).listSessions()) ?? []
            let finalText = text, finalOK = ok
            await MainActor.run { [weak self] in
                self?.message = finalText; self?.lastRestoreOK = finalOK
                self?.sessions = sessions; self?.busy = false
            }
        }
    }

    func purge(days: Int) {
        guard !busy else { return }
        busy = true; message = nil
        let vaultURL = paths.vault
        let interval = TimeInterval(days) * 86400
        Task.detached { [weak self] in
            let purged = (try? VaultService(vaultRoot: vaultURL).purge(olderThan: interval)) ?? []
            let sessions = (try? VaultService(vaultRoot: vaultURL).listSessions()) ?? []
            let bytes = purged.reduce(Int64(0)) { $0 + $1.totalBytes }
            await MainActor.run { [weak self] in
                self?.message = purged.isEmpty ? "Nothing old enough to purge yet." : "Permanently removed \(purged.count) session(s), \(bytesString(bytes)) freed."
                self?.sessions = sessions; self?.busy = false
            }
        }
    }
}

// MARK: - Tools

/// Per-tool run state for a `PlanToolCard`. One instance per tool, kept by `ToolsController`.
@MainActor final class ToolRunState: ObservableObject {
    @Published var plan: CleanupPlan?
    @Published var scanning = false
    @Published var applying = false
    @Published var message: String?
}

@MainActor final class ToolsController: ObservableObject {
    @Published var project = FileManager.default.homeDirectoryForCurrentUser
    @Published var secretsScanning = false
    @Published var secrets: [SecretMatch]?
    @Published var sleepers: [SleepAssertion] = []
    @Published var maintenance: [MaintenanceTask] = []
    @Published var loginItems: [LaunchItem] = []
    @Published var cloudFiles: [FileEntry] = []
    @Published var cloudLoading = false
    @Published var cloudMessage: String?
    // Similar-images review: groups of look-alikes, and which images the user marked to remove.
    @Published var photoGroups: [[FileEntry]] = []
    @Published var photoScanning = false
    @Published var photoApplying = false
    @Published var photoMessage: String?
    @Published var photoRemoval: Set<URL> = []
    // Duplicate files (any chosen folder): groups of byte-identical files + which copies to remove.
    @Published var dupFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var dupGroups: [DuplicateGroup] = []
    @Published var dupScanning = false
    @Published var dupApplying = false
    @Published var dupMessage: String?
    @Published var dupRemoval: Set<URL> = []
    // Developer package-manager caches (all regeneratable).
    @Published var devCaches: [PackageCache] = []
    @Published var devCachesLoading = false
    @Published var devCachesMessage: String?
    // Browser privacy stores — opt-in, nothing preselected (clearing history signs you out).
    @Published var privacyItems: [PrivacyItem] = []
    @Published var privacyLoading = false
    @Published var privacyApplying = false
    @Published var privacyMessage: String?
    @Published var privacySelection: Set<URL> = []
    private var states: [String: ToolRunState] = [:]
    private var loadedMeta = false

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    /// A stable per-tool state object. The backing dictionary is intentionally not
    /// `@Published` — creating a state lazily during a view build must not itself trigger
    /// an update; the card observes the returned `ToolRunState` directly.
    func state(_ id: String) -> ToolRunState {
        if let s = states[id] { return s }
        let s = ToolRunState(); states[id] = s; return s
    }

    func loadMeta() {
        guard !loadedMeta else { return }
        loadedMeta = true
        Task.detached { [weak self] in
            let sleep = PowerAuditor().assertionsPreventingSleep()
            let tasks = MaintenanceService().tasks()
            let items = LaunchAgentAuditor().audit()
            await MainActor.run { [weak self] in self?.sleepers = sleep; self?.maintenance = tasks; self?.loginItems = items }
        }
    }

    /// Scan iCloud Drive for large files with a local copy (evictable to free space).
    func loadCloud() {
        guard !cloudLoading else { return }
        cloudLoading = true
        Task.detached { [weak self] in
            let files = CloudOffloadFinder().find().sorted { $0.size > $1.size }
            await MainActor.run { [weak self] in self?.cloudFiles = files; self?.cloudLoading = false }
        }
    }

    /// Offload (evict) a file's local copy — it stays in iCloud. Non-destructive.
    func offload(_ file: FileEntry) {
        cloudMessage = nil
        let url = file.url
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
            process.arguments = ["evict", url.path]
            let ok = (try? { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }()) ?? false
            await MainActor.run { [weak self] in
                self?.cloudMessage = ok ? "Offloaded “\(url.lastPathComponent)” — it stays in iCloud." : "Couldn't offload “\(url.lastPathComponent)”."
                self?.cloudFiles.removeAll { $0.url == url }
            }
        }
    }

    /// Scan Pictures for perceptually-similar photos, grouped. Defaults to keeping the largest
    /// of each group and marking the rest for removal — the user tweaks per image before applying.
    func scanPhotos() {
        guard !photoScanning else { return }
        photoScanning = true; photoMessage = nil; photoGroups = []; photoRemoval = []
        let home = paths.home
        Task.detached { [weak self] in
            let files = (try? Scanner().scanFiles(under: home.appendingPathComponent("Pictures"), pruning: [], includingHidden: false)) ?? []
            let groups = SimilarImageFinder().find(in: files)
            let removal = Set(groups.flatMap { $0.dropFirst().map(\.url) })  // keep the largest (index 0)
            await MainActor.run { [weak self] in
                self?.photoGroups = groups
                self?.photoRemoval = removal
                self?.photoScanning = false
                if groups.isEmpty { self?.photoMessage = "No similar photos found." }
            }
        }
    }

    func togglePhoto(_ url: URL) {
        if photoRemoval.contains(url) { photoRemoval.remove(url) } else { photoRemoval.insert(url) }
    }

    var photoRemovalBytes: Int64 {
        let sizes = Dictionary(photoGroups.flatMap { $0 }.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        return photoRemoval.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    /// Move the marked images to the vault (undoable), then drop them from the groups.
    func applyPhotos() {
        guard !photoRemoval.isEmpty, !photoApplying else { return }
        photoApplying = true
        let entries = photoGroups.flatMap { $0 }.filter { photoRemoval.contains($0.url) }
        let plan = CleanupPlan(items: entries.map { CleanupItem(entry: $0, category: .duplicate, reason: "Similar/duplicate image") })
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            let removed = Set(entries.map(\.url))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.photoMessage = result.map { "Moved \($0.movedCount) photo(s), \(bytesString($0.movedBytes)) → vault\($0.failureSuffix)" } ?? "Failed"
                self.photoGroups = self.photoGroups.map { $0.filter { !removed.contains($0.url) } }.filter { $0.count > 1 }
                self.photoRemoval = []
                self.photoApplying = false
            }
        }
    }

    /// Scan for global package-manager caches (npm, pip, Gradle, DerivedData…) with their sizes.
    func loadDevCaches() {
        guard !devCachesLoading else { return }
        devCachesLoading = true; devCachesMessage = nil
        Task.detached { [weak self] in
            let caches = PackageCacheFinder().find()
            await MainActor.run { [weak self] in
                self?.devCaches = caches
                self?.devCachesLoading = false
                if caches.isEmpty { self?.devCachesMessage = "No developer caches found." }
            }
        }
    }

    /// Move a cache directory to the vault (undoable). It's regeneratable, so tools rebuild it.
    func clearDevCache(_ cache: PackageCache) {
        devCachesMessage = nil
        let entry = FileEntry(url: cache.url, size: cache.size, modified: Date(), isDirectory: true)
        let plan = CleanupPlan(items: [CleanupItem(entry: entry, category: .devArtifact, reason: "\(cache.tool) cache")])
        let vaultURL = paths.vault, auditURL = paths.auditLog, tool = cache.tool, url = cache.url
        Task.detached { [weak self] in
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run { [weak self] in
                self?.devCachesMessage = (result?.movedCount ?? 0) > 0 ? "Cleared \(tool) cache → vault (undoable)." : "Couldn't clear \(tool) cache."
                self?.devCaches.removeAll { $0.url == url }
            }
        }
    }

    /// Locate browser caches/history/cookies with their sizes. Nothing is preselected.
    func loadPrivacy() {
        guard !privacyLoading else { return }
        privacyLoading = true; privacyMessage = nil; privacySelection = []
        Task.detached { [weak self] in
            let items = PrivacyDataFinder().find()
            await MainActor.run { [weak self] in
                self?.privacyItems = items
                self?.privacyLoading = false
                if items.isEmpty { self?.privacyMessage = "No browser data found." }
            }
        }
    }

    func togglePrivacy(_ url: URL) {
        if privacySelection.contains(url) { privacySelection.remove(url) } else { privacySelection.insert(url) }
    }

    var privacySelectionBytes: Int64 {
        let sizes = Dictionary(privacyItems.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        return privacySelection.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    /// Move the chosen privacy stores to the vault (undoable). Explicit selection only.
    func applyPrivacy() {
        guard !privacySelection.isEmpty, !privacyApplying else { return }
        privacyApplying = true
        let chosen = privacyItems.filter { privacySelection.contains($0.url) }
        let plan = CleanupPlan(items: chosen.map {
            CleanupItem(entry: FileEntry(url: $0.url, size: $0.size, modified: Date(), isDirectory: true),
                        category: .privacy, reason: "\($0.app) \($0.kind.rawValue)")
        })
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            let removed = Set(chosen.map(\.url))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.privacyMessage = result.map { "Cleared \($0.movedCount) item(s), \(bytesString($0.movedBytes)) → vault\($0.failureSuffix)" } ?? "Failed"
                self.privacyItems.removeAll { removed.contains($0.url) }
                self.privacySelection = []
                self.privacyApplying = false
            }
        }
    }

    func pickDupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = dupFolder
        if panel.runModal() == .OK, let url = panel.url { dupFolder = url; dupGroups = []; dupMessage = nil }
    }

    /// Find byte-identical duplicates in the chosen folder, grouped. Every copy (but never the
    /// kept original) is preselected for removal; the user unticks any they want to keep.
    func scanDuplicates() {
        guard !dupScanning else { return }
        dupScanning = true; dupMessage = nil; dupGroups = []; dupRemoval = []
        let root = dupFolder
        Task.detached { [weak self] in
            let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
            let groups = DuplicateFinder().findGroups(in: files)
            let removal = Set(groups.flatMap { $0.copies.map(\.url) })
            await MainActor.run { [weak self] in
                self?.dupGroups = groups
                self?.dupRemoval = removal
                self?.dupScanning = false
                if groups.isEmpty { self?.dupMessage = "No duplicate files found." }
            }
        }
    }

    func toggleDup(_ url: URL) {
        if dupRemoval.contains(url) { dupRemoval.remove(url) } else { dupRemoval.insert(url) }
    }

    var dupRemovalBytes: Int64 {
        let sizes = Dictionary(dupGroups.flatMap { $0.all }.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        return dupRemoval.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    func applyDuplicates() {
        guard !dupRemoval.isEmpty, !dupApplying else { return }
        dupApplying = true
        let entries = dupGroups.flatMap { $0.copies }.filter { dupRemoval.contains($0.url) }
        let plan = CleanupPlan(items: entries.map { CleanupItem(entry: $0, category: .duplicate, reason: "Duplicate file") })
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            let removed = Set(entries.map(\.url))
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.dupMessage = result.map { "Moved \($0.movedCount) file(s), \(bytesString($0.movedBytes)) → vault\($0.failureSuffix)" } ?? "Failed"
                self.dupGroups = self.dupGroups.compactMap { g in
                    let copies = g.copies.filter { !removed.contains($0.url) }
                    return copies.isEmpty ? nil : DuplicateGroup(original: g.original, copies: copies)
                }
                self.dupRemoval = []
                self.dupApplying = false
            }
        }
    }

    func runTool(_ id: String, scan: @escaping @Sendable () -> CleanupPlan) {
        let s = state(id)
        guard !s.scanning else { return }
        s.scanning = true; s.message = nil
        Task.detached {
            let result = scan()
            await MainActor.run { s.scanning = false; s.plan = result }
        }
    }

    func applyTool(_ id: String) {
        let s = state(id)
        guard let plan = s.plan, !s.applying else { return }
        s.applying = true
        let vaultURL = paths.vault
        let auditURL = paths.auditLog
        Task.detached {
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run {
                s.message = result.map { "Cleaned \($0.movedCount), \(bytesString($0.movedBytes)) → vault\($0.failureSuffix)" } ?? "Failed"
                s.plan = nil
                s.applying = false
            }
        }
    }

    func pickProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = project
        if panel.runModal() == .OK, let url = panel.url { project = url; secrets = nil }
    }

    func scanSecrets() {
        guard !secretsScanning else { return }
        secretsScanning = true; secrets = nil
        let root = project
        Task.detached { [weak self] in
            let matches = SecretsScanner().scan(root: root)
            await MainActor.run { [weak self] in self?.secrets = matches; self?.secretsScanning = false }
        }
    }
}
