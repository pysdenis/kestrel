import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KestrelCore

// A small, consistent design language: material cards, a health ring, metric tiles and
// helpers. Everything uses semantic colors and materials so it adapts to light/dark.

func healthColor(_ score: Int) -> Color {
    switch score {
    case 80...: return Palette.good
    case 50..<80: return Palette.warn
    default: return Palette.crit
    }
}

/// A short, honest one-liner for the Mac Health score.
func healthVerdict(_ score: Int) -> String {
    switch score {
    case 90...: return "Your Mac is in great shape"
    case 80..<90: return "Your Mac is running well"
    case 65..<80: return "A little upkeep would help"
    case 50..<65: return "Some things need attention"
    default: return "Needs attention"
    }
}

func fractionColor(_ fraction: Double) -> Color {
    switch fraction {
    case 0.9...: return Palette.crit
    case 0.75..<0.9: return Palette.orange
    default: return Palette.accent
    }
}

func bytesString(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

extension ExecutionResult {
    /// The shared " N couldn't be moved …" tail appended to every apply message, so the
    /// honest reporting of failures lives in one place.
    var failureSuffix: String {
        failures.isEmpty ? "" : " \(failures.count) couldn't be moved — likely permissions."
    }
}

/// "1h 20m" / "45m" from a minute count.
func minutesString(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

/// A caption that prefers a time estimate, falling back to health/state.
func batteryCaption(_ b: BatteryStats) -> String {
    if b.isCharging, let m = b.timeToFullMinutes { return "\(minutesString(m)) to full" }
    if !b.isCharging, let m = b.timeToEmptyMinutes { return "\(minutesString(m)) left" }
    return b.healthPercent.map { "health \($0)%" } ?? (b.isCharging ? "charging" : "on battery")
}

/// Modern pill buttons with a soft gradient, a spring press, and a quiet secondary
/// variant. Used everywhere so buttons feel like one family, not stock controls.
struct KestrelButtonStyle: ButtonStyle {
    enum Kind { case prominent, secondary, subtle }
    var kind: Kind = .prominent
    var tint: Color = Palette.accent
    var size: ControlSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        let vPad: CGFloat = size == .small ? 5 : 8
        let hPad: CGFloat = size == .small ? 11 : 15
        return configuration.label
            .font((size == .small ? Font.caption : Font.callout).weight(.semibold))
            .padding(.vertical, vPad)
            .padding(.horizontal, hPad)
            .foregroundStyle(foreground)
            .background(background, in: Capsule(style: .continuous))
            .overlay(kind == .secondary ? Capsule().strokeBorder(.white.opacity(0.08)) : nil)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: some ShapeStyle {
        kind == .prominent ? AnyShapeStyle(.white) : AnyShapeStyle(tint)
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .prominent: return AnyShapeStyle(tint.gradient)
        case .secondary: return AnyShapeStyle(tint.opacity(0.14))
        case .subtle: return AnyShapeStyle(.quaternary)
        }
    }
}

extension ButtonStyle where Self == KestrelButtonStyle {
    static var kestrel: KestrelButtonStyle { KestrelButtonStyle() }
    static func kestrel(_ kind: KestrelButtonStyle.Kind, tint: Color = Palette.accent, size: ControlSize = .regular) -> KestrelButtonStyle {
        KestrelButtonStyle(kind: kind, tint: tint, size: size)
    }
}

/// A padded, rounded material container. A hairline top-light stroke and a soft drop
/// shadow give it the graphite depth of the Precision language; `elevated` deepens the
/// shadow and warms the stroke for hero surfaces.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var elevated: Bool = false
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
                        }
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(elevated ? 0.14 : 0.08), .white.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(elevated ? 0.16 : 0.06), radius: elevated ? 22 : 10, y: elevated ? 10 : 4)
    }
}

/// A segmented ring gauge (battery detail) — ticks around a circle, filled by fraction.
struct SegmentedRing: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var segments: Int = 44
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { i in
                let on = Double(i) / Double(segments) < min(1, max(0, fraction))
                Capsule()
                    .fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: max(2, size * 0.022), height: size * 0.1)
                    .shadow(color: on ? tint.opacity(0.55) : .clear, radius: on ? 3 : 0)
                    .offset(y: -size * 0.41)
                    .rotationEffect(.degrees(Double(i) / Double(segments) * 360))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Circular Mac Health gauge.
struct HealthRing: View {
    let score: Int
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: max(0.001, CGFloat(score) / 100))
                .stroke(
                    AngularGradient(colors: [healthColor(score).opacity(0.6), healthColor(score)], center: .center),
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: score)
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).monospacedDigit()
                Text(L("HEALTH")).font(.system(size: size * 0.11, weight: .semibold)).foregroundStyle(.secondary).kerning(1)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A metric tile built around a radial gauge — the dashboard's instrument look.
struct RadialMetricTile: View {
    let icon: String
    let title: String
    let centerValue: String
    let fraction: Double
    var detail: String = ""
    var iconTint: Color = Palette.accent
    var ringColor: Color = Palette.accent
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        Card {
            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(iconTint).imageScale(.small)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if onTap != nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                }
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, max(0, fraction)))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                    Text(centerValue).font(.title3.weight(.bold)).monospacedDigit()
                }
                .frame(width: 86, height: 86)
                .padding(.vertical, 2)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// A metric tile with an icon, big value, optional progress bar and a caption.
struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var detail: String = ""
    var fraction: Double? = nil
    var tint: Color = Palette.accent

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint).imageScale(.medium)
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                if let fraction {
                    KestrelProgress(value: fraction, tint: fraction.isNaN ? tint : fractionColor(fraction))
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small line+area chart of recent values (network throughput).
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Palette.teal

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle().fill(.quaternary).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = max(values.max() ?? 1, 1)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: size.height * (1 - CGFloat(min(1, v / maxV))))
        }
    }
}

/// The network tile: current Wi-Fi, live throughput and a throughput sparkline.
struct NetworkTile: View {
    let ssid: String?
    let downBps: Double
    let upBps: Double
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi").foregroundStyle(Palette.teal).imageScale(.medium)
                    Text(L("Network")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let ssid { Text(ssid).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                }
                Text("↓ \(rate(downBps))").font(.title3.weight(.semibold)).monospacedDigit()
                Sparkline(values: history).frame(height: 26)
                Text("↑ \(rate(upBps))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func rate(_ bps: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }
}

/// A labelled horizontal bar (used in Space / breakdowns).
struct LabeledBar: View {
    let label: String
    let value: String
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.subheadline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(tint).frame(width: max(2, geo.size.width * min(1, fraction)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

/// A "My Tools" card: scan a fixed target with a Core finder, then move the result to
/// the vault. Runs off the main thread; everything it removes is undoable. Its state
/// lives in a `ToolRunState` owned by `ToolsController`, so a scan keeps running (and its
/// result stays visible) when you switch modules and come back.
struct PlanToolCard: View {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Palette.accent
    @ObservedObject var state: ToolRunState
    let scan: @Sendable () -> CleanupPlan

    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(tint).imageScale(.medium)
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if state.scanning { ScanRadar(tint: tint, size: 18) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)

                if let message = state.message {
                    Text(message).font(.caption).foregroundStyle(Palette.good)
                } else if state.scanning {
                    Text(L("Scanning…")).font(.caption).foregroundStyle(.secondary)
                } else if let plan = state.plan {
                    Text(plan.items.isEmpty ? "Nothing to clean ✓" : "\(bytesString(plan.totalBytes)) · \(plan.count) items")
                        .font(.caption.weight(.medium)).foregroundStyle(plan.items.isEmpty ? .secondary : .primary)
                }

                HStack(spacing: 8) {
                    Button { model.tools.runTool(id, scan: scan) } label: {
                        Text(state.plan == nil ? "Scan" : "Rescan")
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small))
                    .disabled(state.scanning || state.applying)

                    if let plan = state.plan, !plan.items.isEmpty {
                        Button { model.tools.applyTool(id) } label: {
                            if state.applying { KestrelSpinner(tint: .white, size: 14) } else { Text(L("Clean")) }
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(state.applying)
                    }
                }
            }
        }
    }
}

/// A thin capsule bar (energy rows, compact meters).
struct MiniBar: View {
    let fraction: Double
    var tint: Color = Palette.orange
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// An animated radar sweep shown while a scan runs, so the user sees live activity
/// (a rotating accent arc + an expanding pulse). Honours Reduce Motion.
struct ScanRadar: View {
    var tint: Color = Palette.accent
    var size: CGFloat = 34
    @State private var spin = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 2)
            Circle()
                .stroke(tint.opacity(pulse ? 0 : 0.45), lineWidth: 2)
                .scaleEffect(pulse ? 1.35 : 0.72)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0), tint], center: .center),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                )
                .rotationEffect(.degrees(spin ? 360 : 0))
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// A live scanning banner: animated radar, a title, a live status line and — when a
/// finite total is known — a determinate progress bar. Counts are honest; they come
/// straight from the scanner's own progress callbacks.
struct ScanningBanner: View {
    let title: String
    var detail: String = ""
    var progress: Double? = nil
    var tint: Color = Palette.accent

    var body: some View {
        Card {
            HStack(spacing: 13) {
                ScanRadar(tint: tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L(title)).font(.subheadline.weight(.semibold))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .lineLimit(1).truncationMode(.middle)
                            .animation(nil, value: detail)
                    }
                    if let progress {
                        KestrelProgress(value: progress, tint: tint)
                    }
                }
            }
        }
    }
}

/// Shown when the app lacks Full Disk Access — several honest features (emptying the
/// Trash, scanning Mail, some caches) silently return nothing without it. Explains why
/// and links straight to the right Settings pane.
struct FullDiskAccessBanner: View {
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(Palette.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Grant Full Disk Access")).font(.subheadline.weight(.semibold))
                    Text(L("Without it, macOS hides the Trash, Mail and some caches — so tools like “Empty Trash” find nothing. Turn Kestrel on in Settings, then relaunch."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let url = URL(string: FullDiskAccess.settingsURL) { NSWorkspace.shared.open(url) }
                    } label: {
                        Label(L("Open Full Disk Access settings"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small))
                    .padding(.top, 2)
                }
                Spacer()
            }
        }
    }
}

/// A friendly empty / all-clear state: icon, headline, optional caption.
struct EmptyState: View {
    let icon: String
    let title: String
    var caption: String = ""
    var tint: Color = Palette.good

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 30, weight: .regular)).foregroundStyle(tint)
            Text(L(title)).font(.subheadline.weight(.semibold))
            if !caption.isEmpty {
                Text(L(caption)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

/// A wrapping (flow) layout: lays children left-to-right, wrapping to a new line when a
/// row is full. Powers the custom chip selector so it adapts to any width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing); x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Kestrel's own select control — a row of selectable pills instead of a stock dropdown.
/// The active chip fills with the accent gradient; the rest are quiet. Wraps to fit.
struct KestrelSelect<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    var icon: ((T) -> String)? = nil
    var tint: Color = Palette.accent

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                chip(item, selected: item == selection)
            }
        }
    }

    private func chip(_ item: T, selected: Bool) -> some View {
        Button { selection = item } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon(item)).imageScale(.small) }
                Text(label(item)).font(.callout.weight(.medium))
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Color.secondary))
            .background(
                selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)),
                in: Capsule(style: .continuous)
            )
            .overlay(Capsule().strokeBorder(selected ? Color.clear : .white.opacity(0.08)))
            .shadow(color: selected ? tint.opacity(0.35) : .clear, radius: 5, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selected)
    }
}

/// A subtle section heading.
struct SectionTitle: View {
    let text: String
    var icon: String? = nil

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
            Text(L(text)).font(.headline)
            Spacer()
        }
    }
}

// MARK: - Custom controls (no stock AppKit chrome)

/// Kestrel's determinate progress bar — a soft track with a glowing gradient fill.
/// Replaces the stock `ProgressView(value:)` everywhere so meters feel like one family.
struct KestrelProgress: View {
    let value: Double
    var tint: Color = Palette.accent
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .shadow(color: tint.opacity(0.45), radius: 3)
                    .animation(.easeOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}

/// Kestrel's indeterminate spinner — a rotating accent arc. Replaces the stock
/// `ProgressView()` circular spinner inside buttons and inline "loading" states.
struct KestrelSpinner: View {
    var tint: Color = Palette.accent
    var size: CGFloat = 16
    var lineWidth: CGFloat = 2.2
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(AngularGradient(colors: [tint.opacity(0), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}

/// Kestrel's switch — a spring-animated capsule with a floating knob. Used for genuine
/// on/off settings instead of the stock `Toggle`.
struct KestrelToggle: View {
    @Binding var isOn: Bool
    var tint: Color = Palette.accent

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.14)))
                    .frame(width: 42, height: 25)
                    .shadow(color: isOn ? tint.opacity(0.4) : .clear, radius: 5)
                Circle().fill(.white).frame(width: 19, height: 19).padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isOn)
    }
}

/// A one-pixel graphite rule — Kestrel's own divider (the stock `Divider` reads too
/// heavy against material cards).
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
    }
}

/// The dashboard's flagship health gauge: an ambient glow disc, a graphite track and a
/// conic value arc that sweeps to the score, plus a soft accent halo.
struct HeroGauge: View {
    let score: Int
    var size: CGFloat = 176

    private var frac: CGFloat { max(0.001, CGFloat(score) / 100) }
    private var color: Color { healthColor(score) }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.16)).blur(radius: size * 0.13)
                .frame(width: size * 0.72, height: size * 0.72)
            // The stroked ring + its glow are inset so the whole gauge fits inside `size`;
            // otherwise the outer half of the stroke (and the glow) spills past the frame and
            // gets clipped by an ancestor's viewport (the section ScrollView).
            Group {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: size * 0.085)
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(
                        // Symmetric endpoints (same opacity at 0° and 360°) so the angular
                        // gradient has no visible seam, and the wrap sits at 0° — which the
                        // `-90°` rotation moves to the ring's start cap at the top, hiding it.
                        // (Previously the seam landed at 9 o'clock and read as a broken step.)
                        AngularGradient(colors: [color.opacity(0.5), color, color.opacity(0.5)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.55), radius: size * 0.045)
                    .animation(.easeOut(duration: 0.75), value: score)
            }
            .padding(size * 0.09)
            VStack(spacing: size * 0.01) {
                Text("\(score)").font(.system(size: size * 0.3, weight: .bold, design: .rounded)).monospacedDigit()
                Text(L("HEALTH")).font(.system(size: size * 0.072, weight: .bold)).kerning(1.6).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A request to show the app's custom confirm modal. Held on `AppModel` and rendered as
/// an overlay by any surface, so destructive actions never fall back to a stock alert.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    var icon: String = "questionmark.circle"
    var tint: Color = Palette.accent
    var title: String
    var message: String
    var confirmLabel: String = "Confirm"
    var destructive: Bool = false
    var onConfirm: () -> Void
}

/// Kestrel's own confirmation dialog — a dimmed backdrop and a floating material card,
/// fully in the Precision language (no stock `confirmationDialog`/`alert`).
struct ConfirmModal: View {
    let request: ConfirmRequest
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(spacing: 15) {
                Image(systemName: request.icon)
                    .font(.system(size: 27, weight: .semibold)).foregroundStyle(request.tint)
                    .frame(width: 60, height: 60)
                    .background(request.tint.opacity(0.14), in: Circle())
                    .overlay(Circle().strokeBorder(request.tint.opacity(0.25)))
                Text(request.title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                Text(request.message).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Cancel", action: onDismiss).buttonStyle(.kestrel(.subtle))
                    Button(request.confirmLabel) { request.onConfirm(); onDismiss() }
                        .buttonStyle(.kestrel(.prominent, tint: request.destructive ? Palette.crit : request.tint))
                }
                .padding(.top, 2)
            }
            .padding(26)
            .frame(width: 344)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 34, y: 14)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}

/// Presents `AppModel.confirmRequest` as a custom overlay on any surface.
struct ConfirmHost: ViewModifier {
    @EnvironmentObject private var model: AppModel
    func body(content: Content) -> some View {
        content.overlay {
            if let request = model.confirmRequest {
                ConfirmModal(request: request) {
                    withAnimation(.easeOut(duration: 0.18)) { model.confirmRequest = nil }
                }
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.confirmRequest?.id)
    }
}

extension View {
    /// Hosts Kestrel's custom confirmation modal (driven by `AppModel.confirmRequest`).
    func confirmHost() -> some View { modifier(ConfirmHost()) }
}

/// Accept a folder dropped anywhere on a surface — a dashed accent outline highlights the
/// drop, and the folder (a dropped file resolves to its parent) is handed to `onDrop`.
struct FolderDrop: ViewModifier {
    let onDrop: (URL) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    var isDir: ObjCBool = false
                    let dir = (FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
                        ? url : url.deletingLastPathComponent()
                    DispatchQueue.main.async { onDrop(dir) }
                }
                return true
            }
    }
}

extension View {
    /// Scan a folder dropped onto this surface.
    func dropFolder(_ onDrop: @escaping (URL) -> Void) -> some View { modifier(FolderDrop(onDrop: onDrop)) }
}
