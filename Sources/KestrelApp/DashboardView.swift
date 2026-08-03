import SwiftUI
import KestrelCore

/// The menu-bar dashboard: a Mac Health header, live tiles, and a one-click dry-run
/// scan. No placebo controls — every value is real and every action maps to Core.
struct DashboardView: View {
    @StateObject private var model = DashboardModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            tiles
            Divider()
            freeUp
            Divider()
            footer
        }
        .padding(14)
        .onAppear { model.start() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "bird.fill").foregroundStyle(.tint)
            Text("Kestrel").font(.headline)
            Spacer()
            if let health = model.health {
                Text("\(health.overall)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: health.overall))
                Text("/ 100").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    private var tiles: some View {
        VStack(spacing: 8) {
            if let disk = model.disk {
                Tile(label: "Disk", value: "\(Int(disk.usedFraction * 100))% full",
                     fraction: disk.usedFraction, detail: bytes(disk.used) + " / " + bytes(disk.total))
            }
            if let memory = model.memory {
                Tile(label: "Memory", value: "\(Int(memory.usedFraction * 100))% used",
                     fraction: memory.usedFraction, detail: bytes(memory.used) + " / " + bytes(memory.total))
            }
            if let cpu = model.cpu {
                Tile(label: "CPU", value: String(format: "load %.2f", cpu.loadAverages.first ?? 0),
                     fraction: min(1, cpu.pressure), detail: "\(cpu.coreCount) cores")
            }
            if let battery = model.battery {
                Tile(label: "Battery", value: "\(battery.percent)%",
                     fraction: Double(battery.percent) / 100,
                     detail: battery.healthPercent.map { "health \($0)%" } ?? (battery.isCharging ? "charging" : ""))
            }
        }
    }

    private var freeUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    model.scan(path: "~/Developer")
                } label: {
                    Label("Scan ~/Developer", systemImage: "sparkles")
                }
                .disabled(model.scanning)
                if model.scanning { ProgressView().controlSize(.small) }
            }
            if let summary = model.scanSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Dry-run — nothing is deleted without confirmation")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// A single live metric row with a progress bar.
private struct Tile: View {
    let label: String
    let value: String
    let fraction: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, max(0, fraction)))
                .tint(fraction > 0.9 ? .red : (fraction > 0.75 ? .yellow : .accentColor))
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
