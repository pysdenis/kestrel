import SwiftUI

/// A number that eases to its target value (the speed read-out climbing during a test
/// and settling on the result).
struct AnimatedNumber: View {
    let value: Double
    var format: (Double) -> String
    var font: Font = .title2.weight(.bold)
    @State private var shown: Double = 0
    @State private var token = 0

    var body: some View {
        Text(format(shown))
            .font(font)
            .monospacedDigit()
            .onAppear { shown = value }
            .onChange(of: value) { new in step(to: new) }
    }

    private func step(to target: Double) {
        token += 1
        let mine = token
        let start = shown
        let delta = target - start
        guard abs(delta) > 0.5 else { shown = target; return }
        let steps = 14
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = 1 - pow(1 - t, 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + t * 0.4) {
                if token == mine { shown = start + delta * eased }
            }
        }
    }
}

/// A premium speedometer gauge: tick marks, a 270° track, a glowing value arc that eases
/// as the measured rate climbs, and a counting read-out. `mbps` nil means idle.
struct SpeedGauge: View {
    let mbps: Double?
    let testing: Bool
    var size: CGFloat = 128

    private var fraction: Double { min(1, max(0, (mbps ?? 0) / 500)) }

    private var arcGradient: AngularGradient {
        AngularGradient(
            colors: [Palette.teal, Palette.blue, Palette.accent],
            center: .center, startAngle: .degrees(135), endAngle: .degrees(135 + 270)
        )
    }

    var body: some View {
        ZStack {
            ticks
            Circle().trim(from: 0, to: 0.75)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle().trim(from: 0, to: 0.75 * fraction)
                .stroke(arcGradient, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: Palette.teal.opacity(testing ? 0.55 : 0), radius: testing ? size * 0.06 : 0)
                .animation(.easeOut(duration: 0.5), value: fraction)

            center
        }
        .frame(width: size, height: size)
    }

    private var ticks: some View {
        ForEach(0..<9, id: \.self) { i in
            Capsule()
                .fill(.quaternary)
                .frame(width: max(1.2, size * 0.014), height: size * 0.05)
                .offset(y: -size * 0.43)
                .rotationEffect(.degrees(-135 + Double(i) / 8 * 270))
        }
        .opacity(0.7)
    }

    @ViewBuilder private var center: some View {
        if mbps == nil {
            VStack(spacing: 2) {
                Image(systemName: "speedometer").font(.system(size: size * 0.24)).foregroundStyle(Palette.teal)
                Text("tap test").font(.system(size: size * 0.085, weight: .medium)).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 0) {
                AnimatedNumber(value: mbps ?? 0, format: { String(format: "%.0f", $0) },
                               font: .system(size: size * 0.27, weight: .bold, design: .rounded))
                Text("Mbps").font(.system(size: size * 0.1, weight: .semibold)).foregroundStyle(.secondary).kerning(0.5)
            }
        }
    }
}
