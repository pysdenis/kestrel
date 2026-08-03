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
                        Button("Choose…") { pickFolder() }
                    }

                    HStack {
                        Button(action: scan) {
                            if scanning { ProgressView().controlSize(.small) } else { Label("Scan", systemImage: "magnifyingglass") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(scanning || applying)

                        if let plan, !plan.items.isEmpty {
                            Button(action: apply) {
                                if applying { ProgressView().controlSize(.small) } else { Label("Move \(plan.count) to Vault", systemImage: "tray.and.arrow.down") }
                            }
                            .disabled(applying)
                        }
                    }
                }
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
        scanning = true; plan = nil; message = nil
        let root = self.root
        let categories = choice.categories
        Task.detached {
            let classified = (try? ScanCoordinator().scan(root: root)) ?? []
            let result = Planner().plan(classified, categories: categories)
            await MainActor.run { self.plan = result; self.scanning = false }
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
                        Button("Choose…") { pickFolder() }
                        Button(action: scan) {
                            if scanning { ProgressView().controlSize(.small) } else { Text("Scan") }
                        }
                        .buttonStyle(.borderedProminent).disabled(scanning)
                    }
                    if let report {
                        if report.isClean {
                            Label("Clean — scanned \(report.scanned) file(s).", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                        } else {
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, f in
                                VStack(alignment: .leading, spacing: 1) {
                                    Label("[\(f.severity.rawValue)] \(f.rule)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
                .foregroundStyle(ok ? .green : .red).font(.headline)
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

    var body: some View {
        SectionScaffold(title: "Tools", subtitle: "Developer and maintenance utilities") {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Secrets scanner", icon: "key.horizontal")
                    HStack {
                        Text(project.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { pickProject() }
                        Button(action: scanSecrets) {
                            if scanning { ProgressView().controlSize(.small) } else { Text("Scan") }
                        }
                        .buttonStyle(.borderedProminent).disabled(scanning)
                    }
                    if let secrets {
                        if secrets.isEmpty {
                            Label("No leaked credentials found.", systemImage: "checkmark.circle").foregroundStyle(.green)
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
                        Label("Nothing is preventing sleep.", systemImage: "checkmark.circle").foregroundStyle(.green)
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
