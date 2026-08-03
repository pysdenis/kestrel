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

/// Kestrel's own sidebar (not a stock List) — a branded header, grouped navigation and
/// an accent bar + glow on the active item, matching the Precision design.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            brand
            group("Monitor", [.dashboard, .energy, .space])
            group("Maintain", [.cleanup, .security, .tools])
            group("Intelligence", [.assistant])
            Spacer(minLength: 8)
            group(nil, [.activity, .settings])
            paletteHint
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.6)
            LinearGradient(colors: [Palette.accent.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "bird.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Palette.kestrel, Palette.kestrel.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                           in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("Kestrel").font(.title3.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, 6).padding(.bottom, 10)
    }

    private func group(_ title: String?, _ items: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).kerning(0.8)
                    .foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
            }
            ForEach(items) { navRow($0) }
        }
    }

    private func navRow(_ item: AppSection) -> some View {
        let selected = model.section == item
        return Button { model.section = item } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon).font(.system(size: 14))
                    .foregroundStyle(selected ? Palette.accent : Color.secondary).frame(width: 18)
                Text(item.title).font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Palette.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Palette.accent).frame(width: 3, height: 16)
                        .shadow(color: Palette.accent.opacity(0.6), radius: 4).offset(x: -10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var paletteHint: some View {
        Button { model.showPalette = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Commands").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("⌘K").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The full window: a sidebar of sections, each backed by KestrelCore.
struct MainWindow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared(); model.mainWindowClosed() }
        .sheet(isPresented: $model.showPalette) { CommandPaletteView().environmentObject(model) }
    }

    @ViewBuilder private var detail: some View {
        switch model.section ?? .dashboard {
        case .dashboard: DashboardSection()
        case .cleanup: CleanupSection(controller: model.cleanup)
        case .space: SpaceSection(controller: model.space)
        case .energy: EnergySection()
        case .security: SecuritySection(controller: model.security)
        case .tools: ToolsSection(controller: model.tools)
        case .assistant: AssistantSection(controller: model.assistant)
        case .activity: ActivitySection()
        case .settings: SettingsSection(controller: model.settingsController)
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
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Mac Health").font(.title2.weight(.semibold))
                            Text(healthVerdict(model.health?.overall ?? 0))
                                .font(.subheadline).foregroundStyle(healthColor(model.health?.overall ?? 0))
                        }
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
    @ObservedObject var controller: SpaceController

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
                SectionTitle("Storage map", icon: "square.grid.3x3.fill")
                Spacer()
                Button { controller.load() } label: { Label(controller.tree == nil ? "Scan Home" : "Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.kestrel(controller.tree == nil ? .prominent : .subtle, size: .small))
                    .disabled(controller.loading)
            }

            if controller.loading {
                ScanningBanner(title: "Measuring your Home folder…",
                               detail: controller.scanStatus.isEmpty ? "Reading top-level folders…" : controller.scanStatus,
                               progress: controller.scanTotal > 0 ? Double(controller.scanDone) / Double(controller.scanTotal) : nil,
                               tint: Palette.blue)
            } else if let tree = controller.tree {
                let current = controller.path.last ?? tree
                HStack(spacing: 5) {
                    Button("Home") { controller.path = [] }.buttonStyle(.plain).foregroundStyle(controller.path.isEmpty ? Color.primary : Palette.accent)
                    ForEach(Array(controller.path.enumerated()), id: \.offset) { i, node in
                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Button(node.name) { controller.path = Array(controller.path.prefix(i + 1)) }
                            .buttonStyle(.plain).foregroundStyle(i == controller.path.count - 1 ? Color.primary : Palette.accent).lineLimit(1)
                    }
                    Spacer()
                    Text(bytesString(current.size)).foregroundStyle(.secondary)
                }
                .font(.caption)
                Card(padding: 6) {
                    TreemapView(node: current) { child in controller.path.append(child) }
                        .frame(height: 340)
                }
                Text("Sized by real on-disk usage (allocated bytes), so sparse files like Docker.raw show their true footprint. Click a block to drill in.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Scanning your Home folder reads Desktop, Documents, Downloads and Pictures, so macOS may ask for permission. Click Scan when you're ready.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Activity

struct ActivitySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var summary: ActivitySummary?
    @State private var digest: Digest?

    var body: some View {
        SectionScaffold(title: "Activity", subtitle: "What Kestrel has actually reclaimed — from the audit log") {
            let s = summary
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bytesString(s?.reclaimedBytes ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("reclaimed across \(s?.totalActions ?? 0) action(s)")
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
                Card {
                    EmptyState(icon: "tray", title: "Nothing reclaimed yet",
                               caption: "Run a cleanup and what you free up will show up here.", tint: Palette.accent)
                }
            }

            if let d = digest, (d.dailyGrowthBytes != nil || !d.recentChanges.isEmpty) {
                SectionTitle("Storage trend", icon: "chart.line.uptrend.xyaxis")
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        if let g = d.dailyGrowthBytes {
                            Text("\(g >= 0 ? "+" : "-")\(bytesString(abs(g)))/day" + (d.daysUntilFull.map { " · full in ~\(Int($0)) days" } ?? ""))
                                .font(.subheadline.weight(.medium))
                        }
                        ForEach(Array(d.recentChanges.enumerated()), id: \.offset) { _, c in
                            HStack {
                                Text(c.path).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(c.delta >= 0 ? "+" : "-")\(bytesString(abs(c.delta)))").font(.caption.monospacedDigit())
                                    .foregroundStyle(c.delta >= 0 ? Palette.warn : Palette.good)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            summary = ActivityReporter(audit: AuditLog(url: model.paths.auditLog)).summary()
            digest = DigestReporter(audit: AuditLog(url: model.paths.auditLog), snapshots: SnapshotStore(directory: model.paths.snapshots)).generate()
        }
    }
}

// MARK: - Settings

struct SettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: SettingsController

    private var totalVaultBytes: Int64 { controller.sessions.reduce(0) { $0 + $1.totalBytes } }

    var body: some View {
        SectionScaffold(title: "Settings", subtitle: "The vault, and where Kestrel stores things") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            vaultCard

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
        .onAppear { controller.load() }
    }

    private var vaultCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Vault", icon: "tray.full")
                    Spacer()
                    if !controller.sessions.isEmpty {
                        Text("\(controller.sessions.count) session(s) · \(bytesString(totalVaultBytes))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text("Everything a cleanup removes is moved here first, so it can be restored. Purging is the only place data is really deleted.")
                    .font(.caption).foregroundStyle(.secondary)

                if let message = controller.message {
                    Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }

                if controller.sessions.isEmpty {
                    EmptyState(icon: "tray", title: "Vault is empty",
                               caption: "Cleaned items will appear here, restorable until you purge.", tint: Palette.accent)
                } else {
                    ForEach(controller.sessions, id: \.id) { session in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.callout.weight(.medium))
                                Text("\(session.count) item(s) · \(bytesString(session.totalBytes))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            Button { controller.undo(session.id) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                .buttonStyle(.kestrel(.secondary, size: .small))
                                .disabled(controller.busy)
                        }
                        .padding(.vertical, 2)
                        Divider()
                    }
                    HStack {
                        Spacer()
                        Button { controller.purge(days: 14) } label: { Label("Purge older than 14 days", systemImage: "trash") }
                            .buttonStyle(.kestrel(.subtle, tint: Palette.crit, size: .small))
                            .disabled(controller.busy)
                    }
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
