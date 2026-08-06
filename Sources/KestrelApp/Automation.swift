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

    // Natural-language rule builder (local-first: uses whichever assistant backend is active)
    @Published var nlDraft = ""
    @Published var nlBusy = false
    @Published var nlSuggestion: MaintenanceRule?
    @Published var nlSuggestionPlan: CleanupPlan?
    @Published var nlError: String?

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

    /// Turn a plain-language sentence into a proposed rule via the (local-first) assistant, then
    /// show it for review. Nothing is saved or run until the user accepts — the assistant only
    /// proposes. Metadata only leaves the device (and stays on-device with Ollama/on-device AI).
    func suggestFromLanguage(assistant: AIAssistant?) {
        let text = nlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let assistant, !text.isEmpty, !nlBusy else { return }
        nlBusy = true; nlError = nil; nlSuggestion = nil; nlSuggestionPlan = nil
        Task { [weak self] in
            let json = (try? await assistant.suggestRule(from: text)) ?? ""
            let rule = json.data(using: .utf8).flatMap { try? JSONDecoder().decode(MaintenanceRule.self, from: $0) }
            guard let rule else {
                await MainActor.run { [weak self] in
                    self?.nlError = L("Couldn't turn that into a rule. Try something like “delete screenshots older than 30 days”.")
                    self?.nlBusy = false
                }
                return
            }
            let plan = await Task.detached { RulesEngine().evaluate(rule) }.value
            await MainActor.run { [weak self] in
                self?.nlSuggestion = rule; self?.nlSuggestionPlan = plan; self?.nlBusy = false
            }
        }
    }

    /// Accept the proposed rule: add it (with a unique name), save, and preview it. Still just a
    /// rule — it only runs when the user runs it or the schedule fires, always through the vault.
    func acceptSuggestion() {
        guard let suggestion = nlSuggestion else { return }
        var rule = suggestion
        if rules.contains(where: { $0.name == rule.name }) {
            rule = MaintenanceRule(name: "\(rule.name) (2)", root: rule.root, criteria: rule.criteria)
        }
        rules.append(rule)
        try? RulesEngine.save(rules, to: paths.rules)
        preview(rule)
        nlDraft = ""; nlSuggestion = nil; nlSuggestionPlan = nil; nlError = nil
    }

    func discardSuggestion() { nlSuggestion = nil; nlSuggestionPlan = nil; nlError = nil }

    /// Create a scheduled-cleanup rule from a regrowth cadence (the data-driven link). Re-reads
    /// from disk first so it never clobbers existing rules, dedupes the name, and previews it.
    @discardableResult
    func createRule(name: String, rootPath: String, olderDays: Int) -> Bool {
        var current = RulesEngine.load(from: paths.rules)
        var finalName = name
        var n = 2
        while current.contains(where: { $0.name == finalName }) { finalName = "\(name) (\(n))"; n += 1 }
        let rule = MaintenanceRule(name: finalName, root: rootPath, criteria: RuleCriteria(olderThanDays: olderDays))
        current.append(rule)
        try? RulesEngine.save(current, to: paths.rules)
        rules = current
        loaded = true
        preview(rule)
        return true
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
            if model.aiConfigured { nlCard }
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

    /// Describe a rule in plain language; the local-first assistant drafts it, you review the
    /// match, then add it. The assistant only proposes — nothing is saved or run until you accept.
    private var nlCard: some View {
        Card(tint: Palette.violet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionTitle("Describe a rule", icon: "text.bubble")
                    if model.aiIsLocal {
                        Text(L("on-device")).font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.good.opacity(0.15), in: Capsule())
                            .foregroundStyle(Palette.good)
                    }
                    Spacer()
                    if let coder = model.ruleModelHint {
                        Label(coder, systemImage: "cpu").font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .help(L("Using a stronger local model for more accurate rules."))
                    }
                }
                HStack(spacing: 8) {
                    TextField(L("e.g. delete screenshots older than 30 days"), text: $controller.nlDraft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onSubmit { controller.suggestFromLanguage(assistant: model.ruleAssistant) }
                    Button { controller.suggestFromLanguage(assistant: model.ruleAssistant) } label: {
                        if controller.nlBusy { KestrelSpinner(tint: .white, size: 14) } else { Label(L("Suggest"), systemImage: "sparkles") }
                    }
                    .buttonStyle(.kestrel(.prominent, tint: Palette.violet, size: .small))
                    .disabled(controller.nlBusy || controller.nlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let err = controller.nlError {
                    Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let rule = controller.nlSuggestion {
                    let plan = controller.nlSuggestionPlan
                    Hairline()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Proposed rule — review before adding")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars.inverse").font(.title2).foregroundStyle(Palette.violet)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name).font(.subheadline.weight(.semibold))
                                Text(ruleSummary(rule)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                if let plan {
                                    Text(plan.items.isEmpty ? L("Nothing matches right now") : "\(bytesString(plan.totalBytes)) · \(plan.count) \(L("items"))")
                                        .font(.caption2).foregroundStyle(plan.items.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.accent))
                                }
                            }
                            Spacer()
                            Button { controller.acceptSuggestion() } label: { Label(L("Add rule"), systemImage: "plus") }
                                .buttonStyle(.kestrel(.prominent, size: .small))
                            Button { controller.discardSuggestion() } label: { Image(systemName: "xmark") }
                                .buttonStyle(.kestrel(.subtle, size: .small))
                        }
                    }
                }
            }
        }
    }

    /// A human-readable one-liner for a rule's root + criteria.
    private func ruleSummary(_ rule: MaintenanceRule) -> String {
        var parts: [String] = []
        if let d = rule.criteria.olderThanDays { parts.append("\(L("older than")) \(d) \(L("days"))") }
        if let b = rule.criteria.largerThanBytes { parts.append("\(L("larger than")) \(bytesString(b))") }
        if let n = rule.criteria.nameContains, !n.isEmpty { parts.append("\(L("name contains")) “\(n)”") }
        if let e = rule.criteria.extensions, !e.isEmpty { parts.append(".\(e.joined(separator: " / ."))") }
        let where_ = (rule.root as NSString).abbreviatingWithTildeInPath
        return parts.isEmpty ? where_ : "\(where_) · \(parts.joined(separator: ", "))"
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
