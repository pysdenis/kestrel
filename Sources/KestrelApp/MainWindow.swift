import SwiftUI
import KestrelCore

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case smartcare, dashboard, cleanup, space, energy, security, applications, permissions, tools, assistant, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartcare: return "Smart Care"
        case .dashboard: return "Dashboard"
        case .cleanup: return "Cleanup"
        case .space: return "Space"
        case .energy: return "Energy"
        case .security: return "Security"
        case .applications: return "Applications"
        case .permissions: return "Permissions"
        case .tools: return "Tools"
        case .assistant: return "Assistant"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .smartcare: return "wand.and.stars"
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleanup: return "sparkles"
        case .space: return "chart.pie"
        case .energy: return "bolt.fill"
        case .security: return "shield.lefthalf.filled"
        case .applications: return "square.grid.2x2"
        case .permissions: return "hand.raised"
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
            group(nil, [.smartcare])
            group("Monitor", [.dashboard, .energy, .space])
            group("Maintain", [.cleanup, .security, .applications, .permissions, .tools])
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
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1).ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 640)
        .confirmHost()
        .onAppear { model.surfaceAppeared() }
        .onDisappear { model.surfaceDisappeared(); model.mainWindowClosed() }
        .sheet(isPresented: $model.showPalette) { CommandPaletteView().environmentObject(model) }
    }

    @ViewBuilder private var detail: some View {
        switch model.section ?? .dashboard {
        case .smartcare: SmartCareSection(controller: model.smartcare)
        case .dashboard: DashboardSection(controller: model.dashboard)
        case .cleanup: CleanupSection(controller: model.cleanup)
        case .space: SpaceSection(controller: model.space)
        case .energy: EnergySection()
        case .security: SecuritySection(controller: model.security)
        case .applications: ApplicationsSection(controller: model.apps)
        case .permissions: PermissionsSection(controller: model.permissions)
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
    @ObservedObject var controller: DashboardController
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var score: Int { model.health?.overall ?? 0 }

    var body: some View {
        SectionScaffold(title: "Dashboard", subtitle: "Live health, storage forecast and protection at a glance") {
            heroCard
            if model.aiConfigured { aiInsightCard }
            metricGrid
            HStack(alignment: .top, spacing: 12) {
                ForecastCard(trend: controller.trend, series: controller.usedSeries)
                ProtectionCard(status: controller.protection) { model.section = .security }
            }
            SpeedTestCard()
        }
        .onAppear { controller.load(disk: model.disk) }
        .onChange(of: model.disk?.total) { _ in
            if controller.usedSeries.isEmpty { controller.load(disk: model.disk) }
        }
    }

    // MARK: hero

    private var heroCard: some View {
        Card(elevated: true, tint: healthColor(score)) {
            HStack(spacing: 24) {
                HeroGauge(score: score, size: 168)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac Health").font(.title2.weight(.bold))
                        Text(healthVerdict(score)).font(.subheadline.weight(.medium)).foregroundStyle(healthColor(score))
                    }
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(model.health?.components ?? [], id: \.name) { c in
                            HealthChip(name: c.name, score: c.score)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        Button { model.section = .cleanup } label: { Label("Free up space", systemImage: "sparkles") }
                            .buttonStyle(.kestrel(.prominent))
                        Button(action: runSmartCare) { Label("Run Smart Care", systemImage: "wand.and.stars") }
                            .buttonStyle(.kestrel(.secondary))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: AI insight (on-demand, metadata-only — invariant #7)

    private var aiInsightCard: some View {
        Card(tint: Palette.violet) {
            HStack(alignment: .top, spacing: 12) {
                AssistantAvatar()
                VStack(alignment: .leading, spacing: 8) {
                    if let insight = controller.insight {
                        Text(insight).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else {
                        Text("Get one quick, honest AI insight about your storage and health.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        Button { controller.getInsight(assistant: model.aiAssistant, context: model.aiContext()) } label: {
                            if controller.insightLoading {
                                HStack(spacing: 6) { KestrelSpinner(tint: Palette.violet, size: 13); Text("Thinking…") }
                            } else {
                                Label(controller.insight == nil ? "Get insight" : "Refresh", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.kestrel(.secondary, tint: Palette.violet, size: .small))
                        .disabled(controller.insightLoading)
                        Spacer()
                        Text("metadata only · never file contents").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Jump to the Smart Care module and start its honest orchestrated pass.
    private func runSmartCare() {
        model.section = .smartcare
        let home = model.paths.home
        model.smartcare.run(home: home, downloads: home.appendingPathComponent("Downloads"))
    }

    // MARK: metrics

    private var metricGrid: some View {
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
    }
}

/// A compact health-component pill (colored dot + name + score) for the hero card.
struct HealthChip: View {
    let name: String
    let score: Int
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(healthColor(score)).frame(width: 7, height: 7)
            Text(name).font(.caption.weight(.medium))
            Text("\(score)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
    }
}

/// Storage forecast: growth per day, a naive fill date and a sparkline of recent
/// used-bytes. Honest about needing a couple of days of history.
struct ForecastCard: View {
    let trend: SpaceTrend?
    let series: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Storage forecast", icon: "chart.line.uptrend.xyaxis")
                if let t = trend, t.dailyGrowthBytes != 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(t.dailyGrowthBytes > 0 ? "+" : "−")\(bytesString(abs(t.dailyGrowthBytes)))")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(t.dailyGrowthBytes > 0 ? Palette.warn : Palette.good)
                        Text("/ day").font(.caption).foregroundStyle(.secondary)
                    }
                    if let days = t.daysUntilFull {
                        Text("Full in about \(Int(days)) days at this rate").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Freeing space overall — no fill date").font(.caption).foregroundStyle(Palette.good)
                    }
                    if series.count > 1 {
                        Sparkline(values: series, tint: Palette.accent2).frame(height: 38).padding(.top, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Building history").font(.subheadline.weight(.medium))
                        Text("Kestrel records a daily snapshot. The forecast fills in after a couple of days.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// macOS protection status (Gatekeeper + XProtect) with an honest verdict and a jump to
/// the Security section.
struct ProtectionCard: View {
    let status: GatekeeperStatus?
    let openSecurity: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Protection", icon: "shield.lefthalf.filled")
                if let p = status {
                    let ok = p.assessmentsEnabled == true
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill((ok ? Palette.good : Palette.warn).opacity(0.14)).frame(width: 44, height: 44)
                            Image(systemName: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.title3).foregroundStyle(ok ? Palette.good : Palette.warn)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ok ? "Protected" : "Check protection").font(.subheadline.weight(.semibold))
                            Text(ok ? "Gatekeeper on · XProtect \(p.xprotectVersion ?? "—")" : "Gatekeeper assessments are off")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                    }
                    Button(action: openSecurity) { Label("Open Security", systemImage: "arrow.right") }
                        .buttonStyle(.kestrel(.subtle, size: .small))
                } else {
                    HStack(spacing: 8) {
                        KestrelSpinner(size: 14)
                        Text("Reading protection status…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }
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
            if let d = model.disk { capacityCard(d) }

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
                breadcrumb(current)
                Card(padding: 6) {
                    TreemapView(node: current) { child in controller.path.append(child) }
                        .frame(height: 340)
                }
                Text("Sized by real on-disk usage (allocated bytes), so sparse files like Docker.raw show their true footprint. Click a block to drill in.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                largestCard(current)
            } else {
                Card {
                    EmptyState(icon: "square.grid.3x3", title: "Scan your Home folder",
                               caption: "This reads Desktop, Documents, Downloads and Pictures, so macOS may ask for permission. Click Scan Home when you're ready.",
                               tint: Palette.accent)
                }
            }
        }
    }

    private func capacityCard(_ d: DiskSpace) -> some View {
        Card(elevated: true, tint: fractionColor(d.usedFraction)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(bytesString(d.used)) used").font(.title3.weight(.bold))
                    Spacer()
                    Text("of \(bytesString(d.total))").font(.subheadline).foregroundStyle(.secondary)
                }
                KestrelProgress(value: d.usedFraction, tint: fractionColor(d.usedFraction), height: 10)
                HStack(spacing: 16) {
                    legendDot(fractionColor(d.usedFraction), "Used", bytesString(d.used))
                    legendDot(.primary.opacity(0.2), "Free", bytesString(d.available))
                    if d.purgeable > 0 { legendDot(Palette.warn, "Purgeable", bytesString(d.purgeable)) }
                    Spacer()
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private func breadcrumb(_ current: DirNode) -> some View {
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
    }

    @ViewBuilder private func largestCard(_ current: DirNode) -> some View {
        let top = current.children.sorted { $0.size > $1.size }.prefix(8)
        if !top.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Largest in \(current.name)", icon: "list.number")
                    ForEach(Array(top.enumerated()), id: \.offset) { _, child in
                        Button { if !child.children.isEmpty { controller.path.append(child) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: child.children.isEmpty ? "doc" : "folder.fill")
                                    .foregroundStyle(child.children.isEmpty ? Color.secondary : Palette.accent2).imageScale(.small).frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(child.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(bytesString(child.size)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                                    }
                                    MiniBar(fraction: current.size > 0 ? Double(child.size) / Double(current.size) : 0, tint: Palette.accent2)
                                }
                                if !child.children.isEmpty {
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
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
            Card(elevated: true, tint: Palette.good) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Palette.good.opacity(0.14)).frame(width: 56, height: 56)
                        Image(systemName: "arrow.up.bin.fill").font(.system(size: 24)).foregroundStyle(Palette.good)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bytesString(s?.reclaimedBytes ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("reclaimed across \(s?.totalActions ?? 0) action(s)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if let byCat = s?.bytesByCategory, !byCat.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("By category", icon: "chart.bar")
                        let total = max(1, byCat.values.reduce(0, +))
                        ForEach(byCat.sorted { $0.value > $1.value }, id: \.key) { key, bytes in
                            LabeledBar(label: categoryLabel(key), value: bytesString(bytes),
                                       fraction: Double(bytes) / Double(total), tint: categoryColor(key))
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
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Storage trend", icon: "chart.line.uptrend.xyaxis")
                        if let g = d.dailyGrowthBytes {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(g >= 0 ? "+" : "−")\(bytesString(abs(g)))")
                                    .font(.title3.weight(.bold)).foregroundStyle(g >= 0 ? Palette.warn : Palette.good)
                                Text("/ day" + (d.daysUntilFull.map { " · full in ~\(Int($0)) days" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Array(d.recentChanges.enumerated()), id: \.offset) { i, c in
                            if i > 0 { Hairline() }
                            HStack {
                                Text(c.path).font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(c.delta >= 0 ? "+" : "−")\(bytesString(abs(c.delta)))").font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(c.delta >= 0 ? Palette.warn : Palette.good)
                            }
                            .padding(.vertical, 2)
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

    private func categoryColor(_ key: String) -> Color {
        KestrelCore.Category(rawValue: key)?.display.color ?? Palette.good
    }
    private func categoryLabel(_ key: String) -> String {
        KestrelCore.Category(rawValue: key)?.display.title ?? key.capitalized
    }
}

// MARK: - Settings

struct SettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: SettingsController

    private var totalVaultBytes: Int64 { controller.sessions.reduce(0) { $0 + $1.totalBytes } }

    var body: some View {
        SectionScaffold(title: "Settings", subtitle: "Preferences, the vault, and where Kestrel stores things") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            preferencesCard
            vaultCard

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    row("Version", Kestrel.version)
                    Hairline()
                    row("Vault", model.paths.vault.path)
                    row("Audit log", model.paths.auditLog.path)
                    Hairline()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) } label: {
                        Label("Reveal ~/.kestrel in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.kestrel(.secondary))
                }
            }
            Card(tint: Palette.good) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Safety", systemImage: "checkmark.shield").font(.headline)
                    Text("Cleanups are dry-run by default. Nothing is deleted outright — items move to the vault and can be undone. Zero telemetry: nothing leaves this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { controller.load() }
    }

    private var preferencesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Preferences", icon: "slider.horizontal.3")
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Launch at login").font(.callout.weight(.medium))
                        Text("Start Kestrel automatically when you log in.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    KestrelToggle(isOn: Binding(get: { controller.launchAtLogin },
                                                set: { controller.setLaunchAtLogin($0) }))
                }
                Hairline()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Low-space notifications").font(.callout.weight(.medium))
                        Text("A local alert when the disk is nearly full. Nothing leaves this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    KestrelToggle(isOn: Binding(get: { model.notificationsEnabled },
                                                set: { model.setNotifications($0) }))
                }
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Vault retention").font(.callout.weight(.medium))
                        Text("How long cleaned items stay restorable before they can be purged.").font(.caption).foregroundStyle(.secondary)
                    }
                    KestrelSelect(items: controller.retentionOptions, selection: $controller.retentionDays,
                                  label: { "\($0) days" })
                }
            }
        }
    }

    private func confirmPurge() {
        model.requestConfirm(ConfirmRequest(
            icon: "trash", tint: Palette.crit,
            title: "Purge old vault sessions?",
            message: "Permanently deletes everything in the vault older than \(controller.retentionDays) days. This can't be undone — restored items are unaffected.",
            confirmLabel: "Purge", destructive: true,
            onConfirm: { controller.purge(days: controller.retentionDays) }
        ))
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
                    Label(message, systemImage: controller.lastRestoreOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(controller.lastRestoreOK ? Palette.good : Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
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
                        Hairline()
                    }
                    HStack {
                        Spacer()
                        Button { confirmPurge() } label: { Label("Purge older than 14 days", systemImage: "trash") }
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
