import SwiftUI
import AppKit
import KestrelCore

/// Display metadata for a cleanup category — a friendly name, an icon and a tint — so the
/// Cleanup module can render a per-category breakdown in the Precision language.
extension KestrelCore.Category {
    var display: (title: String, icon: String, color: Color) {
        switch self {
        case .safeCache:   return ("Caches", "shippingbox", Palette.accent)
        case .logs:        return ("Logs", "doc.text", Palette.accent2)
        case .devArtifact: return ("Dev artifacts", "hammer", Palette.kestrel)
        case .duplicate:   return ("Duplicates", "doc.on.doc", Palette.violet)
        case .largeOld:    return ("Large & old", "arrow.up.left.and.arrow.down.right", Palette.warn)
        case .appLeftover: return ("App leftovers", "app.badge.checkmark", Palette.accent)
        case .privacy:     return ("Privacy", "eye.slash", Palette.pink)
        case .trash:       return ("Trash", "trash", Palette.good)
        case .unknown:     return ("Unknown", "questionmark.circle", Palette.orange)
        }
    }
}

// MARK: - Cleanup

enum CleanupChoice: String, CaseIterable, Identifiable {
    case all, dev, cache, logs, dupes, large, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Everything safe"
        case .dev: return "Dev artifacts"
        case .cache: return "Caches"
        case .logs: return "Logs"
        case .dupes: return "Duplicates"
        case .large: return "Large & old"
        case .privacy: return "Privacy"
        }
    }

    var categories: Set<KestrelCore.Category>? {
        switch self {
        case .all: return nil
        case .dev: return [.devArtifact]
        case .cache: return [.safeCache]
        case .logs: return [.logs]
        case .dupes: return [.duplicate]
        case .large: return [.largeOld]
        case .privacy: return [.privacy]
        }
    }

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .dev: return "hammer"
        case .cache: return "shippingbox"
        case .logs: return "doc.text"
        case .dupes: return "doc.on.doc"
        case .large: return "arrow.up.left.and.arrow.down.right"
        case .privacy: return "eye.slash"
        }
    }
}

struct CleanupSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: CleanupController

    var body: some View {
        SectionScaffold(title: "Cleanup", subtitle: "Preview first — nothing is deleted, items move to the vault") {
            configCard

            if controller.scanning {
                ScanningBanner(title: "Scanning \(controller.choice.title.lowercased())…",
                               detail: controller.scanStatus.isEmpty ? "Walking \(controller.root.lastPathComponent)…" : controller.scanStatus)
            }

            if let message = controller.message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good).font(.callout)
            }

            if let aiReview = controller.aiReview {
                Card(tint: Palette.violet) {
                    HStack(alignment: .top, spacing: 10) {
                        AssistantAvatar()
                        Text(aiReview).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let plan = controller.plan, !controller.scanning {
                if plan.items.isEmpty {
                    EmptyState(icon: "checkmark.seal.fill", title: "Nothing to clean here",
                               caption: "This category is already tidy in \(controller.root.lastPathComponent).")
                } else {
                    summaryHero(plan)
                    ForEach(groups(plan), id: \.category) { group in
                        CleanupGroup(category: group.category, items: group.items)
                    }
                }
            }
        }
        .dropFolder { url in
            controller.root = url; controller.plan = nil; controller.message = nil; controller.scan()
        }
    }

    // MARK: config

    private var configCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Text("CATEGORY").font(.system(size: 10.5, weight: .bold)).kerning(0.8).foregroundStyle(.tertiary)
                KestrelSelect(items: CleanupChoice.allCases, selection: $controller.choice,
                              label: { $0.title }, icon: { $0.icon })

                FolderChip(url: controller.root) { controller.pickFolder() }

                HStack(spacing: 10) {
                    Button { controller.scan() } label: {
                        Label(controller.scanning ? "Scanning…" : "Scan for reclaimable space", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel)
                    .disabled(controller.scanning || controller.applying)
                    Label("or drop a folder anywhere here", systemImage: "arrow.down.doc")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: summary

    private func summaryHero(_ plan: CleanupPlan) -> some View {
        Card(elevated: true, tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bytesString(plan.totalBytes)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("reclaimable · \(plan.count) item(s)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button { controller.apply() } label: {
                            if controller.applying { KestrelSpinner(tint: .white, size: 15) }
                            else { Label("Move \(plan.count) to Vault", systemImage: "tray.and.arrow.down") }
                        }
                        .buttonStyle(.kestrel(.prominent))
                        .disabled(controller.applying)

                        if model.aiConfigured {
                            Button { controller.review(assistant: model.aiAssistant) } label: {
                                if controller.reviewing { KestrelSpinner(tint: Palette.violet, size: 14) }
                                else { Label("AI second opinion", systemImage: "sparkles") }
                            }
                            .buttonStyle(.kestrel(.subtle, tint: Palette.violet, size: .small))
                            .disabled(controller.reviewing)
                        }
                    }
                }
                let byCat = plan.bytesByCategory
                if byCat.count > 1 {
                    SegmentBar(segments: byCat.sorted { $0.value > $1.value }.map {
                        SegmentBar.Segment(color: $0.key.display.color, value: Double($0.value), label: $0.key.display.title)
                    })
                }
            }
        }
    }

    private struct Group { let category: KestrelCore.Category; let items: [CleanupItem] }

    private func groups(_ plan: CleanupPlan) -> [Group] {
        let byCat = Dictionary(grouping: plan.items, by: { $0.category })
        return byCat
            .map { Group(category: $0.key, items: $0.value.sorted { $0.entry.size > $1.entry.size }) }
            .sorted { $0.items.reduce(0) { $0 + $1.entry.size } > $1.items.reduce(0) { $0 + $1.entry.size } }
    }
}

/// A folder-picker row rendered as a chip (no stock control): a folder glyph, the path,
/// and a "Choose…" affordance.
struct FolderChip: View {
    let url: URL
    let onChoose: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill").foregroundStyle(Palette.accent2).imageScale(.small)
            Text(url.path).lineLimit(1).truncationMode(.middle).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Choose…", action: onChoose).buttonStyle(.kestrel(.subtle, size: .small))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// A single stacked proportion bar — one colored segment per category — for the reclaim
/// breakdown. Segments narrower than a hair are dropped so the bar reads cleanly.
struct SegmentBar: View {
    struct Segment: Identifiable { let id = UUID(); let color: Color; let value: Double; let label: String }
    let segments: [Segment]
    private var total: Double { max(1, segments.reduce(0) { $0 + $1.value }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments) { s in
                        Capsule().fill(s.color.gradient)
                            .frame(width: max(0, geo.size.width * s.value / total - 2))
                    }
                }
            }
            .frame(height: 9)
            FlowLayout(spacing: 12, lineSpacing: 6) {
                ForEach(segments) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.label).font(.caption).foregroundStyle(.secondary)
                        Text(bytesString(Int64(s.value))).font(.caption.monospacedDigit().weight(.medium))
                    }
                }
            }
        }
    }
}

/// A collapsible per-category group of cleanup items — a custom disclosure (no stock
/// `DisclosureGroup`): tap the header to reveal the largest items with their reasons.
struct CleanupGroup: View {
    let category: KestrelCore.Category
    let items: [CleanupItem]
    @State private var expanded = false

    private var subtotal: Int64 { items.reduce(0) { $0 + $1.entry.size } }

    var body: some View {
        let d = category.display
        Card(padding: 0) {
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.icon).foregroundStyle(d.color).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.title).font(.subheadline.weight(.semibold))
                            Text("\(items.count) item(s)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(bytesString(subtotal)).font(.callout.weight(.semibold).monospacedDigit())
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .padding(14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    Hairline().padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(50).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 12) {
                                Text(bytesString(item.entry.size)).font(.caption.monospacedDigit().weight(.medium))
                                    .frame(width: 72, alignment: .leading).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.entry.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                    Text(item.reason).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        if items.count > 50 {
                            Text("+ \(items.count - 50) more").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Assistant (AI, opt-in)

struct AssistantSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: AssistantController

    private let suggestions = [
        "What's using most of my disk?",
        "Is it safe to clear developer caches?",
        "How can I free space as a developer?",
        "What are the biggest wins to reclaim space?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if !model.aiConfigured {
                ScrollView { setupCard.padding(22).frame(maxWidth: 560) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                conversation
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LinearGradient(colors: [Palette.violet, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                           in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Assistant").font(.title3.weight(.bold))
                Text("Honest AI help · sends metadata only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.aiConfigured, !controller.messages.isEmpty {
                Button { controller.clear() } label: { Label("New chat", systemImage: "square.and.pencil") }
                    .buttonStyle(.kestrel(.subtle, size: .small))
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    // MARK: conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if controller.messages.isEmpty { welcome }
                    ForEach(controller.messages) { ChatBubble(message: $0).id($0.id) }
                    if controller.thinking {
                        HStack(alignment: .top, spacing: 10) {
                            AssistantAvatar()
                            TypingIndicator()
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Spacer(minLength: 32)
                        }
                        .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.messages.count) { _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: controller.thinking) { _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask me about your Mac's storage, or analyze a folder.")
                .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { controller.send(s, assistant: model.aiAssistant, context: model.aiContext()) } label: {
                        Text(s).font(.callout)
                    }
                    .buttonStyle(.kestrel(.secondary, tint: Palette.violet, size: .small))
                    .disabled(controller.thinking)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: composer

    private var composer: some View {
        VStack(spacing: 8) {
            Hairline()
            HStack(spacing: 8) {
                Button { controller.pickFolder() } label: { Image(systemName: "folder") }
                    .buttonStyle(.kestrel(.subtle, size: .small))
                    .help("Choose a folder to analyze: \(controller.analyzeRoot.path)")
                Button { controller.analyze(assistant: model.aiAssistant, disk: model.disk) } label: {
                    Label("Analyze \(controller.analyzeRoot.lastPathComponent)", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.kestrel(.subtle, size: .small))
                .disabled(controller.thinking)
                Spacer()
                Text("metadata only · never file contents").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                TextField("Ask anything…", text: $controller.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule(style: .continuous))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(sendEnabled ? AnyShapeStyle(Palette.violet.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3)), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!sendEnabled)
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 16).padding(.top, 4)
    }

    private var sendEnabled: Bool {
        !controller.thinking && !controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        controller.send(controller.draft, assistant: model.aiAssistant, context: model.aiContext())
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Turn on the assistant", systemImage: "key").font(.headline)
                Text("The assistant is opt-in and off by default. To enable it, put your Google Gemini API key in a file:")
                    .font(.callout).foregroundStyle(.secondary)
                Text(model.paths.geminiKey.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("It then sends only metadata (names, sizes, categories) — never file contents.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.paths.root]) } label: {
                    Label("Reveal ~/.kestrel in Finder", systemImage: "folder")
                }
                .buttonStyle(.kestrel(.secondary))
            }
        }
    }
}

/// The assistant's little gradient avatar, shown beside its messages.
struct AssistantAvatar: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(LinearGradient(colors: [Palette.violet, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing),
                       in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A single chat message: user bubbles are accent-filled and right-aligned; the
/// assistant's are a material card with an avatar, left-aligned.
struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                AssistantAvatar()
                Text(message.text)
                    .font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06)))
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.callout).foregroundStyle(.white).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Palette.violet.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

/// Three bouncing dots while the assistant is composing a reply. Honours Reduce Motion.
struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Palette.violet.opacity(0.75)).frame(width: 6, height: 6)
                        .offset(y: reduceMotion ? 0 : -3 * abs(sin(t * 3 + Double(i) * 0.5)))
                }
            }
        }
    }
}

// MARK: - Energy

struct EnergySection: View {
    @EnvironmentObject private var model: AppModel

    private var maxNow: Double { max(1, model.energyNow.map(\.energyImpact).max() ?? 1) }
    private var max24h: Double { max(1, model.energy24h.first?.total ?? 1) }

    var body: some View {
        SectionScaffold(title: "Energy", subtitle: "What's using power — right now and over the last 24 hours") {
            if let b = model.battery { batteryCard(b) }
            if let m = model.memory { memoryCard(m) }
            drainingCard
            historyCard
        }
        .onAppear { model.energyAppeared() }
        .onDisappear { model.energyDisappeared() }
    }

    // MARK: battery

    private func batteryCard(_ b: BatteryStats) -> some View {
        let full = b.percent > 20
        return Card(elevated: true, tint: full ? Palette.good : Palette.crit) {
            HStack(spacing: 20) {
                ZStack {
                    SegmentedRing(fraction: Double(b.percent) / 100, tint: full ? Palette.good : Palette.crit, size: 104)
                    VStack(spacing: 0) {
                        Text("\(b.percent)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("%").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.isCharging ? "Charging" : "On battery").font(.title3.weight(.bold))
                    if let m = model.batteryTimeMinutes {
                        Text(b.isCharging ? "About \(minutesString(m)) until full" : "About \(minutesString(m)) remaining")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    if let h = b.healthPercent { EnergyStat(icon: "heart.fill", label: "Health", value: "\(h)%", tint: Palette.pink) }
                    if let cy = b.cycleCount { EnergyStat(icon: "arrow.triangle.2.circlepath", label: "Cycles", value: "\(cy)", tint: Palette.blue) }
                    if let t = b.temperatureC { EnergyStat(icon: "thermometer.medium", label: "Temp", value: "\(Int(t.rounded()))°", tint: Palette.orange) }
                }
            }
        }
    }

    // MARK: memory / performance

    private func memoryCard(_ m: MemoryStats) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Memory", icon: "memorychip")
                    Spacer()
                    Button { model.freeMemory() } label: {
                        if model.freeingMemory { HStack(spacing: 6) { KestrelSpinner(size: 13); Text("Freeing…") } }
                        else { Label("Free up memory", systemImage: "arrow.down.circle") }
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small))
                    .disabled(model.freeingMemory)
                    .help("Runs macOS purge to free inactive memory — non-destructive")
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(m.usedFraction * 100))%").font(.title3.weight(.bold)).monospacedDigit()
                    Text("\(bytesString(m.used)) of \(bytesString(m.total)) used").font(.caption).foregroundStyle(.secondary)
                }
                KestrelProgress(value: m.usedFraction, tint: fractionColor(m.usedFraction), height: 9)
                HStack(spacing: 16) {
                    memLegend(Palette.violet, "App", m.active)
                    memLegend(Palette.accent, "Wired", m.wired)
                    memLegend(Palette.warn, "Compressed", m.compressed)
                    memLegend(.primary.opacity(0.2), "Free", m.free)
                    Spacer()
                }
            }
        }
    }

    private func memLegend(_ color: Color, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(bytesString(bytes)).font(.caption2.monospacedDigit())
        }
    }

    // MARK: right now

    private var drainingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Draining right now", icon: "bolt.fill")
                if model.energyNow.isEmpty {
                    HStack(spacing: 10) {
                        ScanRadar(tint: Palette.orange, size: 24)
                        Text("Reading energy usage…").foregroundStyle(.secondary).font(.callout)
                    }
                } else {
                    ForEach(Array(model.energyNow.enumerated()), id: \.element.id) { i, proc in
                        if i > 0 { Hairline() }
                        EnergyRow(rank: i + 1, proc: proc, fraction: proc.energyImpact / maxNow) { confirmQuit(proc) }
                    }
                }
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Most draining — last 24 hours", icon: "clock.arrow.circlepath")
                if model.energy24h.count < 2 {
                    Text("Building history… this fills in while Kestrel is running.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(Array(model.energy24h.prefix(10))) { usage in
                        LabeledBar(label: usage.name, value: String(format: "%.0f", usage.total),
                                   fraction: usage.total / max24h, tint: Palette.orange)
                    }
                    if let start = model.energyStart {
                        Text("Recorded since \(start.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func confirmQuit(_ proc: ProcessEnergy) {
        model.requestConfirm(ConfirmRequest(
            icon: "xmark.octagon", tint: Palette.crit,
            title: "Quit \(proc.name)?",
            message: "This asks the app to quit (SIGTERM). Unsaved work in that app may be lost.",
            confirmLabel: "Quit \(proc.name)", destructive: true,
            onConfirm: { model.quitProcess(pid: proc.pid) }
        ))
    }
}

/// A boxed battery stat (health/cycles/temperature) for the Energy header.
struct EnergyStat: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.callout).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// A "draining right now" row: rank, name, live CPU%, an impact bar, and a quit button.
struct EnergyRow: View {
    let rank: Int
    let proc: ProcessEnergy
    let fraction: Double
    let onQuit: () -> Void

    private var tint: Color { fraction > 0.66 ? Palette.crit : (fraction > 0.33 ? Palette.orange : Palette.accent) }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.tertiary).frame(width: 16)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(proc.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.0f%% CPU", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                MiniBar(fraction: fraction, tint: tint)
            }
            Button(action: onQuit) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.crit)
            }
            .buttonStyle(.plain).help("Quit \(proc.name)")
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Security

struct SecuritySection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: SecurityController

    var body: some View {
        SectionScaffold(title: "Security", subtitle: "Honest, evidence-based checks — no scare tactics") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            if let status = controller.status { protectionHero(status) }

            scanCard

            if !controller.extensions.isEmpty { extensionsCard }
            if !controller.orphans.isEmpty { orphansCard }
        }
        .dropFolder { url in controller.root = url; controller.report = nil; controller.scan() }
        .onAppear { controller.loadMeta() }
    }

    // MARK: protection status

    private func protectionHero(_ status: GatekeeperStatus) -> some View {
        let ok = status.assessmentsEnabled == true && status.xprotectVersion != nil
        return Card(elevated: true, tint: ok ? Palette.good : Palette.warn) {
            VStack(spacing: 14) {
                HStack(spacing: 15) {
                    ZStack {
                        Circle().fill((ok ? Palette.good : Palette.warn).opacity(0.14)).frame(width: 56, height: 56)
                        Image(systemName: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 25, weight: .semibold)).foregroundStyle(ok ? Palette.good : Palette.warn)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ok ? "macOS protection is on" : "Protection needs a look").font(.title3.weight(.bold))
                        Text(ok ? "Gatekeeper and XProtect are active." : "One of macOS's built-in defenses is off.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatusTile(icon: "lock.shield", label: "Gatekeeper",
                               value: status.assessmentsEnabled == true ? "On" : (status.assessmentsEnabled == false ? "Off" : "Unknown"),
                               ok: status.assessmentsEnabled == true)
                    StatusTile(icon: "checkmark.seal", label: "XProtect",
                               value: status.xprotectVersion ?? "—", ok: status.xprotectVersion != nil)
                }
            }
        }
    }

    // MARK: threat scan

    private var scanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Scan for threats", icon: "magnifyingglass")
                FolderChip(url: controller.root) { controller.pickFolder() }
                Button { controller.scan() } label: {
                    Label(controller.scanning ? "Scanning…" : "Scan for malware", systemImage: "shield.checkerboard")
                }
                .buttonStyle(.kestrel).disabled(controller.scanning)

                if controller.scanning {
                    ScanningBanner(title: "Scanning for threats…",
                                   detail: controller.scanStatus.isEmpty ? "Reading files in \(controller.root.lastPathComponent)…" : controller.scanStatus,
                                   progress: controller.scanProgress)
                } else if let report = controller.report {
                    if report.isClean {
                        EmptyState(icon: "checkmark.shield.fill", title: "Clean",
                                   caption: "Scanned \(report.scanned) file(s) — no threats found. No scare tactics.")
                    } else {
                        Label("\(report.findings.count) finding(s), each with evidence", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.orange)
                        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, f in FindingRow(finding: f) }
                    }
                }
            }
        }
    }

    // MARK: extensions & agents

    private var extensionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("System extensions", icon: "puzzlepiece.extension")
                ForEach(Array(controller.extensions.enumerated()), id: \.offset) { i, ext in
                    if i > 0 { Hairline() }
                    HStack {
                        Text(ext.name.isEmpty ? ext.identifier : ext.name).font(.callout).lineLimit(1)
                        Spacer()
                        StatePill(text: ext.state, ok: ext.state.contains("enabled"))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var orphansCard: some View {
        Card(tint: Palette.warn) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Orphaned launch agents", icon: "bolt.badge.xmark")
                Text("These agents point at programs that no longer exist — usually safe to remove.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(controller.orphans.enumerated()), id: \.offset) { _, o in
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.slash").font(.caption).foregroundStyle(Palette.warn)
                        Text(o.label ?? "?").font(.callout).lineLimit(1)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(o.program ?? "?").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// A compact status tile (icon + label + value) tinted good/warn — the Security header's
/// building block.
struct StatusTile: View {
    let icon: String
    let label: String
    let value: String
    let ok: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(ok ? Palette.good : Palette.warn).imageScale(.small)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.headline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// A small state pill (green when enabled, quiet otherwise).
struct StatePill: View {
    let text: String
    let ok: Bool
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(ok ? Palette.good : Color.secondary)
            .background((ok ? Palette.good : Color.secondary).opacity(0.14), in: Capsule())
    }
}

/// One malware finding, as an evidence card with a severity stripe.
struct FindingRow: View {
    let finding: ScanFinding
    private var crit: Bool { finding.severity == .malicious }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(crit ? Palette.crit : Palette.orange).frame(width: 3)
            Image(systemName: crit ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.title3).foregroundStyle(crit ? Palette.crit : Palette.orange)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(finding.rule).font(.callout.weight(.semibold))
                    StatePill(text: finding.severity.rawValue, ok: false)
                }
                Text(finding.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Text(finding.evidence).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(2)
            }
            Spacer()
        }
        .padding(11)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Tools

struct ToolsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: ToolsController

    private var home: URL { model.paths.home }

    var body: some View {
        SectionScaffold(title: "Tools", subtitle: "One-click cleanup tools and developer utilities") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            SectionTitle("My Tools", icon: "wrench.and.screwdriver")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                toolCard("Trash Bins", "Empty every Trash — undoable via the vault", "trash", Palette.good) { TrashFinder().find() }
                toolCard("App Leftovers", "Data left behind by removed apps", "app.badge.checkmark", Palette.accent) { OrphanFinder().find() }
                toolCard("Old Installers", ".dmg / .pkg / .iso in Downloads", "shippingbox", Palette.accent2) { ClutterFinder().oldInstallers(under: home.appendingPathComponent("Downloads")) }
                toolCard("Screenshots", "Screenshots on the Desktop", "camera.viewfinder", Palette.accent) { ClutterFinder().screenshots(under: home.appendingPathComponent("Desktop")) }
                toolCard("Downloads", "Files older than 30 days", "arrow.down.circle", Palette.accent2) { ClutterFinder().oldDownloads(under: home.appendingPathComponent("Downloads")) }
                toolCard("Mail Attachments", "Locally cached, re-downloadable", "paperclip", Palette.accent) { ClutterFinder().mailAttachments(under: home.appendingPathComponent("Library/Mail")) }
                toolCard("Similar Images", "Keep the best of each group", "photo.on.rectangle.angled", Palette.accent2) {
                    let files = (try? Scanner().scanFiles(under: home.appendingPathComponent("Pictures"), pruning: [], includingHidden: false)) ?? []
                    return SimilarImageFinder().plan(in: files)
                }
            }

            secretsCard
            loginItemsCard
            awakeCard
            maintenanceCard
        }
        .onAppear { controller.loadMeta() }
    }

    private var loginItemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Starts at login", icon: "person.badge.clock")
                if controller.loginItems.isEmpty {
                    Label("No launch agents found.", systemImage: "checkmark.circle").foregroundStyle(Palette.good).font(.callout)
                } else {
                    Text("Launch agents that run when you log in. Ones pointing at a missing program are flagged.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(controller.loginItems.enumerated()), id: \.offset) { i, item in
                        if i > 0 { Hairline() }
                        HStack(spacing: 10) {
                            Image(systemName: item.programExists ? "bolt.fill" : "bolt.slash.fill")
                                .font(.caption).foregroundStyle(item.programExists ? Palette.accent : Palette.warn)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label ?? (item.path as NSString).lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                Text(item.program ?? item.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if !item.programExists { StatePill(text: "orphan", ok: false) }
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.kestrel(.subtle, size: .small)).help("Reveal in Finder")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var secretsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Secrets scanner", icon: "key.horizontal")
                FolderChip(url: controller.project) { controller.pickProject() }
                Button { controller.scanSecrets() } label: {
                    Label(controller.secretsScanning ? "Scanning…" : "Scan for leaked credentials", systemImage: "key.viewfinder")
                }
                .buttonStyle(.kestrel).disabled(controller.secretsScanning)

                if controller.secretsScanning {
                    ScanningBanner(title: "Scanning for leaked secrets…",
                                   detail: "Reading \(controller.project.lastPathComponent)…", tint: Palette.kestrel)
                } else if let secrets = controller.secrets {
                    if secrets.isEmpty {
                        EmptyState(icon: "checkmark.circle.fill", title: "No leaked credentials",
                                   caption: "No API keys, tokens or private keys found in \(controller.project.lastPathComponent).")
                    } else {
                        Label("\(secrets.count) potential secret(s)", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.orange)
                        ForEach(Array(secrets.prefix(40).enumerated()), id: \.offset) { _, m in
                            HStack(spacing: 8) {
                                StatePill(text: m.rule, ok: false)
                                Text("\(m.path):\(m.line)").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var awakeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Keeping the Mac awake", icon: "moon.zzz")
                if controller.sleepers.isEmpty {
                    Label("Nothing is preventing sleep.", systemImage: "checkmark.circle").foregroundStyle(Palette.good).font(.callout)
                } else {
                    ForEach(Array(controller.sleepers.enumerated()), id: \.offset) { _, a in
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer").font(.caption).foregroundStyle(Palette.orange)
                            Text(a.process).font(.callout)
                            Spacer()
                            StatePill(text: a.type, ok: false)
                        }
                    }
                }
            }
        }
    }

    private var maintenanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Maintenance", icon: "wrench.adjustable")
                Text("Advisory — run these yourself; they change system state. Copy the command when you're ready.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(controller.maintenance.enumerated()), id: \.offset) { i, t in
                    if i > 0 { Hairline() }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(t.name).font(.callout.weight(.medium))
                                if t.needsSudo { StatePill(text: "sudo", ok: false) }
                            }
                            Text(t.command).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        CopyButton(text: t.command)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    /// Build a `PlanToolCard` bound to a persistent per-tool state, so its scan survives
    /// navigating away and back.
    private func toolCard(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color,
                          scan: @escaping @Sendable () -> CleanupPlan) -> some View {
        PlanToolCard(id: title, title: title, subtitle: subtitle, icon: icon, tint: tint,
                     state: controller.state(title), scan: scan)
    }
}

/// A copy-to-clipboard button that flips to a checkmark for a moment — used for advisory
/// maintenance commands the user runs themselves.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption.weight(.semibold))
        }
        .buttonStyle(.kestrel(.subtle, tint: copied ? Palette.good : Palette.accent, size: .small))
        .help("Copy command")
    }
}
