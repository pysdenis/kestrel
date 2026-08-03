import SwiftUI
import AppKit
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
    @Published var aiReview: String?
    @Published var reviewing = false
    @Published var scanStatus = ""

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url; plan = nil; message = nil }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; plan = nil; message = nil; aiReview = nil; scanStatus = ""
        let root = self.root
        let categories = choice.categories
        Task.detached { [weak self] in
            let classified = (try? ScanCoordinator().scan(root: root) { count, url in
                let name = url.lastPathComponent
                Task { @MainActor in self?.scanStatus = "Scanned \(count) files · \(name)" }
            }) ?? []
            let result = Planner().plan(classified, categories: categories)
            await MainActor.run { self?.plan = result; self?.scanning = false }
        }
    }

    func review(assistant: AIAssistant?) {
        guard let plan, let assistant, !reviewing else { return }
        reviewing = true; aiReview = nil
        Task { [weak self] in
            let text = (try? await assistant.review(plan: plan)) ?? "AI review failed. Check your key and connection."
            await MainActor.run { self?.aiReview = text; self?.reviewing = false }
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
            await MainActor.run {
                self?.message = result.map { "Moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable)." } ?? "Cleanup failed."
                self?.plan = nil
                self?.applying = false
            }
        }
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
    @Published var scanProgress: Double = 0
    @Published var scanStatus = ""
    private var loadedMeta = false

    func loadMeta() {
        guard !loadedMeta else { return }
        loadedMeta = true
        status = SystemProtectionReader().status()
        Task.detached { [weak self] in
            let orphaned = LaunchAgentAuditor().orphans()
            let exts = SystemExtensionAuditor().list()
            await MainActor.run { self?.orphans = orphaned; self?.extensions = exts }
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
            await MainActor.run { self?.report = result; self?.scanning = false }
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

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

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
            await MainActor.run { self?.tree = measured; self?.loading = false }
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
            await MainActor.run { self?.sleepers = sleep; self?.maintenance = tasks }
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
                s.message = result.map { "Cleaned \($0.movedCount), \(bytesString($0.movedBytes)) → vault" } ?? "Failed"
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
            await MainActor.run { self?.secrets = matches; self?.secretsScanning = false }
        }
    }
}
