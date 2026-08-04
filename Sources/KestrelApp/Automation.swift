import SwiftUI
import AppKit
import KestrelCore

@MainActor final class AutomationController: ObservableObject {
    @Published var rules: [MaintenanceRule] = []
    @Published var previews: [String: CleanupPlan] = [:]     // keyed by rule name
    @Published var scheduled = false
    @Published var intervalHours = 24
    @Published var busy = false
    @Published var message: String?

    // New-rule form
    @Published var newName = ""
    @Published var newRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var newOlderDays = 30

    let intervalOptions = [6, 12, 24, 168]
    let olderOptions = [7, 30, 90, 180, 365]

    private let paths: KestrelPaths
    private var loaded = false
    init(paths: KestrelPaths) { self.paths = paths }

    func load() {
        guard !loaded else { return }
        loaded = true
        rules = RulesEngine.load(from: paths.rules)
        scheduled = RulesScheduler().isInstalled()
        for rule in rules { preview(rule) }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.directoryURL = newRoot
        if panel.runModal() == .OK, let url = panel.url { newRoot = url }
    }

    func addRule() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !rules.contains(where: { $0.name == name }) else { return }
        let rule = MaintenanceRule(name: name, root: newRoot.path, criteria: RuleCriteria(olderThanDays: newOlderDays))
        rules.append(rule)
        try? RulesEngine.save(rules, to: paths.rules)
        newName = ""
        preview(rule)
    }

    func deleteRule(_ rule: MaintenanceRule) {
        rules.removeAll { $0.name == rule.name }
        previews[rule.name] = nil
        try? RulesEngine.save(rules, to: paths.rules)
    }

    func preview(_ rule: MaintenanceRule) {
        Task.detached { [weak self] in
            let plan = RulesEngine().evaluate(rule)
            await MainActor.run { [weak self] in self?.previews[rule.name] = plan }
        }
    }

    /// Run one rule now — through the vault, undoable, audited.
    func applyRule(_ rule: MaintenanceRule) {
        guard !busy else { return }
        busy = true; message = nil
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let plan = RulesEngine().evaluate(rule)
            let result: ExecutionResult? = plan.items.isEmpty ? nil
                : try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run { [weak self] in
                self?.message = plan.items.isEmpty ? "Rule ‘\(rule.name)’ matched nothing."
                    : (result.map { "Rule ‘\(rule.name)’ — moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault.\($0.failureSuffix)" } ?? "Failed to run ‘\(rule.name)’.")
                self?.busy = false
                self?.preview(rule)
            }
        }
    }

    /// The kestrel CLI the LaunchAgent will run. Scheduling needs it installed.
    var cliPath: String {
        ["/opt/homebrew/bin/kestrel", "/usr/local/bin/kestrel"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "kestrel"
    }
    var cliInstalled: Bool { cliPath.hasPrefix("/") }

    func setSchedule(_ on: Bool) {
        do {
            if on { try RulesScheduler().writePlist(executable: cliPath, everyHours: intervalHours) }
            else { try RulesScheduler().removePlist() }
        } catch {
            message = "Couldn't change the schedule: \((error as NSError).localizedDescription)"
        }
        scheduled = RulesScheduler().isInstalled()
    }
}

struct AutomationSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: AutomationController

    var body: some View {
        SectionScaffold(title: "Automation", subtitle: "Declarative cleanup rules — previewed, vault-backed, undoable") {
            if let message = controller.message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good).font(.callout)
            }
            scheduleCard
            newRuleCard
            if controller.rules.isEmpty {
                Card { EmptyState(icon: "wand.and.rays", title: "No rules yet",
                                  caption: "Add a rule above — e.g. Downloads older than 30 days.", tint: Palette.accent) }
            } else {
                ForEach(Array(controller.rules.enumerated()), id: \.offset) { _, rule in ruleCard(rule) }
            }
        }
        .onAppear { controller.load() }
    }

    private var scheduleCard: some View {
        Card(tint: controller.scheduled ? Palette.good : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Run rules on a schedule")).font(.callout.weight(.medium))
                        Text(L("Installs a LaunchAgent that runs your rules automatically (into the vault).")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    KestrelToggle(isOn: Binding(get: { controller.scheduled }, set: { controller.setSchedule($0) }))
                }
                if controller.scheduled {
                    HStack(spacing: 8) {
                        Text(L("Every")).font(.caption).foregroundStyle(.secondary)
                        KestrelSelect(items: controller.intervalOptions, selection: $controller.intervalHours,
                                      label: { $0 >= 24 ? "\($0 / 24) \(L("d"))" : "\($0) h" })
                    }
                }
                if !controller.cliInstalled {
                    Label(L("Needs the kestrel CLI installed for the schedule to actually run."), systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(Palette.warn)
                }
            }
        }
    }

    private var newRuleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("New rule", icon: "plus.circle")
                TextField(L("Rule name (e.g. Old downloads)"), text: $controller.newName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                FolderChip(url: controller.newRoot) { controller.pickFolder() }
                HStack(spacing: 8) {
                    Text(L("Older than")).font(.caption).foregroundStyle(.secondary)
                    KestrelSelect(items: controller.olderOptions, selection: $controller.newOlderDays, label: { "\($0) \(L("days"))" })
                    Spacer()
                    Button { controller.addRule() } label: { Label(L("Add rule"), systemImage: "plus") }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(controller.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func ruleCard(_ rule: MaintenanceRule) -> some View {
        let preview = controller.previews[rule.name]
        return Card {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars.inverse").font(.title2).foregroundStyle(Palette.accent2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.subheadline.weight(.semibold))
                    Text("\((rule.root as NSString).lastPathComponent) · \(L("older than")) \(rule.criteria.olderThanDays ?? 0) \(L("days"))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let preview {
                        Text(preview.items.isEmpty ? L("Nothing matches right now") : "\(bytesString(preview.totalBytes)) · \(preview.count) \(L("items"))")
                            .font(.caption2).foregroundStyle(preview.items.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.accent))
                    }
                }
                Spacer()
                if let preview, !preview.items.isEmpty {
                    Button { controller.applyRule(rule) } label: {
                        if controller.busy { KestrelSpinner(size: 13) } else { Label(L("Run now"), systemImage: "play.fill") }
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small)).disabled(controller.busy)
                }
                Button { controller.deleteRule(rule) } label: { Image(systemName: "trash") }
                    .buttonStyle(.kestrel(.subtle, tint: Palette.crit, size: .small))
            }
        }
    }
}
