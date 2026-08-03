import SwiftUI

/// A number that eases to its target value (used for the speed read-out counting up).
struct AnimatedNumber: View {
    let value: Double
    var format: (Double) -> String
    var font: Font = .title2.weight(.bold)
    @State private var shown: Double = 0

    var body: some View {
        Text(format(shown))
            .font(font)
            .monospacedDigit()
            .onAppear { run(to: value) }
            .onChange(of: value) { run(to: $0) }
    }

    private func run(to target: Double) {
        let start = shown
        let delta = target - start
        guard abs(delta) > 0.01 else { shown = target; return }
        let steps = 26
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = 1 - pow(1 - t, 3)      // ease-out cubic
            DispatchQueue.main.asyncAfter(deadline: .now() + t * 0.7) {
                shown = start + delta * eased
            }
        }
    }
}

/// A 270° speed gauge. While testing it shows a sweeping arc; when a result arrives the
/// arc eases to the measured fraction and the number counts up.
struct SpeedGauge: View {
    let mbps: Double?
    let testing: Bool
    var size: CGFloat = 128
    @State private var spin = false
    @State private var pulse = false

    private var fraction: Double { min(1, (mbps ?? 0) / 500) }

    private var arcGradient: AngularGradient {
        AngularGradient(
            colors: [.teal, Color(red: 0.2, green: 0.6, blue: 0.95), .accentColor],
            center: .center, startAngle: .degrees(135), endAngle: .degrees(135 + 270)
        )
    }

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .rotationEffect(.degrees(135))

            if testing {
                Circle().trim(from: 0, to: 0.16)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 405 : 45))
                    .animation(.linear(duration: 0.85).repeatForever(autoreverses: false), value: spin)
            } else {
                Circle().trim(from: 0, to: 0.75 * fraction)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.7), value: fraction)
            }

            center
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
    }

    @ViewBuilder private var center: some View {
        VStack(spacing: 1) {
            if testing {
                Image(systemName: "waveform.path")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(.teal)
                    .opacity(pulse ? 1 : 0.35)
                    .scaleEffect(pulse ? 1.05 : 0.92)
                    .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
                Text("testing").font(.system(size: size * 0.09, weight: .semibold)).foregroundStyle(.secondary)
            } else if let mbps {
                AnimatedNumber(value: mbps, format: { String(format: "%.0f", $0) },
                               font: .system(size: size * 0.27, weight: .bold, design: .rounded))
                Text("Mbps").font(.system(size: size * 0.1, weight: .semibold)).foregroundStyle(.secondary).kerning(0.5)
            } else {
                Image(systemName: "speedometer").font(.system(size: size * 0.26)).foregroundStyle(.teal)
                Text("tap test").font(.system(size: size * 0.09)).foregroundStyle(.secondary)
            }
        }
    }
}
