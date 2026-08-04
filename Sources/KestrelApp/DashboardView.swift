import SwiftUI
import KestrelCore

enum DetailKind: String, Identifiable { case storage, memory, battery, cpu, network; var id: String { rawValue } }

/// The menu-bar popover — Kestrel's own layout (not a CleanMyMac clone): a compact
/// header with the health ring, a single "instrument cluster" row of mini-gauges, a
/// dev-first free-up action, and a speed check. Tapping a gauge navigates to a rich
/// full-width detail (back to return) rather than a side panel.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var detail: DetailKind?

    var body: some View {
        Group {
            if let detail {
                DetailPanel(kind: detail, onBack: back)
            } else {
                overview
            }
        }
        .padding(14)
        .frame(width: 366)
        .background(LinearGradient(colors: [Palette.accent.opacity(0.06), .clear], startPoint: .topTrailing, endPoint: .center).ignoresSafeArea())
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared() }
    }

    // Mutating `detail` synchronously inside a button tap makes the .window-style
    // MenuBarExtra popover treat the in-place hierarchy swap as a dismissal and close.
    // Deferring the change to the next runloop tick lets the click finish first, so
    // opening a detail and pressing Back navigate within the popover instead of closing it.
    private func open(_ kind: DetailKind) {
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.18)) { detail = kind } }
    }
    private func back() {
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.18)) { detail = nil } }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            cluster
            actionCard
            speedRow
            Hairline().opacity(0.7)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "bird.fill")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Palette.kestrel, Palette.kestrel.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                           in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Kestrel").font(.title3.weight(.bold))
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HealthRing(score: model.health?.overall ?? 0, size: 46)
        }
    }

    private var caption: String {
        switch model.health?.overall ?? 0 {
        case 80...: return L("Everything looks healthy")
        case 50..<80: return L("A little attention needed")
        default: return L("Needs attention")
        }
    }

    private var cluster: some View {
        HStack(spacing: 6) {
            if let d = model.disk {
                MetricChip(icon: "internaldrive", label: L("Disk"), value: "\(Int(d.usedFraction * 100))%", fraction: d.usedFraction, tint: Palette.blue, selected: false) { open(.storage) }
            }
            if let m = model.memory {
                MetricChip(icon: "memorychip", label: L("Memory"), value: "\(Int(m.usedFraction * 100))%", fraction: m.usedFraction, tint: Palette.violet, selected: false) { open(.memory) }
            }
            if let c = model.cpu {
                MetricChip(icon: "cpu", label: L("CPU"), value: "\(Int(c.usagePercent.rounded()))%", fraction: c.usagePercent / 100, tint: Palette.warn, selected: false) { open(.cpu) }
            }
            if let b = model.battery {
                MetricChip(icon: "bolt.fill", label: L("Battery"), value: "\(b.percent)%", fraction: Double(b.percent) / 100, tint: Palette.good, selected: false) { open(.battery) }
            }
            MetricChip(icon: "wifi", label: L("Network"), value: netRate, fraction: 0, tint: Palette.accent, selected: false) { open(.network) }
        }
    }

    private var netRate: String {
        let bps = model.netDownBps
        if bps <= 0 { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .memory).replacingOccurrences(of: " bytes", with: " B")
    }

    private var actionCard: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Free up space")).font(.subheadline.weight(.semibold))
                        Text(L("Dev junk, caches, duplicates & more")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button { model.freeDevJunk(openWindow) } label: { Label(L("Clean dev junk"), systemImage: "hammer") }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                    Button { model.section = .cleanup; model.openMainWindow(openWindow) } label: { Text(L("Review all")) }
                        .buttonStyle(.kestrel(.secondary, size: .small))
                    Spacer()
                }
                Hairline().opacity(0.6)
                HStack(spacing: 8) {
                    quickAction(L("Free RAM"), "memorychip", Palette.violet, busy: model.freeingMemory) { model.freeMemory() }
                    quickAction(L("Empty Trash"), "trash", Palette.good, busy: model.quickBusy) { model.emptyTrashQuick() }
                    quickAction(L("Smart Care"), "sparkles", Palette.accent) { model.runSmartCare(openWindow) }
                }
                if let msg = model.quickActionMessage {
                    Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, _ tint: Color, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // Normalise every glyph to the same square so SF Symbols with different
                // intrinsic sizes (memorychip vs sparkles) don't look uneven in the grid.
                ZStack {
                    if busy { KestrelSpinner(tint: tint, size: 18) }
                    else {
                        Image(systemName: icon).resizable().aspectRatio(contentMode: .fit)
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 18, height: 18)
                Text(title).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var speedRow: some View {
        Card(padding: 12) {
            HStack(spacing: 13) {
                SpeedGauge(mbps: model.speedDisplay, testing: model.speedTesting, size: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Internet speed")).font(.subheadline.weight(.semibold))
                    if let s = model.speed, !model.speedTesting {
                        Text(String(format: "%.0f ms latency", s.latencyMs)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(model.speedTesting ? L("Measuring…") : L("Download & latency")).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(model.speedTesting ? L("Testing…") : L("Run test"), action: model.runSpeedTest)
                        .buttonStyle(.kestrel(.prominent, tint: Palette.accent, size: .small)).disabled(model.speedTesting).padding(.top, 1)
                }
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button { model.openMainWindow(openWindow) } label: { Label(L("Open Kestrel"), systemImage: "macwindow") }
                .buttonStyle(.kestrel)
            Spacer()
            Button(L("Quit")) { model.quit() }.buttonStyle(.kestrel(.subtle, size: .small))
        }
    }
}

// MARK: - Instrument cluster chip

struct MetricChip: View {
    let icon: String
    let label: String
    let value: String
    let fraction: Double
    let tint: Color
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3.5)
                    if fraction > 0 {
                        Circle().trim(from: 0, to: min(1, fraction))
                            .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                Text(value).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? Palette.accent.opacity(0.12) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail panel (full-width, back to return)

struct DetailPanel: View {
    let kind: DetailKind
    let onBack: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.body.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Text(title).font(.title3.weight(.bold))
                Spacer()
            }
            content
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        switch kind {
        case .storage: return "Storage"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .cpu: return model.cpuBrand
        case .network: return "Network"
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .storage: StorageDetailView()
        case .memory: MemoryDetailView()
        case .battery: BatteryDetailView()
        case .cpu: CPUDetailView()
        case .network: NetworkDetailView()
        }
    }
}

// MARK: - Memory detail

struct MemoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let m = model.memory {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(m.usedFraction * 100))%").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(bytesString(m.used)) used of \(bytesString(m.total))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Card {
                    VStack(spacing: 10) {
                        let total = max(1, m.total)
                        LabeledBar(label: "App", value: bytesString(m.active), fraction: Double(m.active) / Double(total), tint: Palette.violet)
                        LabeledBar(label: "Wired", value: bytesString(m.wired), fraction: Double(m.wired) / Double(total), tint: Palette.accent)
                        LabeledBar(label: "Compressed", value: bytesString(m.compressed), fraction: Double(m.compressed) / Double(total), tint: Palette.warn)
                        LabeledBar(label: "Free", value: bytesString(m.free), fraction: Double(m.free) / Double(total), tint: Palette.good)
                    }
                }
            }
        } else { Text(L("Memory unavailable.")).foregroundStyle(.secondary) }
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
        } else { Text(L("No battery.")).foregroundStyle(.secondary) }
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
                if model.cpuHistory.count > 1 {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Recent load")).font(.caption).foregroundStyle(.secondary)
                            Sparkline(values: model.cpuHistory, tint: Palette.warn).frame(height: 34)
                        }
                    }
                }
                Card(padding: 12) {
                    HStack { Image(systemName: "clock").foregroundStyle(Palette.warn); Text(L("Uptime")).font(.subheadline.weight(.medium)); Spacer(); Text("\(model.uptimeDays)d").font(.subheadline.weight(.semibold)) }
                }
            }
            Text(L("Top Consumers")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if model.energyNow.isEmpty {
                HStack(spacing: 8) { KestrelSpinner(tint: Palette.warn, size: 14); Text(L("Reading…")).foregroundStyle(.secondary).font(.caption) }
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
                        Text(L("Wi-Fi connection")).font(.caption).foregroundStyle(.secondary)
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
                        Text(L("Test your connection")).font(.subheadline.weight(.semibold))
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

            // Volume capacity only — no directory walk, so this never triggers a Photos /
            // Documents / Downloads permission prompt. The full folder breakdown lives in
            // the Space section, where you navigate to it deliberately.
            let volumes = model.volumes()
            if !volumes.isEmpty {
                Text(L("Volumes")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(volumes, id: \.name) { v in
                    LabeledBar(label: v.name, value: "\(bytesString(v.space.used)) / \(bytesString(v.space.total))",
                               fraction: v.space.usedFraction, tint: Palette.accent)
                }
            }
        }
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
