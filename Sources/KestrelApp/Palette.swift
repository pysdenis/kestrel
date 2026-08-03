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

/// The exact palette from the design reference, so the native app matches it precisely
/// rather than inheriting the system accent and stock semantic colors. Semantic tones
/// (good/warn/crit) stay separate from the accent, per the design.
enum Palette {
    static let accent  = Color(lightHex: 0x2F6FED, darkHex: 0x5B93F8)
    static let kestrel = Color(lightHex: 0xC05F2C, darkHex: 0xE0894F)
    static let good    = Color(lightHex: 0x2BA36B, darkHex: 0x3CC184)
    static let warn    = Color(lightHex: 0xDD8B28, darkHex: 0xF0A53F)
    static let crit    = Color(lightHex: 0xD64637, darkHex: 0xF0685B)
    static let teal    = Color(lightHex: 0x1F9BB0, darkHex: 0x39B7CC)
    static let violet  = Color(lightHex: 0x7A5CF0, darkHex: 0x9A80FF)
    static let orange  = Color(lightHex: 0xE2842B, darkHex: 0xF0A53F)
    static let pink    = Color(lightHex: 0xD6568A, darkHex: 0xF07BAB)
    static let blue    = accent
}
