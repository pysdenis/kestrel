import SwiftUI
import KestrelCore

// A small, consistent design language: material cards, a health ring, metric tiles and
// helpers. Everything uses semantic colors and materials so it adapts to light/dark.

func healthColor(_ score: Int) -> Color {
    switch score {
    case 80...: return .green
    case 50..<80: return .yellow
    default: return .red
    }
}

func fractionColor(_ fraction: Double) -> Color {
    switch fraction {
    case 0.9...: return .red
    case 0.75..<0.9: return .orange
    default: return .accentColor
    }
}

func bytesString(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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
                Text("\(score)").font(.system(size: size * 0.34, weight: .bold, design: .rounded))
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
    var tint: Color = .accentColor

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
