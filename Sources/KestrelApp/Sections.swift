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
    }

    // MARK: config

    private var configCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                Text("CATEGORY").font(.system(size: 10.5, weight: .bold)).kerning(0.8).foregroundStyle(.tertiary)
                KestrelSelect(items: CleanupChoice.allCases, selection: $controller.choice,
                              label: { $0.title }, icon: { $0.icon })

                FolderChip(url: controller.root) { controller.pickFolder() }

                Button { controller.scan() } label: {
                    Label(controller.scanning ? "Scanning…" : "Scan for reclaimable space", systemImage: "magnifyingglass")
                }
                .buttonStyle(.kestrel)
                .disabled(controller.scanning || controller.applying)
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
            if let b = model.battery {
                Card {
                    HStack(spacing: 22) {
                        badge(icon: b.isCharging ? "battery.100.bolt" : "battery.75", title: "Charge", value: "\(b.percent)%", tint: Palette.good)
                        if let h = b.healthPercent { badge(icon: "heart.text.square", title: "Health", value: "\(h)%", tint: Palette.pink) }
                        if let cy = b.cycleCount { badge(icon: "arrow.triangle.2.circlepath", title: "Cycles", value: "\(cy)", tint: Palette.blue) }
                        badge(icon: "bolt", title: "State", value: b.isCharging ? "Charging" : "On battery", tint: Palette.orange)
                        if let m = model.batteryTimeMinutes {
                            badge(icon: b.isCharging ? "battery.100.bolt" : "hourglass",
                                  title: b.isCharging ? "Full in" : "Time left", value: minutesString(m), tint: Palette.teal)
                        }
                        Spacer()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Draining right now", icon: "bolt.fill")
                    if model.energyNow.isEmpty {
                        HStack(spacing: 10) {
                            ScanRadar(tint: Palette.orange, size: 24)
                            Text("Reading energy usage…").foregroundStyle(.secondary).font(.callout)
                        }
                    } else {
                        ForEach(model.energyNow) { proc in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(proc.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(String(format: "%.0f%% CPU", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    MiniBar(fraction: proc.energyImpact / maxNow)
                                }
                                Button { confirmQuit(proc) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.crit)
                                }
                                .buttonStyle(.plain).help("Quit \(proc.name)")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
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
        .onAppear { model.energyAppeared() }
        .onDisappear { model.energyDisappeared() }
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

    private func badge(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
        }
    }
}

// MARK: - Security

struct SecuritySection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: SecurityController

    var body: some View {
        SectionScaffold(title: "Security", subtitle: "Honest, evidence-based checks — no scare tactics") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            if let status = controller.status {
                Card {
                    HStack(spacing: 20) {
                        badge("Gatekeeper", status.assessmentsEnabled == true ? "On" : (status.assessmentsEnabled == false ? "Off" : "?"),
                              ok: status.assessmentsEnabled == true)
                        badge("XProtect", status.xprotectVersion ?? "—", ok: status.xprotectVersion != nil)
                        Spacer()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Scan for threats", icon: "magnifyingglass")
                    HStack {
                        Image(systemName: "folder")
                        Text(controller.root.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { controller.pickFolder() }.buttonStyle(.kestrel(.subtle, size: .small))
                        Button { controller.scan() } label: {
                            Text(controller.scanning ? "Scanning…" : "Scan")
                        }
                        .buttonStyle(.kestrel).disabled(controller.scanning)
                    }
                    if controller.scanning {
                        ScanningBanner(title: "Scanning for threats…",
                                       detail: controller.scanStatus.isEmpty ? "Reading files in \(controller.root.lastPathComponent)…" : controller.scanStatus,
                                       progress: controller.scanProgress)
                    } else if let report = controller.report {
                        if report.isClean {
                            EmptyState(icon: "checkmark.shield.fill", title: "Clean",
                                       caption: "Scanned \(report.scanned) file(s) — no threats. No scare tactics.")
                        } else {
                            Label("\(report.findings.count) finding(s) with evidence", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.orange)
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, f in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: f.severity == .malicious ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(f.severity == .malicious ? Palette.crit : Palette.orange)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(f.rule)  ·  \(f.severity.rawValue)").font(.callout.weight(.medium))
                                        Text(f.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        Text(f.evidence).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }

            if !controller.extensions.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("System extensions", icon: "puzzlepiece.extension")
                        ForEach(Array(controller.extensions.enumerated()), id: \.offset) { _, ext in
                            HStack {
                                Text(ext.name.isEmpty ? ext.identifier : ext.name).font(.callout).lineLimit(1)
                                Spacer()
                                Text(ext.state).font(.caption).foregroundStyle(ext.state.contains("enabled") ? Palette.good : .secondary)
                            }
                        }
                    }
                }
            }

            if !controller.orphans.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Orphaned launch agents", icon: "bolt.badge.xmark")
                        ForEach(Array(controller.orphans.enumerated()), id: \.offset) { _, o in
                            Text("\(o.label ?? "?") → \(o.program ?? "?")").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .onAppear { controller.loadMeta() }
    }

    private func badge(_ title: String, _ value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Label(value, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Palette.good : Palette.crit).font(.headline)
        }
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

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Secrets scanner", icon: "key.horizontal")
                    HStack {
                        Text(controller.project.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { controller.pickProject() }.buttonStyle(.kestrel(.subtle, size: .small))
                        Button { controller.scanSecrets() } label: {
                            Text(controller.secretsScanning ? "Scanning…" : "Scan")
                        }
                        .buttonStyle(.kestrel).disabled(controller.secretsScanning)
                    }
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
                                Text("[\(m.rule)] \(m.path):\(m.line)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Keeping the Mac awake", icon: "moon.zzz")
                    if controller.sleepers.isEmpty {
                        Label("Nothing is preventing sleep.", systemImage: "checkmark.circle").foregroundStyle(Palette.good)
                    } else {
                        ForEach(Array(controller.sleepers.enumerated()), id: \.offset) { _, a in
                            Text("\(a.process) — \(a.type)").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Maintenance", icon: "wrench.adjustable")
                    Text("Run these yourself — they change system state.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(controller.maintenance.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name + (t.needsSudo ? "  (needs sudo)" : "")).font(.callout.weight(.medium))
                            Text(t.command).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .onAppear { controller.loadMeta() }
    }

    /// Build a `PlanToolCard` bound to a persistent per-tool state, so its scan survives
    /// navigating away and back.
    private func toolCard(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color,
                          scan: @escaping @Sendable () -> CleanupPlan) -> some View {
        PlanToolCard(id: title, title: title, subtitle: subtitle, icon: icon, tint: tint,
                     state: controller.state(title), scan: scan)
    }
}
