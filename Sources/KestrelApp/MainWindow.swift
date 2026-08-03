import SwiftUI
import KestrelCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, cleanup, space, energy, security, tools, assistant, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .cleanup: return "Cleanup"
        case .space: return "Space"
        case .energy: return "Energy"
        case .security: return "Security"
        case .tools: return "Tools"
        case .assistant: return "Assistant"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleanup: return "sparkles"
        case .space: return "chart.pie"
        case .energy: return "bolt.fill"
        case .security: return "shield.lefthalf.filled"
        case .tools: return "wrench.and.screwdriver"
        case .assistant: return "bubble.left.and.sparkles"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// The full window: a sidebar of sections, each backed by KestrelCore.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Section("Monitor") { row(.dashboard); row(.energy); row(.space) }
                Section("Maintain") { row(.cleanup); row(.security); row(.tools) }
                Section("Intelligence") { row(.assistant) }
                Section { row(.activity); row(.settings) }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 520)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared(); model.mainWindowClosed() }
        .sheet(isPresented: $model.showPalette) { CommandPaletteView().environmentObject(model) }
    }

    private func row(_ item: AppSection) -> some View {
        Label(item.title, systemImage: item.icon).tag(item)
    }

    @ViewBuilder private var detail: some View {
        switch model.section ?? .dashboard {
        case .dashboard: DashboardSection()
        case .cleanup: CleanupSection()
        case .space: SpaceSection()
        case .energy: EnergySection()
        case .security: SecuritySection()
        case .tools: ToolsSection()
        case .assistant: AssistantSection()
        case .activity: ActivitySection()
        case .settings: SettingsSection()
        }
    }
}

/// A scroll container with a consistent title + padding for every section.
struct SectionScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.largeTitle.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Dashboard

struct DashboardSection: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        SectionScaffold(title: "Dashboard", subtitle: "Live health and system metrics") {
            Card {
                HStack(spacing: 18) {
                    HealthRing(score: model.health?.overall ?? 0, size: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mac Health").font(.title2.weight(.semibold))
                        ForEach(model.health?.components ?? [], id: \.name) { c in
                            HStack {
                                Text(c.name).frame(width: 70, alignment: .leading).font(.callout)
                                ProgressView(value: Double(c.score) / 100).tint(healthColor(c.score))
                                Text("\(c.score)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                    Spacer()
                }
            }

            Card {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.title).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free up space").font(.headline)
                        Text("Review reclaimable clutter — dev junk, caches, duplicates & more").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Review") { model.section = .cleanup }.buttonStyle(.kestrel(.prominent))
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                if let d = model.disk {
                    RadialMetricTile(icon: "internaldrive", title: "Disk", centerValue: "\(Int(d.usedFraction * 100))%",
                                     fraction: d.usedFraction,
                                     detail: "\(bytesString(d.available)) free", iconTint: Palette.blue, ringColor: fractionColor(d.usedFraction))
                }
                if let m = model.memory {
                    RadialMetricTile(icon: "memorychip", title: "Memory", centerValue: "\(Int(m.usedFraction * 100))%",
                                     fraction: m.usedFraction,
                                     detail: "\(bytesString(m.used)) used", iconTint: Palette.violet, ringColor: fractionColor(m.usedFraction))
                }
                if let c = model.cpu {
                    RadialMetricTile(icon: "cpu", title: "CPU", centerValue: "\(Int(c.usagePercent.rounded()))%",
                                     fraction: c.usagePercent / 100,
                                     detail: "\(c.coreCount) cores", iconTint: Palette.warn, ringColor: fractionColor(c.usagePercent / 100))
                }
                if let b = model.battery {
                    RadialMetricTile(icon: b.isCharging ? "battery.100.bolt" : "battery.75", title: "Battery", centerValue: "\(b.percent)%",
                                     fraction: Double(b.percent) / 100,
                                     detail: model.batteryCaptionText, iconTint: Palette.good, ringColor: b.percent > 20 ? Palette.good : Palette.crit)
                }
                if model.network != nil {
                    NetworkTile(ssid: model.network?.ssid, downBps: model.netDownBps,
                                upBps: model.netUpBps, history: model.netHistory)
                }
            }

            SpeedTestCard()
        }
    }
}

struct SpeedTestCard: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Card {
            HStack(spacing: 18) {
                SpeedGauge(mbps: model.speedDisplay, testing: model.speedTesting, size: 108)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Internet speed").font(.headline)
                    if let s = model.speed, !model.speedTesting {
                        Text(String(format: "%.0f Mbps download", s.downloadMbps)).font(.subheadline)
                        Text(String(format: "%.0f ms latency · via Cloudflare", s.latencyMs)).font(.caption).foregroundStyle(.secondary)
                    } else if model.speedTesting {
                        Text("Measuring your connection…").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Measure download speed and latency").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button(action: model.runSpeedTest) {
                        Label(model.speedTesting ? "Testing…" : "Run test", systemImage: "play.fill")
                    }
                    .buttonStyle(.kestrel(.prominent, tint: Palette.teal))
                    .disabled(model.speedTesting)
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Space

struct SpaceSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var tree: DirNode?
    @State private var loading = false

    var body: some View {
        SectionScaffold(title: "Space", subtitle: "Where your storage is going") {
            if let d = model.disk {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(bytesString(d.used)) used").font(.headline)
                            Spacer()
                            Text("\(bytesString(d.available)) free").foregroundStyle(.secondary)
                        }
                        ProgressView(value: d.usedFraction).tint(fractionColor(d.usedFraction))
                        if d.purgeable > 0 {
                            Text("\(bytesString(d.purgeable)) purgeable (reclaimable on demand)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                SectionTitle("Largest folders in Home", icon: "folder")
                Spacer()
                Button { load() } label: { Label(tree == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.kestrel(tree == nil ? .prominent : .subtle, size: .small))
                    .disabled(loading)
            }

            if loading {
                HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) }
            } else if let tree {
                Card {
                    VStack(spacing: 10) {
                        ForEach(Array(tree.children.prefix(12)), id: \.url) { child in
                            LabeledBar(label: child.name, value: bytesString(child.size),
                                       fraction: tree.size > 0 ? Double(child.size) / Double(tree.size) : 0, tint: Palette.blue)
                        }
                    }
                }
            } else {
                Text("Scanning your Home folder reads Desktop, Documents, Downloads and Pictures, so macOS may ask for permission. Click Scan when you're ready.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() {
        loading = true
        let home = model.paths.home
        Task.detached {
            let measured = DiskMap().measure(home, maxDepth: 1)
            await MainActor.run { self.tree = measured; self.loading = false }
        }
    }
}

// MARK: - Activity

struct ActivitySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var summary: ActivitySummary?

    var body: some View {
        SectionScaffold(title: "Activity", subtitle: "What Kestrel has actually reclaimed") {
            let s = summary
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bytesString(s?.reclaimedBytes ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("reclaimed across \(s?.totalActions ?? 0) action(s), from the audit log")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let byCat = s?.bytesByCategory, !byCat.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        let total = max(1, byCat.values.reduce(0, +))
                        ForEach(byCat.sorted { $0.value > $1.value }, id: \.key) { key, bytes in
                            LabeledBar(label: key, value: bytesString(bytes), fraction: Double(bytes) / Double(total), tint: Palette.good)
                        }
                    }
                }
            } else {
                Text("Nothing reclaimed yet. Run a cleanup and it will show up here.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { summary = ActivityReporter(audit: AuditLog(url: model.paths.auditLog)).summary() }
    }
}

// MARK: - Settings

struct SettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionScaffold(title: "Settings", subtitle: "About Kestrel and where it stores things") {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    row("Version", Kestrel.version)
                    Divider()
                    row("Vault", model.paths.vault.path)
                    row("Audit log", model.paths.auditLog.path)
                    Divider()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) } label: {
                        Label("Reveal ~/.kestrel in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.kestrel(.secondary))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Safety", systemImage: "checkmark.shield").font(.headline)
                    Text("Cleanups are dry-run by default. Nothing is deleted outright — items move to the vault and can be undone. Zero telemetry: nothing leaves this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
    }
}
