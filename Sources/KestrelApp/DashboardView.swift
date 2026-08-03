import SwiftUI
import KestrelCore

private enum MetricKind: String, Identifiable { case disk, memory, cpu, battery; var id: String { rawValue } }

/// Compact menu-bar popover: a health summary, tappable live tiles that expand a short
/// detail, an animated speed test, and a button to open the full window.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var expanded: MetricKind?

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tiles
            detailArea
            speedSection
            Divider().opacity(0.6)
            footer
        }
        .padding(14)
        .frame(width: 344)
        .fixedSize(horizontal: false, vertical: true)
        .background(popoverBackground)
        // easeOut (no overshoot) so the popover grows smoothly instead of bouncing.
        .animation(.easeOut(duration: 0.16), value: expanded)
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared() }
    }

    private var popoverBackground: some View {
        LinearGradient(
            colors: [Palette.accent.opacity(0.06), .clear],
            startPoint: .topTrailing, endPoint: .center
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            HealthRing(score: model.health?.overall ?? 0, size: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kestrel").font(.title3.weight(.bold))
                Text(healthCaption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var healthCaption: String {
        guard let score = model.health?.overall else { return "Measuring…" }
        switch score {
        case 80...: return "Your Mac looks healthy"
        case 50..<80: return "A little attention needed"
        default: return "Needs attention"
        }
    }

    private var tiles: some View {
        LazyVGrid(columns: columns, spacing: 9) {
            if let d = model.disk {
                tileButton(.disk, icon: "internaldrive", title: "Disk", value: "\(Int(d.usedFraction * 100))%",
                           detail: "\(bytesString(d.available)) free", fraction: d.usedFraction, tint: Palette.blue)
            }
            if let m = model.memory {
                tileButton(.memory, icon: "memorychip", title: "Memory", value: "\(Int(m.usedFraction * 100))%",
                           detail: "\(bytesString(m.used)) used", fraction: m.usedFraction, tint: Palette.violet)
            }
            if let c = model.cpu {
                tileButton(.cpu, icon: "cpu", title: "CPU", value: "\(Int(c.usagePercent.rounded()))%",
                           detail: "\(c.coreCount) cores", fraction: c.usagePercent / 100, tint: Palette.orange)
            }
            if let b = model.battery {
                tileButton(.battery, icon: b.isCharging ? "battery.100.bolt" : "battery.100", title: "Battery",
                           value: "\(b.percent)%", detail: model.batteryCaptionText,
                           fraction: Double(b.percent) / 100, tint: Palette.good)
            }
        }
    }

    private func tileButton(_ kind: MetricKind, icon: String, title: String, value: String, detail: String, fraction: Double, tint: Color) -> some View {
        Button {
            expanded = (expanded == kind) ? nil : kind
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint).imageScale(.small)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded == kind ? 180 : 0))
                }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                ProgressView(value: min(1, max(0, fraction))).tint(fractionColor(fraction))
                Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(expanded == kind ? tint.opacity(0.7) : .white.opacity(0.06), lineWidth: expanded == kind ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Always on screen at a constant height, so toggling details never resizes the
    /// popover (that was the "jumping"). With no tile selected it shows the health
    /// breakdown; tapping a tile swaps in that metric's four details in place.
    private var detailArea: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                detailRows
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .top)
        }
    }

    @ViewBuilder private var detailRows: some View {
        switch expanded {
        case .none:
            ForEach(model.health?.components ?? [], id: \.name) { c in
                HStack(spacing: 8) {
                    Text(c.name).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    ProgressView(value: Double(c.score) / 100).tint(healthColor(c.score))
                    Text("\(c.score)").font(.caption.monospacedDigit().weight(.medium)).frame(width: 26, alignment: .trailing)
                }
            }
        case .disk:
            if let d = model.disk {
                row("Used", bytesString(d.used))
                row("Free", bytesString(d.available))
                row("Purgeable", d.purgeable > 0 ? bytesString(d.purgeable) : "—")
                row("Total", bytesString(d.total))
            }
        case .memory:
            if let m = model.memory {
                row("App", bytesString(m.active))
                row("Wired", bytesString(m.wired))
                row("Compressed", bytesString(m.compressed))
                row("Free", bytesString(m.free))
            }
        case .cpu:
            if let c = model.cpu {
                row("Usage", "\(Int(c.usagePercent.rounded()))%")
                row("Load 1 min", String(format: "%.2f", c.loadAverages[0]))
                row("Load 5 / 15", String(format: "%.2f / %.2f", c.loadAverages[1], c.loadAverages[2]))
                row("Cores", "\(c.coreCount)")
            }
        case .battery:
            if let b = model.battery {
                row("Charge", "\(b.percent)%")
                row("State", b.isCharging ? "Charging" : "On battery")
                if b.isCharging, let m = b.timeToFullMinutes { row("Full in", minutesString(m)) }
                else if !b.isCharging, let m = b.timeToEmptyMinutes { row("Time left", minutesString(m)) }
                else { row("Health", b.healthPercent.map { "\($0)%" } ?? "—") }
                row("Cycles", b.cycleCount.map { "\($0)" } ?? "—")
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private var speedSection: some View {
        Card(padding: 12) {
            HStack(spacing: 14) {
                SpeedGauge(mbps: model.speedDisplay, testing: model.speedTesting, size: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Internet speed").font(.subheadline.weight(.semibold))
                    if let s = model.speed, !model.speedTesting {
                        Text(String(format: "%.0f ms latency", s.latencyMs)).font(.caption).foregroundStyle(.secondary)
                    } else if model.speedTesting {
                        Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Download & latency").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: model.runSpeedTest) {
                        Text(model.speedTesting ? "Testing…" : "Run test")
                    }
                    .buttonStyle(.kestrel(.prominent, tint: Palette.teal, size: .small))
                    .disabled(model.speedTesting)
                    .padding(.top, 1)
                }
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.openMainWindow(openWindow)
            } label: {
                Label("Open Kestrel", systemImage: "macwindow")
            }
            .buttonStyle(.kestrel)
            Spacer()
            Button("Quit") { model.quit() }
                .buttonStyle(.kestrel(.subtle, size: .small))
        }
    }
}
