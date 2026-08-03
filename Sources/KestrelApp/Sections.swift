import SwiftUI
import AppKit
import KestrelCore

// MARK: - Cleanup

enum CleanupChoice: String, CaseIterable, Identifiable {
    case all, dev, cache, logs, dupes, large, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Everything safe"
        case .dev: return "Dev artifacts"
        case .cache: return "Caches"
        case .logs: return "Logs"
        case .dupes: return "Duplicates"
        case .large: return "Large & old"
        case .privacy: return "Privacy"
        }
    }

    var categories: Set<KestrelCore.Category>? {
        switch self {
        case .all: return nil
        case .dev: return [.devArtifact]
        case .cache: return [.safeCache]
        case .logs: return [.logs]
        case .dupes: return [.duplicate]
        case .large: return [.largeOld]
        case .privacy: return [.privacy]
        }
    }
}

struct CleanupSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var choice: CleanupChoice = .dev
    @State private var root = FileManager.default.homeDirectoryForCurrentUser
    @State private var scanning = false
    @State private var applying = false
    @State private var plan: CleanupPlan?
    @State private var message: String?
    @State private var aiReview: String?
    @State private var reviewing = false

    var body: some View {
        SectionScaffold(title: "Cleanup", subtitle: "Preview first — nothing is deleted, items move to the vault") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Category", selection: $choice) {
                        ForEach(CleanupChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Image(systemName: "folder")
                        Text(root.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { pickFolder() }.buttonStyle(.kestrel(.subtle, size: .small))
                    }

                    HStack {
                        Button(action: scan) {
                            if scanning { ProgressView().controlSize(.small) } else { Label("Scan", systemImage: "magnifyingglass") }
                        }
                        .buttonStyle(.kestrel)
                        .disabled(scanning || applying)

                        if let plan, !plan.items.isEmpty {
                            Button(action: apply) {
                                if applying { ProgressView().controlSize(.small) } else { Label("Move \(plan.count) to Vault", systemImage: "tray.and.arrow.down") }
                            }
                            .buttonStyle(.kestrel(.secondary))
                            .disabled(applying)

                            if model.aiConfigured {
                                Button(action: review) {
                                    if reviewing { ProgressView().controlSize(.small) } else { Label("AI review", systemImage: "sparkles") }
                                }
                                .buttonStyle(.kestrel(.subtle))
                                .disabled(reviewing)
                            }
                        }
                    }
                }
            }

            if let aiReview {
                Card {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(Palette.violet)
                        Text(aiReview).font(.callout).textSelection(.enabled)
                    }
                }
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good)
            }

            if let plan {
                if plan.items.isEmpty {
                    Label("Nothing to clean here.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                } else {
                    Text("Reclaimable: \(bytesString(plan.totalBytes)) across \(plan.count) item(s)").font(.headline)
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(plan.items.sorted { $0.entry.size > $1.entry.size }.prefix(60).enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(bytesString(item.entry.size)).font(.callout.monospacedDigit().weight(.medium)).frame(width: 80, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.entry.url.lastPathComponent).lineLimit(1)
                                        Text(item.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url; plan = nil; message = nil }
    }

    private func scan() {
        scanning = true; plan = nil; message = nil; aiReview = nil
        let root = self.root
        let categories = choice.categories
        Task.detached {
            let classified = (try? ScanCoordinator().scan(root: root)) ?? []
            let result = Planner().plan(classified, categories: categories)
            await MainActor.run { self.plan = result; self.scanning = false }
        }
    }

    private func review() {
        guard let plan, let assistant = model.aiAssistant else { return }
        reviewing = true; aiReview = nil
        Task {
            let text = (try? await assistant.review(plan: plan)) ?? "AI review failed. Check your key and connection."
            await MainActor.run { aiReview = text; reviewing = false }
        }
    }

    private func apply() {
        guard let plan else { return }
        applying = true
        let vaultURL = model.paths.vault
        let auditURL = model.paths.auditLog
        Task.detached {
            let executor = CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL))
            let result = try? executor.execute(plan, apply: true)
            await MainActor.run {
                self.message = result.map { "Moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable)." } ?? "Cleanup failed."
                self.plan = nil
                self.applying = false
            }
        }
    }
}

// MARK: - Assistant (AI, opt-in)

struct AssistantSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var question = ""
    @State private var answer: String?
    @State private var thinking = false
    @State private var root = FileManager.default.homeDirectoryForCurrentUser

    private let suggestions = [
        "What's using most of my disk?",
        "Is it safe to clear developer caches?",
        "How can I free space as a developer?",
    ]

    var body: some View {
        SectionScaffold(title: "Assistant", subtitle: "Honest AI help — opt-in, sends metadata only") {
            if !model.aiConfigured {
                setupCard
            } else {
                askCard
                analyzeCard
                if thinking {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                }
                if let answer {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Assistant", systemImage: "sparkles").font(.headline).foregroundStyle(Palette.violet)
                            Text(answer).textSelection(.enabled).font(.callout)
                        }
                    }
                }
                Text("Sends only metadata (names, sizes, categories) to Google Gemini — never file contents. Off unless you set a key.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Turn on the assistant", systemImage: "key").font(.headline)
                Text("The assistant is opt-in and off by default. To enable it, put your Google Gemini API key in a file:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(model.paths.geminiKey.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("It then sends only metadata (names, sizes, categories) — never file contents.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) } label: {
                    Label("Reveal ~/.kestrel in Finder", systemImage: "folder")
                }
                .buttonStyle(.kestrel(.secondary))
            }
        }
    }

    private var askCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Ask anything", icon: "bubble.left.and.sparkles")
                HStack {
                    TextField("e.g. what can I safely clean?", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(ask)
                    Button(action: ask) { Text("Ask") }
                        .buttonStyle(.kestrel(.prominent, tint: Palette.violet))
                        .disabled(thinking || question.isEmpty)
                }
                HStack {
                    ForEach(suggestions, id: \.self) { s in
                        Button { question = s; ask() } label: { Text(s).font(.caption) }
                            .buttonStyle(.kestrel(.subtle, size: .small))
                            .disabled(thinking)
                    }
                }
            }
        }
    }

    private var analyzeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Analyze a folder", icon: "sparkle.magnifyingglass")
                HStack {
                    Text(root.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { pickFolder() }.buttonStyle(.kestrel(.subtle, size: .small))
                    Button(action: analyze) { Text("Analyze") }
                        .buttonStyle(.kestrel(.prominent, tint: Palette.violet))
                        .disabled(thinking)
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url }
    }

    private func ask() {
        guard let assistant = model.aiAssistant, !question.isEmpty else { return }
        let q = question
        let context = model.aiContext()
        thinking = true; answer = nil
        Task {
            let result = (try? await assistant.ask(q, context: context)) ?? "The request failed. Check your API key and connection."
            await MainActor.run { answer = result; thinking = false }
        }
    }

    private func analyze() {
        guard let assistant = model.aiAssistant else { return }
        let target = root
        let currentDisk = model.disk
        thinking = true; answer = nil
        Task.detached {
            let classified = (try? ScanCoordinator().scan(root: target)) ?? []
            let plan = Planner().plan(classified)
            let result = (try? await assistant.summarize(plan: plan, disk: currentDisk)) ?? "The request failed. Check your API key and connection."
            await MainActor.run { answer = result; thinking = false }
        }
    }
}

// MARK: - Energy

struct EnergySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingQuit: ProcessEnergy?

    private var maxNow: Double { max(1, model.energyNow.map(\.energyImpact).max() ?? 1) }
    private var max24h: Double { max(1, model.energy24h.first?.total ?? 1) }

    var body: some View {
        SectionScaffold(title: "Energy", subtitle: "What's using power — right now and over the last 24 hours") {
            if let b = model.battery {
                Card {
                    HStack(spacing: 22) {
                        badge(icon: b.isCharging ? "battery.100.bolt" : "battery.75", title: "Charge", value: "\(b.percent)%", tint: Palette.good)
                        if let h = b.healthPercent { badge(icon: "heart.text.square", title: "Health", value: "\(h)%", tint: Palette.pink) }
                        if let cy = b.cycleCount { badge(icon: "arrow.triangle.2.circlepath", title: "Cycles", value: "\(cy)", tint: Palette.blue) }
                        badge(icon: "bolt", title: "State", value: b.isCharging ? "Charging" : "On battery", tint: Palette.orange)
                        if let m = model.batteryTimeMinutes {
                            badge(icon: b.isCharging ? "battery.100.bolt" : "hourglass",
                                  title: b.isCharging ? "Full in" : "Time left", value: minutesString(m), tint: Palette.teal)
                        }
                        Spacer()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Draining right now", icon: "bolt.fill")
                    if model.energyNow.isEmpty {
                        Text("Reading energy usage…").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(model.energyNow) { proc in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(proc.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(String(format: "%.0f%% CPU", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    MiniBar(fraction: proc.energyImpact / maxNow)
                                }
                                Button { pendingQuit = proc } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.crit)
                                }
                                .buttonStyle(.plain).help("Quit \(proc.name)")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Most draining — last 24 hours", icon: "clock.arrow.circlepath")
                    if model.energy24h.count < 2 {
                        Text("Building history… this fills in while Kestrel is running.").foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(Array(model.energy24h.prefix(10))) { usage in
                            LabeledBar(label: usage.name, value: String(format: "%.0f", usage.total),
                                       fraction: usage.total / max24h, tint: Palette.orange)
                        }
                        if let start = model.energyStart {
                            Text("Recorded since \(start.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .onAppear { model.energyAppeared() }
        .onDisappear { model.energyDisappeared() }
        .confirmationDialog("Quit \(pendingQuit?.name ?? "")?", isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })) {
            Button("Quit \(pendingQuit?.name ?? "")", role: .destructive) {
                if let p = pendingQuit { model.quitProcess(pid: p.pid) }
                pendingQuit = nil
            }
            Button("Cancel", role: .cancel) { pendingQuit = nil }
        } message: {
            Text("This asks the app to quit (SIGTERM). Unsaved work in that app may be lost.")
        }
    }

    private func badge(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
    }
}

// MARK: - Security

struct SecuritySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var scanning = false
    @State private var report: ScanReport?
    @State private var status: GatekeeperStatus?
    @State private var orphans: [LaunchItem] = []

    var body: some View {
        SectionScaffold(title: "Security", subtitle: "Honest, evidence-based checks — no scare tactics") {
            if let status {
                Card {
                    HStack(spacing: 20) {
                        badge("Gatekeeper", status.assessmentsEnabled == true ? "On" : (status.assessmentsEnabled == false ? "Off" : "?"),
                              ok: status.assessmentsEnabled == true)
                        badge("XProtect", status.xprotectVersion ?? "—", ok: status.xprotectVersion != nil)
                        Spacer()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Scan for threats", icon: "magnifyingglass")
                    HStack {
                        Image(systemName: "folder")
                        Text(root.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { pickFolder() }.buttonStyle(.kestrel(.subtle, size: .small))
                        Button(action: scan) {
                            if scanning { ProgressView().controlSize(.small) } else { Text("Scan") }
                        }
                        .buttonStyle(.kestrel).disabled(scanning)
                    }
                    if let report {
                        if report.isClean {
                            Label("Clean — scanned \(report.scanned) file(s).", systemImage: "checkmark.shield.fill").foregroundStyle(Palette.good)
                        } else {
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, f in
                                VStack(alignment: .leading, spacing: 1) {
                                    Label("[\(f.severity.rawValue)] \(f.rule)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange)
                                    Text(f.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                    }
                }
            }

            if !orphans.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Orphaned launch agents", icon: "bolt.badge.xmark")
                        ForEach(Array(orphans.enumerated()), id: \.offset) { _, o in
                            Text("\(o.label ?? "?") → \(o.program ?? "?")").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .onAppear {
            status = SystemProtectionReader().status()
            orphans = LaunchAgentAuditor().orphans()
        }
    }

    private func badge(_ title: String, _ value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Label(value, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Palette.good : Palette.crit).font(.headline)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url { root = url; report = nil }
    }

    private func scan() {
        scanning = true; report = nil
        let root = self.root
        Task.detached {
            let result = AntivirusEngine().scan(root: root)
            await MainActor.run { self.report = result; self.scanning = false }
        }
    }
}

// MARK: - Tools

struct ToolsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var project = FileManager.default.homeDirectoryForCurrentUser
    @State private var scanning = false
    @State private var secrets: [SecretMatch]?
    @State private var sleepers: [SleepAssertion] = []
    @State private var maintenance: [MaintenanceTask] = []

    private var home: URL { model.paths.home }

    var body: some View {
        SectionScaffold(title: "Tools", subtitle: "One-click cleanup tools and developer utilities") {
            SectionTitle("My Tools", icon: "wrench.and.screwdriver")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                PlanToolCard(title: "Trash Bins", subtitle: "Empty every Trash — undoable via the vault", icon: "trash", tint: Palette.good) { TrashFinder().find() }
                PlanToolCard(title: "App Leftovers", subtitle: "Data left behind by removed apps", icon: "app.badge.checkmark", tint: Palette.accent) { OrphanFinder().find() }
                PlanToolCard(title: "Old Installers", subtitle: ".dmg / .pkg / .iso in Downloads", icon: "shippingbox", tint: Palette.accent2) { ClutterFinder().oldInstallers(under: home.appendingPathComponent("Downloads")) }
                PlanToolCard(title: "Screenshots", subtitle: "Screenshots on the Desktop", icon: "camera.viewfinder", tint: Palette.accent) { ClutterFinder().screenshots(under: home.appendingPathComponent("Desktop")) }
                PlanToolCard(title: "Downloads", subtitle: "Files older than 30 days", icon: "arrow.down.circle", tint: Palette.accent2) { ClutterFinder().oldDownloads(under: home.appendingPathComponent("Downloads")) }
                PlanToolCard(title: "Mail Attachments", subtitle: "Locally cached, re-downloadable", icon: "paperclip", tint: Palette.accent) { ClutterFinder().mailAttachments(under: home.appendingPathComponent("Library/Mail")) }
                PlanToolCard(title: "Similar Images", subtitle: "Keep the best of each group", icon: "photo.on.rectangle.angled", tint: Palette.accent2) {
                    let files = (try? Scanner().scanFiles(under: home.appendingPathComponent("Pictures"), pruning: [], includingHidden: false)) ?? []
                    return SimilarImageFinder().plan(in: files)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Secrets scanner", icon: "key.horizontal")
                    HStack {
                        Text(project.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { pickProject() }.buttonStyle(.kestrel(.subtle, size: .small))
                        Button(action: scanSecrets) {
                            if scanning { ProgressView().controlSize(.small) } else { Text("Scan") }
                        }
                        .buttonStyle(.kestrel).disabled(scanning)
                    }
                    if let secrets {
                        if secrets.isEmpty {
                            Label("No leaked credentials found.", systemImage: "checkmark.circle").foregroundStyle(Palette.good)
                        } else {
                            ForEach(Array(secrets.prefix(40).enumerated()), id: \.offset) { _, m in
                                Text("[\(m.rule)] \(m.path):\(m.line)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Keeping the Mac awake", icon: "moon.zzz")
                    if sleepers.isEmpty {
                        Label("Nothing is preventing sleep.", systemImage: "checkmark.circle").foregroundStyle(Palette.good)
                    } else {
                        ForEach(Array(sleepers.enumerated()), id: \.offset) { _, a in
                            Text("\(a.process) — \(a.type)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Maintenance", icon: "wrench.adjustable")
                    Text("Run these yourself — they change system state.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(maintenance.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name + (t.needsSudo ? "  (needs sudo)" : "")).font(.callout.weight(.medium))
                            Text(t.command).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .onAppear {
            sleepers = PowerAuditor().assertionsPreventingSleep()
            maintenance = MaintenanceService().tasks()
        }
    }

    private func pickProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = project
        if panel.runModal() == .OK, let url = panel.url { project = url; secrets = nil }
    }

    private func scanSecrets() {
        scanning = true; secrets = nil
        let root = project
        Task.detached {
            let matches = SecretsScanner().scan(root: root)
            await MainActor.run { self.secrets = matches; self.scanning = false }
        }
    }
}
