import SwiftUI
import KestrelCore

enum DetailKind: String, Identifiable { case storage, battery, cpu, network; var id: String { rawValue } }

/// The menu-bar popover, modelled on CleanMyMac's two-panel layout in Kestrel's Precision
/// style: a compact "Mac Health" panel of tiles on the right, and a rich detail panel
/// that slides in on the left when a tile is tapped.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var detail: DetailKind?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let detail {
                DetailPanel(kind: detail) { self.detail = nil }
                    .frame(width: 338)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            tiles.frame(width: 340)
        }
        .padding(13)
        .frame(width: detail == nil ? 366 : 716)
        .background(background)
        .animation(.easeOut(duration: 0.22), value: detail)
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared() }
    }

    private var background: some View {
        LinearGradient(colors: [Palette.accent.opacity(0.06), .clear], startPoint: .topTrailing, endPoint: .center).ignoresSafeArea()
    }

    // MARK: - Mac Health tiles

    private var verdict: (text: String, color: Color) {
        switch model.health?.overall ?? 0 {
        case 80...: return ("Good", Palette.accent)
        case 50..<80: return ("Fair", Palette.warn)
        default: return ("Needs attention", Palette.crit)
        }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Mac Health:").font(.title3.weight(.bold))
                        Text(verdict.text).font(.title3.weight(.bold)).foregroundStyle(verdict.color)
                    }
                    Text("Your Mac").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(Palette.accent)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                if let d = model.disk {
                    HealthTile(icon: "internaldrive", title: "Macintosh HD", subtitle: "Available: \(bytesString(d.available))",
                               warnSubtitle: true, action: ("Free Up", openMain), selected: detail == .storage) { detail = .storage }
                }
                if let m = model.memory {
                    HealthTile(icon: "memorychip", title: "Memory", subtitle: "Pressure: \(Int(m.usedFraction * 100))%",
                               warnSubtitle: true, action: ("Optimize", openMain))
                }
                if let b = model.battery {
                    HealthTile(icon: b.isCharging ? "battery.100.bolt" : "battery.100", title: "Battery", value: "\(b.percent)%",
                               subtitle: model.batteryTimeMinutes.map { "\(minutesString($0)) remaining" } ?? "", selected: detail == .battery) { detail = .battery }
                }
                if let c = model.cpu {
                    HealthTile(icon: "cpu", title: "CPU", subtitle: "Load: \(Int(c.usagePercent.rounded()))%", selected: detail == .cpu) { detail = .cpu }
                }
                if let n = model.network {
                    HealthTile(icon: "wifi", title: n.ssid ?? "Network",
                               subtitle: "↑ \(rate(model.netUpBps))   ↓ \(rate(model.netDownBps))",
                               action: ("Test Speed", { model.runSpeedTest(); detail = .network }), selected: detail == .network) { detail = .network }
                }
                HealthTile(icon: "externaldrive", title: "External Drives", subtitle: externalText)
            }

            recommendation
            Spacer(minLength: 0)
            footer
        }
    }

    private var externalText: String {
        let externals = model.volumes().filter { !$0.name.contains("Macintosh") }.count
        return externals > 0 ? "\(externals) connected" : "No devices connected"
    }

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Recommendation").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Card(padding: 12) {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: recommendationIcon).font(.title2).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recommendationTitle).font(.subheadline.weight(.semibold))
                        Text(recommendationBody).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Open Kestrel", action: openMain).buttonStyle(.kestrel(.secondary, size: .small)).padding(.top, 4)
                    }
                }
            }
        }
    }

    private var recommendationIcon: String { (model.disk?.usedFraction ?? 0) > 0.85 ? "sparkles" : "checkmark.seal" }
    private var recommendationTitle: String { (model.disk?.usedFraction ?? 0) > 0.85 ? "Free up disk space" : "Your Mac looks healthy" }
    private var recommendationBody: String {
        (model.disk?.usedFraction ?? 0) > 0.85
            ? "Your disk is nearly full. Review reclaimable clutter to keep things fast."
            : "Nothing urgent right now. Open Kestrel to review clutter, security and more."
    }

    private var footer: some View {
        HStack {
            Button { openMain() } label: { Image(systemName: "desktopcomputer") }.buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Button("Open Kestrel", action: openMain).buttonStyle(.kestrel(.prominent, size: .small))
            Spacer()
            Button { model.quit() } label: { Image(systemName: "power") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func openMain() { model.openMainWindow(openWindow) }
    private func rate(_ bps: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s" }
}

// MARK: - Health tile

struct HealthTile: View {
    let icon: String
    let title: String
    var value: String? = nil
    var subtitle: String = ""
    var warnSubtitle: Bool = false
    var action: (label: String, run: () -> Void)? = nil
    var selected: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(.secondary).imageScale(.medium)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if let value { Text(value).font(.subheadline.weight(.semibold)).monospacedDigit() }
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(warnSubtitle ? Palette.warn : .secondary).lineLimit(1)
            }
            if let action {
                Button(action.label) { action.run() }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? Palette.accent : .white.opacity(0.06), lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Detail panel

struct DetailPanel: View {
    let kind: DetailKind
    let onBack: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onBack) { Image(systemName: "chevron.left") }.buttonStyle(.plain).foregroundStyle(.secondary)
                Text(title).font(.title3.weight(.bold))
                Spacer()
            }
            content
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch kind {
        case .storage: return "Macintosh HD"
        case .battery: return "Battery"
        case .cpu: return model.cpuBrand
        case .network: return "Network"
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .storage: StorageDetailView()
        case .battery: BatteryDetailView()
        case .cpu: CPUDetailView()
        case .network: NetworkDetailView()
        }
    }
}

// MARK: - Battery detail

struct BatteryDetailView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let b = model.battery {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        SegmentedRing(fraction: Double(b.percent) / 100, tint: b.percent > 20 ? Palette.good : Palette.crit, size: 150)
                        VStack(spacing: 0) {
                            Text("\(b.percent)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("%").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(b.isCharging ? "Charging" : "Discharging").font(.headline)
                        if let m = model.batteryTimeMinutes {
                            Text(b.isCharging ? "About \(minutesString(m)) until full" : "About \(minutesString(m)) until empty")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(b.cycleCount ?? 0) / 1000").font(.title3.weight(.semibold)).monospacedDigit().padding(.top, 4)
                        Text("charge cycles").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    infoCard(icon: "heart.fill", tint: Palette.pink, title: "Health", value: b.healthPercent.map { "\($0)%" } ?? "—",
                             note: (b.healthPercent ?? 100) >= 80 ? "Your battery is in good condition." : "Your battery has lost some capacity.")
                    infoCard(icon: "thermometer.medium", tint: Palette.warn, title: "Temperature", value: b.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—",
                             note: "Within its normal working range.")
                }
            }
        } else { Text("No battery.").foregroundStyle(.secondary) }
    }

    private func infoCard(icon: String, tint: Color, title: String, value: String, note: String) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Image(systemName: icon).foregroundStyle(tint); Text(title).font(.subheadline.weight(.medium)); Spacer(); Text(value).font(.subheadline.weight(.semibold)) }
                Text(note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - CPU detail

struct CPUDetailView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = model.cpu {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(c.usagePercent.rounded()))%").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("used · load \(String(format: "%.2f", c.loadAverages.first ?? 0)) · \(c.coreCount) cores").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Card(padding: 12) {
                    HStack { Image(systemName: "clock").foregroundStyle(Palette.warn); Text("Uptime").font(.subheadline.weight(.medium)); Spacer(); Text("\(model.uptimeDays)d").font(.subheadline.weight(.semibold)) }
                }
            }
            Text("Top Consumers").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if model.energyNow.isEmpty {
                HStack { ProgressView().controlSize(.small); Text("Reading…").foregroundStyle(.secondary).font(.caption) }
            } else {
                ForEach(model.energyNow.prefix(6)) { proc in
                    HStack {
                        Text(proc.name).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.1f%%", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { model.energyAppeared() }
        .onDisappear { model.energyDisappeared() }
    }
}

// MARK: - Network detail

struct NetworkDetailView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let n = model.network {
                HStack(spacing: 10) {
                    Image(systemName: "wifi").font(.title2).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.ssid ?? "Network").font(.headline)
                        Text("Wi-Fi connection").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    trafficCard(title: "Download", total: n.bytesIn, rate: model.netDownBps)
                    trafficCard(title: "Upload", total: n.bytesOut, rate: model.netUpBps)
                }
            }
            Card {
                HStack(spacing: 14) {
                    SpeedGauge(mbps: model.speedDisplay, testing: model.speedTesting, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Test your connection").font(.subheadline.weight(.semibold))
                        if let s = model.speed, !model.speedTesting {
                            Text(String(format: "%.0f Mbps · %.0f ms", s.downloadMbps, s.latencyMs)).font(.caption).foregroundStyle(.secondary)
                        }
                        Button(model.speedTesting ? "Testing…" : "Run test", action: model.runSpeedTest)
                            .buttonStyle(.kestrel(.prominent, tint: Palette.accent, size: .small)).disabled(model.speedTesting)
                    }
                    Spacer()
                }
            }
        }
    }

    private func trafficCard(title: String, total: Int64, rate: Double) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(bytesString(total)).font(.title3.weight(.semibold)).monospacedDigit()
                Text(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file) + "/s").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Storage detail

struct StorageDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tree: DirNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let d = model.disk {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.1), lineWidth: 12)
                        Circle().trim(from: 0, to: d.usedFraction)
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(bytesString(d.available)).font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("available").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 5) {
                        legend(color: Palette.accent, label: "Used", value: bytesString(d.used))
                        legend(color: .primary.opacity(0.15), label: "Free", value: bytesString(d.available))
                        if d.purgeable > 0 { legend(color: Palette.warn, label: "Purgeable", value: bytesString(d.purgeable)) }
                    }
                    Spacer()
                }
            }
            Text("Largest folders in Home").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if let tree {
                ForEach(Array(tree.children.prefix(5)), id: \.url) { child in
                    LabeledBar(label: child.name, value: bytesString(child.size),
                               fraction: tree.size > 0 ? Double(child.size) / Double(tree.size) : 0, tint: Palette.accent)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary).font(.caption) }
            }
        }
        .task { if tree == nil {
            let home = model.paths.home
            let measured = await Task.detached { DiskMap().measure(home, maxDepth: 1) }.value
            tree = measured
        } }
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }
}
