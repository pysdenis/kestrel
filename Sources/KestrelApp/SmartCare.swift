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

    // MARK: run / progress

    private var runCard: some View {
        Card(elevated: true, tint: Palette.accent) {
            if controller.running {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ScanRadar(tint: Palette.accent, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Running Smart Care…").font(.title3.weight(.bold))
                            Text(controller.status.isEmpty ? "Working…" : controller.status)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .animation(nil, value: controller.status)
                        }
                        Spacer()
                    }
                    VStack(spacing: 8) {
                        SmartStepRow(label: "Reclaimable space", state: controller.cleanupStep, tint: Palette.accent)
                        SmartStepRow(label: "macOS protection", state: controller.protectionStep, tint: Palette.good)
                        SmartStepRow(label: "Downloads malware scan", state: controller.malwareStep, tint: Palette.violet)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Palette.accent.opacity(0.14)).frame(width: 60, height: 60)
                        Image(systemName: "wand.and.stars").font(.system(size: 26)).foregroundStyle(Palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controller.finished ? "Smart Care complete" : "Run Smart Care").font(.title2.weight(.bold))
                        Text(controller.finished
                             ? "Here's what it found — nothing was deleted."
                             : "Reclaimable space, macOS protection and a Downloads malware scan, in one honest pass.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: start) { Label(controller.finished ? "Run again" : "Run", systemImage: "play.fill") }
                        .buttonStyle(.kestrel(.prominent))
                }
            }
        }
    }

    // MARK: results

    @ViewBuilder private var results: some View {
        LazyVGrid(columns: tiles, spacing: 12) {
            resultTile(icon: "gauge.with.dots.needle.67percent", title: "Health",
                       value: "\(model.health?.overall ?? 0)",
                       subtitle: healthVerdict(model.health?.overall ?? 0),
                       tint: healthColor(model.health?.overall ?? 0))
            if let p = controller.protection {
                let ok = p.assessmentsEnabled == true && p.xprotectVersion != nil
                resultTile(icon: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill", title: "Protection",
                           value: ok ? "On" : "Check",
                           subtitle: ok ? "Gatekeeper + XProtect active" : "A defense is off",
                           tint: ok ? Palette.good : Palette.warn)
            }
            if let r = controller.report {
                resultTile(icon: r.isClean ? "checkmark.seal.fill" : "xmark.octagon.fill", title: "Malware",
                           value: r.isClean ? "Clean" : "\(r.findings.count)",
                           subtitle: r.isClean ? "Downloads · \(r.scanned) files" : "finding(s) with evidence",
                           tint: r.isClean ? Palette.good : Palette.crit)
            }
        }

        cleanupResult
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
                            Text("Nothing to reclaim").font(.title3.weight(.bold))
                            Text("Your Home folder is already tidy.").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("\(bytesString(plan.totalBytes)) reclaimable").font(.title3.weight(.bold))
                            Text("\(plan.count) safe item(s) across caches, logs and dev artifacts.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !plan.items.isEmpty {
                        HStack(spacing: 8) {
                            Button { model.section = .cleanup } label: { Text("Review") }
                                .buttonStyle(.kestrel(.subtle, size: .small))
                            Button { controller.apply() } label: {
                                if controller.applying { KestrelSpinner(tint: .white, size: 15) }
                                else { Label("Move to Vault", systemImage: "tray.and.arrow.down") }
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
            Text(stateText).font(.caption).foregroundStyle(state == .done ? Palette.good : .secondary)
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
        }
    }

    private var stateText: String {
        switch state {
        case .pending: return "Waiting"
        case .running: return "Scanning…"
        case .done: return "Done"
        }
    }
}
