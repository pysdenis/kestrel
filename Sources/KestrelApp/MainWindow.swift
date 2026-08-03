import SwiftUI
import KestrelCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, cleanup, space, security, tools, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .cleanup: return "Cleanup"
        case .space: return "Space"
        case .security: return "Security"
        case .tools: return "Tools"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleanup: return "sparkles"
        case .space: return "chart.pie"
        case .security: return "shield.lefthalf.filled"
        case .tools: return "wrench.and.screwdriver"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// The full window: a sidebar of sections, each backed by KestrelCore.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 520)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { model.start() }
        .onDisappear { model.mainWindowClosed() }
    }

    @ViewBuilder private var detail: some View {
        switch section ?? .dashboard {
        case .dashboard: DashboardSection()
        case .cleanup: CleanupSection()
        case .space: SpaceSection()
        case .security: SecuritySection()
        case .tools: ToolsSection()
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

            LazyVGrid(columns: columns, spacing: 12) {
                if let d = model.disk {
                    MetricTile(icon: "internaldrive", title: "Disk", value: "\(Int(d.usedFraction * 100))%",
                               detail: "\(bytesString(d.available)) free" + (d.purgeable > 0 ? " · \(bytesString(d.purgeable)) purgeable" : ""),
                               fraction: d.usedFraction, tint: .blue)
                }
                if let m = model.memory {
                    MetricTile(icon: "memorychip", title: "Memory", value: "\(Int(m.usedFraction * 100))%",
                               detail: "\(bytesString(m.used)) of \(bytesString(m.total))", fraction: m.usedFraction, tint: .purple)
                }
                if let c = model.cpu {
                    MetricTile(icon: "cpu", title: "CPU load", value: String(format: "%.2f", c.loadAverages.first ?? 0),
                               detail: "\(c.coreCount) cores", fraction: min(1, c.pressure), tint: .orange)
                }
                if let b = model.battery {
                    MetricTile(icon: "battery.100", title: "Battery", value: "\(b.percent)%",
                               detail: b.healthPercent.map { "health \($0)%" } ?? (b.isCharging ? "charging" : ""),
                               fraction: Double(b.percent) / 100, tint: .green)
                }
                if let n = model.network {
                    MetricTile(icon: "wifi", title: "Network", value: n.ssid ?? "Wired/—",
                               detail: "↓\(bytesString(n.bytesIn)) ↑\(bytesString(n.bytesOut))", tint: .teal)
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
            HStack(spacing: 14) {
                Image(systemName: "speedometer").font(.title).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Internet speed").font(.headline)
                    if let s = model.speed {
                        Text(String(format: "%.0f Mbps download · %.0f ms latency", s.downloadMbps, s.latencyMs))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Measure your download speed and latency").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: model.runSpeedTest) {
                    if model.speedTesting { ProgressView().controlSize(.small) }
                    else { Label("Run test", systemImage: "play.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.speedTesting)
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
                Button { load() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .disabled(loading)
            }

            if loading {
                HStack { ProgressView().controlSize(.small); Text("Measuring…").foregroundStyle(.secondary) }
            } else if let tree {
                Card {
                    VStack(spacing: 10) {
                        ForEach(Array(tree.children.prefix(12)), id: \.url) { child in
                            LabeledBar(label: child.name, value: bytesString(child.size),
                                       fraction: tree.size > 0 ? Double(child.size) / Double(tree.size) : 0, tint: .blue)
                        }
                    }
                }
            }
        }
        .task { if tree == nil { load() } }
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
                            LabeledBar(label: key, value: bytesString(bytes), fraction: Double(bytes) / Double(total), tint: .green)
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
