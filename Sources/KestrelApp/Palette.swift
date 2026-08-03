import SwiftUI
import AppKit

private extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// An appearance-adaptive color from two hex values (light / dark).
    init(lightHex: Int, darkHex: Int) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        }))
    }
}

/// The "Precision" palette (see the redesign reference): a calm graphite ground with a
/// single teal signature accent and a cool indigo for secondary data. Semantic tones
/// (good/warn/crit) stay separate from the accent, and the rust "kestrel" tone is used
/// only as an identity garnish.
enum Palette {
    static let accent  = Color(lightHex: 0x0EB3A3, darkHex: 0x25CDBD)   // signature teal
    static let accent2 = Color(lightHex: 0x4F6EF5, darkHex: 0x6C8BFF)   // cool indigo (secondary data)
    static let kestrel = Color(lightHex: 0xC05F2C, darkHex: 0xE6935A)
    static let good    = Color(lightHex: 0x10B981, darkHex: 0x37D39A)
    static let warn    = Color(lightHex: 0xE0912F, darkHex: 0xF2B34A)
    static let crit    = Color(lightHex: 0xE5484D, darkHex: 0xFB6D6D)
    static let teal     = accent
    static let violet  = accent2
    static let blue    = accent2
    static let orange  = Color(lightHex: 0xE0912F, darkHex: 0xF2B34A)
    static let pink    = Color(lightHex: 0xD6568A, darkHex: 0xF07BAB)
}
