import SwiftUI
import KestrelCore

/// Smart Care — one honest orchestrated pass: reclaimable space, macOS protection and a
/// Downloads malware scan, reported as one result. Nothing is deleted here; the cleanup
/// is applied only when the user chooses to move it to the vault.
struct SmartCareSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: SmartCareController

    private let tiles = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        SectionScaffold(title: "Smart Care", subtitle: "One honest pass across cleanup, protection and malware") {
            runCard

            if let message = controller.message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good).font(.callout)
            }

            if controller.finished { results }
        }
    }

    private func start() {
        let home = model.paths.home
        controller.run(home: home, downloads: home.appendingPathComponent("Downloads"))
    }

    /// A selectable chip for one Smart Care step — fills with the accent when included.
    private func stepToggle(_ step: SmartCareController.Step) -> some View {
        let on = controller.isStepOn(step)
        return Button { controller.toggleStep(step) } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.caption)
                Image(systemName: step.icon).font(.caption)
                Text(L(step.title)).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.secondary)
            .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.quaternary), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: run / progress

    private var runCard: some View {
        Card(elevated: true, tint: Palette.accent) {
            if controller.running {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ScanRadar(tint: Palette.accent, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("Running Smart Care…")).font(.title3.weight(.bold))
                            Text(controller.status.isEmpty ? L("Working…") : controller.status)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .animation(nil, value: controller.status)
                        }
                        Spacer()
                    }
                    VStack(spacing: 8) {
                        SmartStepRow(label: L("Reclaimable space"), state: controller.cleanupStep, tint: Palette.accent)
                        SmartStepRow(label: L("macOS protection"), state: controller.protectionStep, tint: Palette.good)
                        SmartStepRow(label: L("Downloads malware scan"), state: controller.malwareStep, tint: Palette.violet)
                        SmartStepRow(label: L("App updates"), state: controller.updatesStep, tint: Palette.accent2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().fill(Palette.accent.opacity(0.14)).frame(width: 60, height: 60)
                            Image(systemName: "wand.and.stars").font(.system(size: 26)).foregroundStyle(Palette.accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(controller.finished ? L("Smart Care complete") : L("Run Smart Care")).font(.title2.weight(.bold))
                            Text(controller.finished
                                 ? L("Here's what it found — nothing was deleted.")
                                 : L("Pick the checks below, then run them in one honest pass."))
                                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(action: start) { Label(controller.finished ? L("Run again") : L("Run"), systemImage: "play.fill") }
                            .buttonStyle(.kestrel(.prominent))
                            .disabled(controller.enabledSteps.isEmpty)
                    }
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(SmartCareController.Step.allCases) { step in
                            stepToggle(step)
                        }
                    }
                }
            }
        }
    }

    // MARK: results

    @ViewBuilder private var results: some View {
        LazyVGrid(columns: tiles, spacing: 12) {
            resultTile(icon: "gauge.with.dots.needle.67percent", title: L("Health"),
                       value: "\(model.health?.overall ?? 0)",
                       subtitle: L(healthVerdict(model.health?.overall ?? 0)),
                       tint: healthColor(model.health?.overall ?? 0))
            if let p = controller.protection {
                let ok = p.assessmentsEnabled == true && p.xprotectVersion != nil
                resultTile(icon: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill", title: L("Protection"),
                           value: ok ? L("On") : L("Check"),
                           subtitle: ok ? L("Gatekeeper + XProtect active") : L("A defense is off"),
                           tint: ok ? Palette.good : Palette.warn)
            }
            if let r = controller.report {
                resultTile(icon: r.isClean ? "checkmark.seal.fill" : "xmark.octagon.fill", title: L("Malware"),
                           value: r.isClean ? L("No threats") : "\(r.findings.count)",
                           subtitle: r.isClean ? "\(L("Downloads")) · \(r.scanned) \(L("files"))" : L("finding(s) with evidence"),
                           tint: r.isClean ? Palette.good : Palette.crit)
            }
            if controller.updatesStep == .done {
                let n = controller.updates.count
                resultTile(icon: n == 0 ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill", title: L("App updates"),
                           value: n == 0 ? L("Up to date") : "\(n)",
                           subtitle: n == 0 ? L("Every Homebrew app is current") : L("app(s) have a newer version"),
                           tint: n == 0 ? Palette.good : Palette.accent2)
            }
        }

        if controller.updatesStep == .done, !controller.updates.isEmpty { updatesResult }
        cleanupResult
    }

    @ViewBuilder private var updatesResult: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("App updates", icon: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button { model.section = .applications } label: { Label(L("Review"), systemImage: "arrow.right") }
                        .buttonStyle(.kestrel(.subtle, size: .small))
                }
                ForEach(Array(controller.updates.prefix(8).enumerated()), id: \.offset) { i, u in
                    if i > 0 { Hairline() }
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox").font(.caption).foregroundStyle(Palette.accent2)
                        Text(u.name).font(.callout).lineLimit(1)
                        Spacer()
                        Text("\(u.current) → \(u.latest)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func resultTile(icon: String, title: String, value: String, subtitle: String, tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(tint).imageScale(.medium)
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var cleanupResult: some View {
        if let plan = controller.plan {
            Card(elevated: true, tint: plan.items.isEmpty ? Palette.good : Palette.accent) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill((plan.items.isEmpty ? Palette.good : Palette.accent).opacity(0.14)).frame(width: 54, height: 54)
                        Image(systemName: plan.items.isEmpty ? "checkmark" : "sparkles")
                            .font(.title2).foregroundStyle(plan.items.isEmpty ? Palette.good : Palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if plan.items.isEmpty {
                            Text(L("Nothing to reclaim")).font(.title3.weight(.bold))
                            Text(L("Your Home folder is already tidy.")).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("\(bytesString(plan.totalBytes)) \(L("reclaimable"))").font(.title3.weight(.bold))
                            Text("\(plan.count) \(L("safe item(s) across caches, logs and dev artifacts."))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !plan.items.isEmpty {
                        HStack(spacing: 8) {
                            Button { model.section = .cleanup } label: { Text(L("Review")) }
                                .buttonStyle(.kestrel(.subtle, size: .small))
                            Button { controller.apply() } label: {
                                if controller.applying { KestrelSpinner(tint: .white, size: 15) }
                                else { Label(L("Move to Vault"), systemImage: "tray.and.arrow.down") }
                            }
                            .buttonStyle(.kestrel(.prominent))
                            .disabled(controller.applying)
                        }
                    }
                }
            }
        }
    }
}

/// One line in the Smart Care progress checklist: a state glyph, a label, and a status.
struct SmartStepRow: View {
    let label: String
    let state: SmartCareController.StepState
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            glyph
            Text(label).font(.callout).foregroundStyle(state == .pending ? .secondary : .primary)
            Spacer()
            Text(L(stateText)).font(.caption).foregroundStyle(state == .done ? Palette.good : .secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .pending:
            Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 2).frame(width: 18, height: 18)
        case .running:
            KestrelSpinner(tint: tint, size: 18)
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.good)
        case .skipped:
            Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(.tertiary)
        }
    }

    private var stateText: String {
        switch state {
        case .pending: return "Waiting"
        case .running: return "Scanning…"
        case .done: return "Done"
        case .skipped: return "Skipped"
        }
    }
}
