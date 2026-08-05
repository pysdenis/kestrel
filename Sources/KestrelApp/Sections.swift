import SwiftUI
import AppKit
import ImageIO
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
                Label(message, systemImage: controller.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(controller.messageIsError ? Palette.warn : Palette.good).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let aiReview = controller.aiReview {
                Card(tint: Palette.violet) {
                    HStack(alignment: .top, spacing: 10) {
                        AssistantAvatar()
                        MarkdownText(text: aiReview).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let advice = controller.aiAdvice {
                Card(tint: Palette.violet) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.clipboard").foregroundStyle(Palette.violet)
                            Text(L("AI cleanup plan")).font(.subheadline.weight(.semibold))
                            if model.aiIsLocal {
                                Text(L("on-device")).font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Palette.good.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Palette.good)
                            }
                        }
                        MarkdownText(text: advice).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if controller.hasSafeItems {
                            Divider().opacity(0.4)
                            HStack(spacing: 8) {
                                Button { controller.selectSafeOnly() } label: {
                                    Label("\(L("Select the safe stuff")) (\(bytesString(controller.safeReclaimBytes)))", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.kestrel(.prominent, tint: Palette.violet, size: .small))
                                Text(L("pre-checks only regenerable items — review below, then Move to Vault")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
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
                        CleanupGroup(category: group.category, items: group.items,
                                     included: controller.isIncluded(group.category),
                                     onToggle: { controller.toggle(group.category) },
                                     isItemIncluded: { controller.isItemIncluded($0) },
                                     onToggleItem: { controller.toggleItem($0) })
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
                Text(model.t("CATEGORY")).font(.system(size: 10.5, weight: .bold)).kerning(0.8).foregroundStyle(.tertiary)
                KestrelSelect(items: CleanupChoice.allCases, selection: $controller.choice,
                              label: { model.t($0.title) }, icon: { $0.icon })

                FolderChip(url: controller.root) { controller.pickFolder() }

                HStack(spacing: 10) {
                    Button { controller.scan() } label: {
                        Label(controller.scanning ? L("Scanning…") : L("Scan for reclaimable space"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel)
                    .disabled(controller.scanning || controller.applying)
                    Label(L("or drop a folder anywhere here"), systemImage: "arrow.down.doc")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: summary

    private func summaryHero(_ plan: CleanupPlan) -> some View {
        let selected = controller.selectedPlan(plan)
        return Card(elevated: true, tint: Palette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bytesString(selected.totalBytes)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(L("reclaimable")) · \(selected.count) \(L("items"))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button { controller.apply() } label: {
                            if controller.applying { KestrelSpinner(tint: .white, size: 15) }
                            else { Label("\(L("Move to Vault")) (\(selected.count))", systemImage: "tray.and.arrow.down") }
                        }
                        .buttonStyle(.kestrel(.prominent))
                        .disabled(controller.applying || selected.items.isEmpty)

                        if model.aiConfigured {
                            Button { controller.advise(assistant: model.aiAssistant, disk: model.disk) } label: {
                                if controller.advising { KestrelSpinner(tint: Palette.violet, size: 14) }
                                else { Label(L("AI cleanup plan"), systemImage: "list.bullet.clipboard") }
                            }
                            .buttonStyle(.kestrel(.subtle, tint: Palette.violet, size: .small))
                            .disabled(controller.advising)

                            Button { controller.review(assistant: model.aiAssistant) } label: {
                                if controller.reviewing { KestrelSpinner(tint: Palette.violet, size: 14) }
                                else { Label(L("AI second opinion"), systemImage: "sparkles") }
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
    var included: Bool = true
    var onToggle: () -> Void = {}
    var isItemIncluded: (URL) -> Bool = { _ in true }
    var onToggleItem: (URL) -> Void = { _ in }
    @State private var expanded = false

    private var subtotal: Int64 { items.reduce(0) { $0 + $1.entry.size } }

    var body: some View {
        let d = category.display
        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onToggle) {
                        Image(systemName: included ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(included ? d.color : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain).help(L("Include in cleanup"))
                    Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: d.icon).foregroundStyle(d.color).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.title).font(.subheadline.weight(.semibold))
                                Text("\(items.count) \(L("item(s)"))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(bytesString(subtotal)).font(.callout.weight(.semibold).monospacedDigit())
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .opacity(included ? 1 : 0.55)

                if expanded {
                    Hairline().padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(80).enumerated()), id: \.offset) { _, item in
                            let itemOn = isItemIncluded(item.entry.url)
                            HStack(spacing: 12) {
                                Button { onToggleItem(item.entry.url) } label: {
                                    Image(systemName: itemOn ? "checkmark.circle.fill" : "circle")
                                        .font(.callout).foregroundStyle(itemOn ? d.color : Color.secondary.opacity(0.5))
                                }
                                .buttonStyle(.plain).help(L("Include this file"))
                                Text(bytesString(item.entry.size)).font(.caption.monospacedDigit().weight(.medium))
                                    .frame(width: 64, alignment: .leading).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.entry.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                        .strikethrough(!itemOn, color: .secondary)
                                    Text(item.entry.url.path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                    Text(item.reason).font(.caption2).foregroundStyle(.secondary.opacity(0.7)).lineLimit(1)
                                }
                                Spacer()
                                Button { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) } label: {
                                    Image(systemName: "magnifyingglass").font(.caption2)
                                }
                                .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .opacity(itemOn ? 1 : 0.5)
                        }
                        if items.count > 80 {
                            Text("+ \(items.count - 80) more item(s) — all included when you clean")
                                .font(.caption).foregroundStyle(.tertiary)
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
            if model.anyBackendAvailable {
                HStack(spacing: 8) { backendSwitcher; Spacer() }
                    .padding(.horizontal, 22).padding(.vertical, 8)
                Hairline()
            }
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

    /// Compact segmented control to switch the answering backend. `fixedSize` keeps it to its
    /// natural width so it never wraps or overlaps the header (unlike the flow-layout chips did).
    private var backendSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(AIBackend.allCases) { b in
                let selected = model.aiBackend == b
                Button { model.setAIBackend(b) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: b == .gemini ? "cloud" : (b == .local ? "cpu" : "wand.and.stars")).imageScale(.small)
                        Text(b.label).font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(selected ? Palette.violet : Color.clear, in: Capsule())
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .fixedSize()
        .help(L("Switch which AI answers: Automatic, Local (Ollama, offline) or Gemini (cloud)."))
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
                HStack(spacing: 8) {
                    Text(L("Assistant")).font(.title3.weight(.bold))
                    if model.aiConfigured {
                        Label(model.aiBackendLabel, systemImage: model.aiIsLocal ? "cpu" : "cloud")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(model.aiIsLocal ? Palette.good : Palette.accent2)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background((model.aiIsLocal ? Palette.good : Palette.accent2).opacity(0.14), in: Capsule())
                    }
                }
                Text(model.aiIsLocal ? L("Honest AI help · fully on-device, nothing leaves your Mac") : L("Honest AI help · sends metadata only"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.aiConfigured, !controller.messages.isEmpty {
                Button { controller.clear() } label: { Label(L("New chat"), systemImage: "square.and.pencil") }
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
            Text(L("Ask me about your Mac's storage, or analyze a folder."))
                .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { controller.send(L(s), assistant: model.aiAssistant, context: model.aiContext()) } label: {
                        Text(L(s)).font(.callout)
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
                    .help("\(L("Choose a folder to analyze:")) \(controller.analyzeRoot.path)")
                Button { controller.analyze(assistant: model.aiAssistant, disk: model.disk) } label: {
                    Label("\(L("Analyze")) \(controller.analyzeRoot.lastPathComponent)", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.kestrel(.subtle, size: .small))
                .disabled(controller.thinking)
                Spacer()
                Text(L("metadata only · never file contents")).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                TextField(L("Ask anything…"), text: $controller.draft, axis: .vertical)
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
            VStack(alignment: .leading, spacing: 12) {
                Label(L("Turn on the assistant"), systemImage: "sparkles").font(.headline)
                Text(L("Best option (free & offline): run a local AI with Ollama — nothing leaves your Mac, no API key, no account."))
                    .font(.callout).foregroundStyle(Palette.good).fixedSize(horizontal: false, vertical: true)

                if model.ollamaBinaryPath == nil {
                    // Ollama not installed — one-click to the installer, then it's auto-detected.
                    Text(L("1. Install Ollama (a small free app). 2. Come back — Kestrel finds it and offers the model."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { model.openOllamaDownload() } label: { Label(L("Install Ollama"), systemImage: "arrow.down.circle") }
                        .buttonStyle(.kestrel(.prominent))
                    Text(L("Prefer the terminal? Run:")).font(.caption).foregroundStyle(.secondary)
                    Text("brew install ollama && brew services start ollama").font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    // Ollama is here — offer to pull the recommended model right from the app.
                    Text("\(L("Ollama is installed. Download the recommended model")) (\(AppModel.recommendedOllamaModel), ~4.7 GB) \(L("and the assistant turns on."))")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.modelPulling {
                        HStack(spacing: 8) {
                            KestrelSpinner(tint: Palette.violet, size: 15)
                            Text(model.modelPullStatus ?? L("Downloading…")).font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Button { model.installRecommendedModel() } label: {
                            Label("\(L("Download AI model")) (\(AppModel.recommendedOllamaModel))", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.kestrel(.prominent))
                        if let status = model.modelPullStatus {
                            Label(status, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.warn)
                        }
                    }
                }

                Hairline()
                Text(L("Or use Google Gemini (cloud) — put your API key in this file:"))
                    .font(.callout).foregroundStyle(.secondary)
                Text(model.paths.geminiKey.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(L("Either way it sends only metadata (names, sizes, categories) — never file contents."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
/// A lightweight Markdown renderer for AI text: paragraphs, bold/italic/inline-code, and bullet /
/// numbered lists. Block structure (lists, paragraphs) is handled here; inline styling comes from
/// AttributedString so `**bold**`, `*italic*` and `` `code` `` render instead of showing raw marks.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    Self.inline(s).fixedSize(horizontal: false, vertical: true)
                case .bullet(let s):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Self.inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(n).").foregroundStyle(.secondary).monospacedDigit()
                        Self.inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// One line/paragraph with inline Markdown resolved to a styled `Text`.
    static func inline(_ s: String) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        guard var attr = try? AttributedString(markdown: s, options: options) else { return Text(s) }
        let codeRanges = attr.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for r in codeRanges { attr[r].font = .system(.callout, design: .monospaced) }
        return Text(attr)
    }

    enum Block { case paragraph(String), bullet(String), numbered(Int, String) }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let b = bulletContent(line) { flush(); out.append(.bullet(b)) }
            else if let (n, s) = numberedContent(line) { flush(); out.append(.numbered(n, s)) }
            else { paragraph.append(line) }
        }
        flush()
        return out
    }

    static func bulletContent(_ line: String) -> String? {
        for p in ["* ", "- ", "• "] where line.hasPrefix(p) { return String(line.dropFirst(p.count)) }
        return nil
    }

    static func numberedContent(_ line: String) -> (Int, String)? {
        guard let sep = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let after = line.index(after: sep)
        guard after < line.endIndex, line[after] == " " else { return nil }   // "1. text", not "3.5 GB"
        let numStr = line[line.startIndex..<sep]
        guard numStr.count <= 2, let n = Int(numStr) else { return nil }
        let rest = String(line[after...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : (n, rest)
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                AssistantAvatar()
                MarkdownText(text: message.text)
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
            bandwidthCard
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
                    Text(b.isCharging ? L("Charging") : L("On battery")).font(.title3.weight(.bold))
                    if let m = model.batteryTimeMinutes {
                        Text(b.isCharging ? "\(L("About")) \(minutesString(m)) \(L("until full"))" : "\(L("About")) \(minutesString(m)) \(L("remaining"))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    if let h = b.healthPercent { EnergyStat(icon: "heart.fill", label: L("Health"), value: "\(h)%", tint: Palette.pink) }
                    if let cy = b.cycleCount { EnergyStat(icon: "arrow.triangle.2.circlepath", label: L("Cycles"), value: "\(cy)", tint: Palette.blue) }
                    if let t = b.temperatureC { EnergyStat(icon: "thermometer.medium", label: L("Temp"), value: "\(Int(t.rounded()))°", tint: Palette.orange) }
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
                        if model.freeingMemory { HStack(spacing: 6) { KestrelSpinner(size: 13); Text(L("Freeing…")) } }
                        else { Label(L("Free up memory"), systemImage: "arrow.down.circle") }
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small))
                    .disabled(model.freeingMemory)
                    .help(L("Runs macOS purge to free inactive memory — non-destructive"))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(m.usedFraction * 100))%").font(.title3.weight(.bold)).monospacedDigit()
                    Text("\(bytesString(m.used)) \(L("of")) \(bytesString(m.total)) \(L("used"))").font(.caption).foregroundStyle(.secondary)
                }
                KestrelProgress(value: m.usedFraction, tint: fractionColor(m.usedFraction), height: 9)
                HStack(spacing: 16) {
                    memLegend(Palette.violet, L("App"), m.active)
                    memLegend(Palette.accent, L("Wired"), m.wired)
                    memLegend(Palette.warn, L("Compressed"), m.compressed)
                    memLegend(.primary.opacity(0.2), L("Free"), m.free)
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
                        Text(L("Reading energy usage…")).foregroundStyle(.secondary).font(.callout)
                    }
                } else {
                    ForEach(Array(model.energyNow.enumerated()), id: \.element.id) { i, proc in
                        if i > 0 { Hairline() }
                        EnergyRow(rank: i + 1, proc: proc, fraction: proc.energyImpact / maxNow,
                                  controller: model.energy, canExplain: model.aiConfigured,
                                  onExplain: { model.energy.explain(proc, assistant: model.aiAssistant) },
                                  onQuit: { confirmQuit(proc) })
                    }
                }
            }
        }
    }

    private var bandwidthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Network usage by app", icon: "network")
                if model.bandwidth.isEmpty {
                    HStack(spacing: 10) {
                        ScanRadar(tint: Palette.accent2, size: 24)
                        Text(L("Measuring per-app traffic…")).foregroundStyle(.secondary).font(.callout)
                    }
                } else {
                    let maxTotal = max(1, model.bandwidth.map(\.total).max() ?? 1)
                    ForEach(model.bandwidth) { app in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(app.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("↓ \(bytesString(app.bytesIn))  ↑ \(bytesString(app.bytesOut))")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            MiniBar(fraction: Double(app.total) / Double(maxTotal), tint: Palette.accent2)
                        }
                        .padding(.vertical, 2)
                    }
                    Text(L("Cumulative traffic since each process started (via nettop). Read-only."))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Most draining — last 24 hours", icon: "clock.arrow.circlepath")
                if model.energy24h.count < 2 {
                    Text(L("Building history… this fills in while Kestrel is running.")).foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(Array(model.energy24h.prefix(10))) { usage in
                        LabeledBar(label: usage.name, value: String(format: "%.0f", usage.total),
                                   fraction: usage.total / max24h, tint: Palette.orange)
                    }
                    if let start = model.energyStart {
                        Text("\(L("Recorded since")) \(start.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func confirmQuit(_ proc: ProcessEnergy) {
        model.requestConfirm(ConfirmRequest(
            icon: "xmark.octagon", tint: Palette.crit,
            title: "\(L("Quit")) \(proc.name)?",
            message: L("This asks the app to quit (SIGTERM). Unsaved work in that app may be lost."),
            confirmLabel: "\(L("Quit")) \(proc.name)", destructive: true,
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

/// A "draining right now" row: the owning app's icon + name (with the raw process name as
/// a subtitle), live CPU%, an impact bar, an optional AI "why?" explanation, and a quit
/// button. The app icon/name are resolved per-row on appear.
struct EnergyRow: View {
    let rank: Int
    let proc: ProcessEnergy
    let fraction: Double
    @ObservedObject var controller: EnergyController
    let canExplain: Bool
    let onExplain: () -> Void
    let onQuit: () -> Void

    @State private var appName = ""
    @State private var appIcon: NSImage?

    private var tint: Color { fraction > 0.66 ? Palette.crit : (fraction > 0.33 ? Palette.orange : Palette.accent) }
    private var displayName: String { appName.isEmpty ? proc.name : appName }
    private var isApp: Bool { !appName.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                Text("\(rank)").font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.tertiary).frame(width: 14)
                Group {
                    if let appIcon { Image(nsImage: appIcon).resizable() }
                    else { Image(systemName: "gearshape.2").resizable().foregroundStyle(.secondary).padding(3) }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayName).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            if isApp, proc.name != appName {
                                Text(proc.name).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer()
                        Text(String(format: "%.0f%% CPU", proc.cpuPercent)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    MiniBar(fraction: fraction, tint: tint)
                }
                if canExplain && controller.explanations[proc.pid] == nil {
                    Button(action: onExplain) {
                        if controller.explaining.contains(proc.pid) { KestrelSpinner(tint: Palette.violet, size: 13) }
                        else { Image(systemName: "sparkles").foregroundStyle(Palette.violet) }
                    }
                    .buttonStyle(.plain).help(L("Why is this using power?"))
                }
                Button(action: onQuit) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Palette.crit)
                }
                .buttonStyle(.plain).help("\(L("Quit")) \(displayName)")
            }
            if let explanation = controller.explanations[proc.pid] {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles").font(.caption2).foregroundStyle(Palette.violet)
                    Text(explanation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .padding(.leading, 51).padding(.trailing, 4)
            }
        }
        .padding(.vertical, 5)
        .onAppear {
            let info = AppResolver.appInfo(forPid: proc.pid)
            appName = info.name
            if let url = info.url { appIcon = NSWorkspace.shared.icon(forFile: url.path) }
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

            if let status = controller.status { protectionHero(status) }
            if let posture = controller.posture { postureCard(posture) }
            if let posture = controller.posture { hardeningCard(posture) }

            canaryCard
            signaturesCard

            scanCard

            if !controller.quarantine.isEmpty { quarantineCard }
            if !controller.extensions.isEmpty { extensionsCard }
            if !controller.orphans.isEmpty { orphansCard }
        }
        .dropFolder { url in controller.root = url; controller.report = nil; controller.scan() }
        .onAppear { controller.loadMeta(); controller.loadSignatures() }
    }

    /// Per-app code-signing verdict — honest facts, no fearmongering. Only a signature that doesn't
    /// verify is highlighted; unsigned/ad-hoc are shown as neutral counts.
    private var signaturesCard: some View {
        Card(tint: controller.signatureAlerts.isEmpty ? nil : Palette.warn) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("App signatures", icon: "signature")
                if controller.signaturesLoading && controller.signatures.isEmpty {
                    HStack(spacing: 10) { KestrelSpinner(tint: Palette.accent, size: 16); Text(L("Inspecting app signatures…")).font(.callout).foregroundStyle(.secondary) }
                } else if controller.signatures.isEmpty {
                    Text(L("No applications found to inspect.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    if controller.signatureAlerts.isEmpty {
                        Label("\(controller.signatures.count) \(L("apps inspected — every signature verifies."))", systemImage: "checkmark.seal.fill")
                            .font(.callout).foregroundStyle(Palette.good)
                    } else {
                        Text("\(controller.signatureAlerts.count) \(L("app(s) whose signature doesn't verify — may have been modified after signing:"))")
                            .font(.callout.weight(.medium)).foregroundStyle(Palette.warn).fixedSize(horizontal: false, vertical: true)
                        ForEach(controller.signatureAlerts) { sig in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.warn)
                                Text(sig.name).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sig.path)]) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                            }
                        }
                    }
                    // Honest breakdown by signing identity.
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(controller.signatureCounts().enumerated()), id: \.offset) { _, pair in
                            Text("\(pair.1) \(L(pair.0.label))")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: ransomware canary (decoys + tamper alert; detection only)

    private var canaryCard: some View {
        let tripped = controller.canaryReport?.isTripped ?? false
        let tint = tripped ? Palette.warn : (controller.canaryArmed ? Palette.good : Palette.accent2)
        return Card(tint: controller.canaryArmed ? tint : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionTitle("Ransomware canary", icon: tripped ? "exclamationmark.shield.fill" : "shield.lefthalf.filled")
                    Spacer()
                    if controller.canaryArmed {
                        StatePill(text: tripped ? L("Tampered!") : L("Armed"), ok: !tripped)
                    }
                }
                Text(L("Kestrel plants harmless decoy files in Documents, Desktop and Pictures and watches them. If something rewrites or deletes them — a hallmark of ransomware — you get warned. Detection only: Kestrel never deletes or changes your files."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if tripped, let report = controller.canaryReport {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L("Decoy files changed unexpectedly — something may be modifying your files. Consider disconnecting from the network and checking recent activity."),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.medium)).foregroundStyle(Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(report.alerts.prefix(10).enumerated()), id: \.offset) { _, a in
                            HStack(spacing: 8) {
                                Image(systemName: a.kind == .deleted ? "trash.slash" : "pencil.slash").font(.caption).foregroundStyle(Palette.warn)
                                Text((a.path as NSString).lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                StatePill(text: a.kind == .deleted ? L("deleted") : L("modified"), ok: false)
                            }
                        }
                    }
                } else if controller.canaryArmed {
                    Text("\(controller.canaryReport?.checked ?? 0) \(L("decoy(s) intact — no sign of mass file tampering."))")
                        .font(.callout).foregroundStyle(Palette.good)
                }

                HStack(spacing: 8) {
                    if controller.canaryArmed {
                        Button { controller.verifyCanary() } label: {
                            if controller.canaryBusy { KestrelSpinner(tint: Palette.accent, size: 14) }
                            else { Label(L("Check now"), systemImage: "arrow.clockwise") }
                        }
                        .buttonStyle(.kestrel(.secondary, size: .small)).disabled(controller.canaryBusy)
                        Button { controller.disarmCanary() } label: { Label(L("Disarm"), systemImage: "shield.slash") }
                            .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.canaryBusy)
                    } else {
                        Button { controller.armCanary() } label: {
                            if controller.canaryBusy { KestrelSpinner(tint: .white, size: 14) }
                            else { Label(L("Arm protection"), systemImage: "shield.lefthalf.filled") }
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small)).disabled(controller.canaryBusy)
                    }
                }
            }
        }
    }

    private var quarantineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Came from the internet", icon: "arrow.down.circle.dotted")
                Text(L("Files in Downloads still flagged by Gatekeeper (quarantine) — normal for anything you downloaded. The agent shows what fetched it."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(controller.quarantine.prefix(30).enumerated()), id: \.offset) { i, q in
                    if i > 0 { Hairline() }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc").font(.caption).foregroundStyle(Palette.accent2)
                        Text((q.path as NSString).lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let agent = q.agent { StatePill(text: agent, ok: false) }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: q.path)]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: security posture (honest checklist)

    private func postureCard(_ p: SecurityPosture) -> some View {
        let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Security posture", icon: "checkerboard.shield")
                Text(L("Your Mac's built-in protections, read straight from the system. Facts only — SIP off is normal on some developer setups."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: cols, spacing: 10) {
                    postureTile("FileVault", "lock.laptopcomputer", p.fileVault, offIsWarn: true)
                    postureTile("Firewall", "network.badge.shield.half.filled", p.firewall, offIsWarn: true)
                    postureTile("Stealth mode", "eye.slash.circle", p.firewallStealth, offIsWarn: false)
                    postureTile("SIP", "cpu", p.sip, offIsWarn: false)
                    postureTile("Gatekeeper", "lock.shield", p.gatekeeper, offIsWarn: true)
                    postureValueTile("XProtect", "checkmark.seal", value: p.xprotectVersion)
                }
            }
        }
    }

    /// A protection with an On/Off/Unknown state. Off is amber only where it *should* be on
    /// (FileVault, Firewall, Gatekeeper); otherwise it's stated neutrally — never as a scare.
    @ViewBuilder private func postureTile(_ label: String, _ icon: String, _ state: SecurityPosture.State, offIsWarn: Bool) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case .on: return (L("On"), Palette.good)
            case .off: return (L("Off"), offIsWarn ? Palette.warn : .secondary)
            case .unknown: return (L("Unknown"), .secondary)
            }
        }()
        postureRow(label: label, icon: icon, valueText: text, color: color)
    }

    @ViewBuilder private func postureValueTile(_ label: String, _ icon: String, value: String?) -> some View {
        let ok = value != nil
        postureRow(label: label, icon: icon, valueText: value ?? L("Unknown"), color: ok ? Palette.good : .secondary)
    }

    private func postureRow(label: String, icon: String, valueText: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).resizable().scaledToFit().foregroundStyle(color).frame(width: 20, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(L(label)).font(.caption.weight(.medium))
                Text(valueText).font(.caption2.monospacedDigit()).foregroundStyle(color)
            }
            Spacer()
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: hardening (actionable recommendations with deep-link fixes)

    private struct Hardening: Identifiable {
        let id = UUID()
        let title: String       // English source
        let why: String         // English source
        let ok: Bool
        let unknown: Bool
        let settingsURL: String
    }

    private func hardeningChecks(_ p: SecurityPosture) -> [Hardening] {
        func mk(_ title: String, wantOn: Bool, _ state: SecurityPosture.State, _ why: String, _ url: String) -> Hardening {
            let ok = wantOn ? state == .on : state == .off
            return Hardening(title: title, why: why, ok: ok, unknown: state == .unknown, settingsURL: url)
        }
        return [
            mk("Turn on FileVault", wantOn: true, p.fileVault,
               "Encrypts your disk so a lost or stolen Mac can't be read.",
               "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"),
            mk("Turn on the firewall", wantOn: true, p.firewall,
               "Blocks unsolicited incoming network connections.",
               "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Firewall"),
            mk("Enable automatic updates", wantOn: true, p.automaticUpdates,
               "Security fixes install as soon as Apple ships them.",
               "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
            mk("Disable the guest account", wantOn: false, p.guestAccount,
               "A guest login is one more way in — turn it off if you don't use it.",
               "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"),
            mk("Keep Gatekeeper on", wantOn: true, p.gatekeeper,
               "Stops unsigned, unnotarized apps from launching by accident.",
               "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
        ]
    }

    @ViewBuilder private func hardeningCard(_ p: SecurityPosture) -> some View {
        let checks = hardeningChecks(p)
        let known = checks.filter { !$0.unknown }
        let actionable = known.filter { !$0.ok }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Hardening", icon: "lock.badge.clock")
                    Spacer()
                    Text("\(known.count - actionable.count)/\(known.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(actionable.isEmpty ? Palette.good : Palette.warn)
                }
                Text(L("One-tap jumps to each setting. Kestrel reads your posture but never flips a system switch behind your back.")).font(.caption).foregroundStyle(.secondary)
                if actionable.isEmpty {
                    Label(L("Your Mac is well hardened — nothing to change."), systemImage: "checkmark.shield.fill")
                        .font(.callout).foregroundStyle(Palette.good)
                } else {
                    ForEach(actionable) { c in
                        Hairline()
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.shield").font(.callout).foregroundStyle(Palette.warn).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L(c.title)).font(.callout.weight(.medium))
                                Text(L(c.why)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button { if let u = URL(string: c.settingsURL) { NSWorkspace.shared.open(u) } } label: {
                                Label(L("Fix"), systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.kestrel(.secondary, size: .small))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
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
                        Text(ok ? L("macOS protection is on") : L("Protection needs a look")).font(.title3.weight(.bold))
                        Text(ok ? L("Gatekeeper and XProtect are active.") : L("One of macOS's built-in defenses is off."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatusTile(icon: "lock.shield", label: "Gatekeeper",
                               value: status.assessmentsEnabled == true ? L("On") : (status.assessmentsEnabled == false ? L("Off") : L("Unknown")),
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
                    Label(controller.scanning ? L("Scanning…") : L("Scan for malware"), systemImage: "shield.checkerboard")
                }
                .buttonStyle(.kestrel).disabled(controller.scanning)

                if controller.scanning {
                    ScanningBanner(title: "Scanning for threats…",
                                   detail: controller.scanStatus.isEmpty ? "\(L("Reading files in")) \(controller.root.lastPathComponent)…" : controller.scanStatus,
                                   progress: controller.scanProgress)
                } else if let report = controller.report {
                    if report.isClean {
                        EmptyState(icon: "checkmark.shield.fill", title: "No threats",
                                   caption: "\(L("Scanned")) \(report.scanned) \(L("file(s) — no threats found. No scare tactics."))")
                    } else {
                        Label("\(report.findings.count) \(L("finding(s), each with evidence"))", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.orange)
                        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, f in
                            let key = SecurityController.findingKey(f)
                            FindingRow(finding: f,
                                       explanation: controller.explanations[key],
                                       explaining: controller.explaining.contains(key),
                                       canExplain: model.aiConfigured,
                                       onExplain: { controller.explain(f, assistant: model.aiAssistant) })
                        }
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
                Text(L("These agents point at programs that no longer exist — usually safe to remove."))
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

/// One malware finding, as an evidence card with a severity stripe. When the assistant is
/// configured it offers an on-demand "Explain" (metadata-only, invariant #7).
struct FindingRow: View {
    let finding: ScanFinding
    var explanation: String? = nil
    var explaining: Bool = false
    var canExplain: Bool = false
    var onExplain: () -> Void = {}

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
                    Spacer()
                    if canExplain && explanation == nil {
                        Button(action: onExplain) {
                            if explaining { KestrelSpinner(tint: Palette.violet, size: 12) }
                            else { Label(L("Explain"), systemImage: "sparkles") }
                        }
                        .buttonStyle(.kestrel(.subtle, tint: Palette.violet, size: .small))
                        .disabled(explaining)
                    }
                }
                Text(finding.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Text(finding.evidence).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(2)
                if let explanation {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(Palette.violet)
                        Text(explanation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.top, 3)
                }
            }
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

            HStack {
                SectionTitle("My Tools", icon: "wrench.and.screwdriver")
                Spacer()
                Button { for t in tools { controller.runTool(t.id, scan: t.scan) } } label: { Label(L("Scan all"), systemImage: "square.stack.3d.up") }
                    .buttonStyle(.kestrel(.secondary, size: .small))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(tools) { t in
                    PlanToolCard(id: t.id, title: t.title, subtitle: t.subtitle, icon: t.icon, tint: t.tint,
                                 state: controller.state(t.id), scan: t.scan)
                }
            }

            photosCard
            duplicatesCard
            largestFilesCard
            deviceBackupsCard
            devCachesCard
            privacyCard
            secretsCard
            cloudCard
            loginItemsCard
            awakeCard
            maintenanceCard
        }
        .onAppear { controller.loadMeta() }
    }

    private var photosCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Similar Images", icon: "photo.on.rectangle.angled")
                    Spacer()
                    Button { controller.scanPhotos() } label: {
                        Label(controller.photoScanning ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.photoScanning)
                }
                Text(L("Finds look-alike photos in your Pictures. The best of each group is kept; tap a photo to change what moves to the vault.")).font(.caption).foregroundStyle(.secondary)
                if let m = controller.photoMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.photoScanning {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.accent2, size: 24); Text(L("Scanning your photos…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.photoGroups.isEmpty {
                    Text(L("Scan to find similar or duplicate photos you can thin out.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Text("\(controller.photoGroups.count) \(L("group(s)")) · \(controller.photoRemoval.count) \(L("selected")) · \(bytesString(controller.photoRemovalBytes))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button { controller.applyPhotos() } label: {
                            Label(controller.photoApplying ? L("Moving…") : L("Move to Vault"), systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(controller.photoRemoval.isEmpty || controller.photoApplying)
                    }
                    ForEach(Array(controller.photoGroups.prefix(12).enumerated()), id: \.offset) { gi, group in
                        if gi > 0 { Hairline() }
                        photoGroupRow(group)
                    }
                    if controller.photoGroups.count > 12 {
                        Text("+\(controller.photoGroups.count - 12) \(L("more group(s)"))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func photoGroupRow(_ group: [FileEntry]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(group.enumerated()), id: \.offset) { idx, file in
                    let removing = controller.photoRemoval.contains(file.url)
                    VStack(spacing: 4) {
                        PhotoThumb(url: file.url)
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(removing ? Palette.crit : Palette.good, lineWidth: 2))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: removing ? "trash.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 15)).foregroundStyle(removing ? Palette.crit : Palette.good)
                                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor))).padding(3)
                            }
                            .overlay(alignment: .bottomLeading) {
                                if idx == 0 {
                                    Text(L("Best")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Palette.good, in: Capsule()).padding(3)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { controller.togglePhoto(file.url) }
                            .help(file.url.lastPathComponent)
                        Text(bytesString(file.size)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var duplicatesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Duplicate Files", icon: "doc.on.doc")
                    Spacer()
                    Button { controller.scanDuplicates() } label: {
                        Label(controller.dupScanning ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.dupScanning)
                }
                Text(L("Byte-identical files in a folder you pick. One copy is kept; tap any file to change what moves to the vault.")).font(.caption).foregroundStyle(.secondary)
                FolderChip(url: controller.dupFolder) { controller.pickDupFolder() }
                if let m = controller.dupMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.dupScanning {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.violet, size: 24); Text(L("Hashing files…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.dupGroups.isEmpty {
                    Text(L("Scan the folder to find exact duplicates you can remove.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Text("\(controller.dupGroups.count) \(L("group(s)")) · \(controller.dupRemoval.count) \(L("selected")) · \(bytesString(controller.dupRemovalBytes))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if controller.dupCloneSupported {
                            Button { controller.dedupeDuplicates() } label: {
                                Label(controller.dupApplying ? L("Working…") : L("Dedupe (APFS)"), systemImage: "square.on.square.dashed")
                            }
                            .buttonStyle(.kestrel(.secondary, size: .small))
                            .disabled(controller.dupRemoval.isEmpty || controller.dupApplying)
                            .help(L("Reclaim the space but keep both files — they share storage until edited."))
                        }
                        Button { controller.applyDuplicates() } label: {
                            Label(controller.dupApplying ? L("Moving…") : L("Move to Vault"), systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(controller.dupRemoval.isEmpty || controller.dupApplying)
                    }
                    ForEach(Array(controller.dupGroups.prefix(20))) { group in
                        dupGroupRow(group)
                    }
                    if controller.dupGroups.count > 20 {
                        Text("+\(controller.dupGroups.count - 20) \(L("more group(s)"))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func dupGroupRow(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Hairline()
            dupFileRow(group.original, isOriginal: true)
            ForEach(Array(group.copies.enumerated()), id: \.offset) { _, copy in
                dupFileRow(copy, isOriginal: false)
            }
        }
    }

    @ViewBuilder private func dupFileRow(_ file: FileEntry, isOriginal: Bool) -> some View {
        let removing = !isOriginal && controller.dupRemoval.contains(file.url)
        HStack(spacing: 10) {
            if isOriginal {
                Image(systemName: "lock.circle.fill").font(.callout).foregroundStyle(Palette.good)
            } else {
                Button { controller.toggleDup(file.url) } label: {
                    Image(systemName: removing ? "checkmark.circle.fill" : "circle")
                        .font(.callout).foregroundStyle(removing ? Palette.crit : .secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path).font(.caption2.monospaced())
                    .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if isOriginal {
                Text(L("Keep")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1).background(Palette.good, in: Capsule())
            }
            Text(bytesString(file.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
        }
        .padding(.vertical, 2)
        .opacity(isOriginal || removing ? 1 : 0.6)
    }

    private var largestFilesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Largest files", icon: "arrow.up.arrow.down.square")
                    Spacer()
                    Button { controller.loadLargestFiles() } label: {
                        Label(controller.largestLoading ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.largestLoading)
                }
                Text(L("The biggest individual files in your Home — a fast way to find single space hogs. Review-only: each moves to the vault (undoable) only when you choose.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let m = controller.largestMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.largestLoading {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.accent, size: 24); Text(L("Scanning for large files…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.largestFiles.isEmpty {
                    Text(L("Scan to list the biggest files taking up space.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Text("\(controller.largestFiles.count) \(L("file(s)")) · \(bytesString(controller.largestFiles.reduce(0) { $0 + $1.entry.size }))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(Array(controller.largestFiles.enumerated()), id: \.offset) { i, item in
                        if i > 0 { Hairline() }
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill").font(.caption).foregroundStyle(Palette.accent2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.entry.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Text(item.entry.url.deletingLastPathComponent().path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(bytesString(item.entry.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.entry.url]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                            Button { controller.moveLargeFileToVault(item) } label: { Image(systemName: "tray.and.arrow.down") }
                                .buttonStyle(.kestrel(.secondary, size: .small)).help(L("Move to Vault"))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var deviceBackupsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("iOS backups", icon: "iphone.gen3")
                    Spacer()
                    Button { controller.loadDeviceBackups() } label: {
                        Label(controller.backupsLoading ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.backupsLoading)
                }
                Text(L("Local iPhone/iPad backups, oldest first — often the biggest reclaim on a Mac. This may be your only backup, so removal is per-item and goes to the vault (undoable).")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let m = controller.backupsMessage {
                    Label(m, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                if controller.deviceBackups.isEmpty && !controller.backupsLoading {
                    Text(L("Scan to list local device backups.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(controller.deviceBackups) { backup in
                        if backup.id != controller.deviceBackups.first?.id { Hairline() }
                        HStack(spacing: 10) {
                            Image(systemName: "iphone").font(.callout).foregroundStyle(Palette.accent2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(backup.deviceName).font(.callout.weight(.medium)).lineLimit(1)
                                Text(backup.lastBackup.map { "\(L("last backup")) \($0.formatted(date: .abbreviated, time: .omitted))" } ?? L("date unknown"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(bytesString(backup.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup.path)]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                            Button { confirmMoveBackup(backup) } label: { Image(systemName: "tray.and.arrow.down") }
                                .buttonStyle(.kestrel(.secondary, size: .small)).help(L("Move to Vault"))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    /// Extra confirm for a device backup — it can be irreplaceable, so make the user mean it.
    private func confirmMoveBackup(_ backup: DeviceBackup) {
        model.requestConfirm(ConfirmRequest(
            icon: "iphone", tint: Palette.warn,
            title: "\(L("Move")) \(backup.deviceName) \(L("backup to the vault?"))",
            message: L("It moves to the reversible vault (undoable until purge). If this is your only backup of that device, make sure you have another."),
            confirmLabel: L("Move to Vault"), destructive: true,
            onConfirm: { controller.moveBackupToVault(backup) }))
    }

    private var devCachesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Developer caches", icon: "hammer")
                    Spacer()
                    Button { controller.loadDevCaches() } label: {
                        Label(controller.devCachesLoading ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.devCachesLoading)
                }
                Text(L("Global caches of npm, pip, Homebrew, Gradle, Cargo, Go, CocoaPods, DerivedData and more — all rebuilt on demand, so clearing them only costs a re-download.")).font(.caption).foregroundStyle(.secondary)
                if let m = controller.devCachesMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.devCachesLoading {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.accent, size: 24); Text(L("Measuring developer caches…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.devCaches.isEmpty {
                    Text(L("Scan to size up your package-manager and build caches.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Text("\(controller.devCaches.count) \(L("cache(s)")) · \(bytesString(controller.devCaches.reduce(0) { $0 + $1.size }))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(controller.devCaches) { cache in
                        if cache.id != controller.devCaches.first?.id { Hairline() }
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.fill").font(.caption).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cache.tool).font(.callout.weight(.medium))
                                Text(cache.url.path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(bytesString(cache.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button { controller.clearDevCache(cache) } label: { Label(L("Move to Vault"), systemImage: "tray.and.arrow.down") }
                                .buttonStyle(.kestrel(.secondary, size: .small))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var privacyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Privacy", icon: "eye.slash")
                    Spacer()
                    Button { controller.loadPrivacy() } label: {
                        Label(controller.privacyLoading ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.privacyLoading)
                }
                Text(L("Browser caches, history and cookies. Nothing is preselected — clearing history signs you out of sites. Passwords and bookmarks are never touched.")).font(.caption).foregroundStyle(.secondary)
                if let m = controller.privacyMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.privacyLoading {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.pink, size: 24); Text(L("Looking for browser data…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.privacyItems.isEmpty {
                    Text(L("Scan to find browsing traces you can clear.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    HStack {
                        Text("\(controller.privacySelection.count) \(L("selected")) · \(bytesString(controller.privacySelectionBytes))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button { controller.applyPrivacy() } label: {
                            Label(controller.privacyApplying ? L("Clearing…") : L("Move to Vault"), systemImage: "tray.and.arrow.down")
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(controller.privacySelection.isEmpty || controller.privacyApplying)
                    }
                    ForEach(controller.privacyItems) { item in
                        if item.id != controller.privacyItems.first?.id { Hairline() }
                        let picked = controller.privacySelection.contains(item.url)
                        HStack(spacing: 10) {
                            Button { controller.togglePrivacy(item.url) } label: {
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                    .font(.callout).foregroundStyle(picked ? Palette.pink : .secondary)
                            }
                            .buttonStyle(.plain)
                            Image(systemName: privacyKindIcon(item.kind)).font(.caption).foregroundStyle(Palette.pink).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.app) · \(L(item.kind.rawValue))").font(.callout.weight(.medium))
                                Text(privacyConsequence(item.kind)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(bytesString(item.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .opacity(picked ? 1 : 0.7)
                    }
                }
            }
        }
    }

    private func privacyKindIcon(_ kind: PrivacyItem.Kind) -> String {
        switch kind { case .cache: return "photo.stack"; case .history: return "clock.arrow.circlepath"; case .cookies: return "circle.grid.2x2" }
    }
    private func privacyConsequence(_ kind: PrivacyItem.Kind) -> String {
        switch kind {
        case .cache: return L("Safe — just re-downloaded as you browse.")
        case .history: return L("Clears your browsing history.")
        case .cookies: return L("Signs you out of websites.")
        }
    }

    private var cloudCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Cloud Cleanup (iCloud)", icon: "icloud")
                    Spacer()
                    Button { controller.loadCloud() } label: {
                        Label(controller.cloudLoading ? L("Scanning…") : L("Scan"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(controller.cloudLoading)
                }
                Text(L("Large files iCloud keeps a local copy of — offload to free space; they stay in iCloud.")).font(.caption).foregroundStyle(.secondary)
                if let m = controller.cloudMessage {
                    Label(m, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.good)
                }
                if controller.cloudLoading {
                    HStack(spacing: 10) { ScanRadar(tint: Palette.accent2, size: 24); Text(L("Scanning iCloud Drive…")).foregroundStyle(.secondary).font(.callout) }
                } else if controller.cloudFiles.isEmpty {
                    Text(L("Scan to find large local iCloud copies you can offload.")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(controller.cloudFiles.prefix(20).enumerated()), id: \.offset) { _, file in
                        HStack(spacing: 10) {
                            Image(systemName: "icloud.and.arrow.down").font(.caption).foregroundStyle(Palette.accent2)
                            Text(file.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(bytesString(file.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button { controller.offload(file) } label: { Text(L("Offload")) }
                                .buttonStyle(.kestrel(.secondary, tint: Palette.accent2, size: .small))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var loginItemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Starts at login", icon: "person.badge.clock")
                if controller.loginItems.isEmpty {
                    Label(L("No launch agents found."), systemImage: "checkmark.circle").foregroundStyle(Palette.good).font(.callout)
                } else {
                    Text(L("Launch agents that run when you log in. Ones pointing at a missing program are flagged."))
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
                    Label(controller.secretsScanning ? L("Scanning…") : L("Scan for leaked credentials"), systemImage: "key.viewfinder")
                }
                .buttonStyle(.kestrel).disabled(controller.secretsScanning)

                if controller.secretsScanning {
                    ScanningBanner(title: "Scanning for leaked secrets…",
                                   detail: "\(L("Reading")) \(controller.project.lastPathComponent)…", tint: Palette.kestrel)
                } else if let secrets = controller.secrets {
                    if secrets.isEmpty {
                        EmptyState(icon: "checkmark.circle.fill", title: "No leaked credentials",
                                   caption: "\(L("No API keys, tokens or private keys found in")) \(controller.project.lastPathComponent).")
                    } else {
                        Label("\(secrets.count) \(L("potential secret(s)"))", systemImage: "exclamationmark.triangle.fill")
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
                    Label(L("Nothing is preventing sleep."), systemImage: "checkmark.circle").foregroundStyle(Palette.good).font(.callout)
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
                Text(L("Advisory — run these yourself; they change system state. Copy the command when you're ready."))
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

    /// One toolbox tool: a stable English `id` (used as the persistent state + scan-all
    /// key) and a localized title/subtitle.
    private struct ToolDef: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let scan: @Sendable () -> CleanupPlan
    }

    private var tools: [ToolDef] { Self.toolDefs(home: home) }

    // Built off the main actor so the @Sendable scan closures capture only the passed-in URL
    // (no actor state), keeping the whole thing free of data-race warnings.
    nonisolated private static func toolDefs(home: URL) -> [ToolDef] {
        [
            ToolDef(id: "Trash Bins", title: L("Trash Bins"), subtitle: L("Empty every Trash — undoable via the vault"), icon: "trash", tint: Palette.good) { TrashFinder().find() },
            ToolDef(id: "App Leftovers", title: L("App Leftovers"), subtitle: L("Data left behind by removed apps"), icon: "app.badge.checkmark", tint: Palette.accent) { OrphanFinder().find() },
            ToolDef(id: "Old Installers", title: L("Old Installers"), subtitle: L(".dmg / .pkg / .iso in Downloads"), icon: "shippingbox", tint: Palette.accent2) { ClutterFinder().oldInstallers(under: home.appendingPathComponent("Downloads")) },
            ToolDef(id: "Screenshots", title: L("Screenshots"), subtitle: L("Screenshots on the Desktop"), icon: "camera.viewfinder", tint: Palette.accent) { ClutterFinder().screenshots(under: home.appendingPathComponent("Desktop")) },
            ToolDef(id: "Downloads", title: L("Downloads"), subtitle: L("Files older than 30 days"), icon: "arrow.down.circle", tint: Palette.accent2) { ClutterFinder().oldDownloads(under: home.appendingPathComponent("Downloads")) },
            ToolDef(id: "Mail Attachments", title: L("Mail Attachments"), subtitle: L("Locally cached, re-downloadable"), icon: "paperclip", tint: Palette.accent) { ClutterFinder().mailAttachments(under: home.appendingPathComponent("Library/Mail")) },
        ]
    }
}

/// A bounded, memory-pressure-aware cache of decoded thumbnails. NSCache is thread-safe and auto-
/// evicts when the system needs RAM; we also cap the count so scrolling a huge image group never
/// balloons memory, while scrolling back reuses an earlier decode instead of paying for it again.
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 240   // a few visible groups' worth; older thumbnails evict automatically
        return c
    }()
    static func image(for key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    static func store(_ image: NSImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// A lazily-loaded, downscaled thumbnail for a local image file. Uses ImageIO (thread-safe,
/// reuses any embedded thumbnail) off the main actor so scrolling a group stays smooth, and a
/// bounded cache so scrolling back doesn't re-decode while memory stays capped.
struct PhotoThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        }
        .task(id: url) { image = await Self.thumbnail(url) }
    }

    /// Off-main image decode hands the finished NSImage back through a one-shot box — the image
    /// is freshly created and passed exactly once, so the unchecked Sendable is safe.
    private struct Box: @unchecked Sendable { let image: NSImage? }

    static func thumbnail(_ url: URL, maxPixel: CGFloat = 200) async -> NSImage? {
        let key = "\(url.path)#\(Int(maxPixel))"
        if let cached = ThumbnailCache.image(for: key) { return cached }
        let decoded = await Task.detached(priority: .utility) { () -> Box in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return Box(image: nil) }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return Box(image: nil) }
            return Box(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        }.value.image
        if let decoded { ThumbnailCache.store(decoded, for: key) }
        return decoded
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
