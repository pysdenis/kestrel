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
                Text("HEALTH").font(.system(size: size * 0.11, weight: .semibold)).foregroundStyle(.secondary).kerning(1)
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

    var body: some View {
        Card {
            VStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(iconTint).imageScale(.small)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
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

/// A "My Tools" card: scan a fixed target with a Core finder, then move the result to
/// the vault. Runs off the main thread; everything it removes is undoable.
struct PlanToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = Palette.accent
    let scan: () -> CleanupPlan

    @EnvironmentObject private var model: AppModel
    @State private var plan: CleanupPlan?
    @State private var scanning = false
    @State private var applying = false
    @State private var message: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(tint).imageScale(.medium)
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)

                if let message {
                    Text(message).font(.caption).foregroundStyle(Palette.good)
                } else if let plan {
                    Text(plan.items.isEmpty ? "Nothing to clean ✓" : "\(bytesString(plan.totalBytes)) · \(plan.count) items")
                        .font(.caption.weight(.medium)).foregroundStyle(plan.items.isEmpty ? .secondary : .primary)
                }

                HStack(spacing: 8) {
                    Button(action: runScan) {
                        if scanning { ProgressView().controlSize(.small) } else { Text(plan == nil ? "Scan" : "Rescan") }
                    }
                    .buttonStyle(.kestrel(.secondary, size: .small))
                    .disabled(scanning || applying)

                    if let plan, !plan.items.isEmpty {
                        Button(action: apply) {
                            if applying { ProgressView().controlSize(.small) } else { Text("Clean") }
                        }
                        .buttonStyle(.kestrel(.prominent, size: .small))
                        .disabled(applying)
                    }
                }
            }
        }
    }

    private func runScan() {
        scanning = true; message = nil
        let scan = self.scan
        Task.detached {
            let result = scan()
            await MainActor.run { self.plan = result; self.scanning = false }
        }
    }

    private func apply() {
        guard let plan else { return }
        applying = true
        let vaultURL = model.paths.vault
        let auditURL = model.paths.auditLog
        Task.detached {
            let result = try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run {
                self.message = result.map { "Cleaned \($0.movedCount), \(bytesString($0.movedBytes)) → vault" } ?? "Failed"
                self.plan = nil
                self.applying = false
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
