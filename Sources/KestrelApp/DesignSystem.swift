import SwiftUI
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

/// A padded, rounded material container.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06)))
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
                Text("HEALTH").font(.system(size: size * 0.11, weight: .semibold)).foregroundStyle(.secondary).kerning(1)
            }
        }
        .frame(width: size, height: size)
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
                    ProgressView(value: min(1, max(0, fraction))).tint(fraction.isNaN ? tint : fractionColor(fraction))
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
                    Text("Network").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
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
            Text(text).font(.headline)
            Spacer()
        }
    }
}
