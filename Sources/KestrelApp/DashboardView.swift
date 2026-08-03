import SwiftUI
import KestrelCore

/// Compact menu-bar popover: a health summary, live tiles, a one-tap speed test, and a
/// button to open the full window.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tiles
            speedRow
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { model.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HealthRing(score: model.health?.overall ?? 0, size: 62)
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
        LazyVGrid(columns: columns, spacing: 10) {
            if let d = model.disk {
                MetricTile(icon: "internaldrive", title: "Disk", value: "\(Int(d.usedFraction * 100))%",
                           detail: "\(bytesString(d.available)) free", fraction: d.usedFraction, tint: .blue)
            }
            if let m = model.memory {
                MetricTile(icon: "memorychip", title: "Memory", value: "\(Int(m.usedFraction * 100))%",
                           detail: "\(bytesString(m.used)) used", fraction: m.usedFraction, tint: .purple)
            }
            if let c = model.cpu {
                MetricTile(icon: "cpu", title: "CPU", value: String(format: "%.2f", c.loadAverages.first ?? 0),
                           detail: "\(c.coreCount) cores", fraction: min(1, c.pressure), tint: .orange)
            }
            if let b = model.battery {
                MetricTile(icon: batteryIcon(b), title: "Battery", value: "\(b.percent)%",
                           detail: b.healthPercent.map { "health \($0)%" } ?? "", fraction: Double(b.percent) / 100, tint: .green)
            }
        }
    }

    private func batteryIcon(_ b: BatteryStats) -> String {
        b.isCharging ? "battery.100.bolt" : "battery.100"
    }

    private var speedRow: some View {
        Card(padding: 12) {
            HStack {
                Image(systemName: "speedometer").foregroundStyle(.teal)
                if let s = model.speed {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.0f Mbps", s.downloadMbps)).font(.subheadline.weight(.semibold))
                        Text(String(format: "%.0f ms latency", s.latencyMs)).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Internet speed").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.runSpeedTest) {
                    if model.speedTesting { ProgressView().controlSize(.small) }
                    else { Text("Test").font(.callout.weight(.medium)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.speedTesting)
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
            .buttonStyle(.borderedProminent)
            Spacer()
            Button("Quit") { model.quit() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}
