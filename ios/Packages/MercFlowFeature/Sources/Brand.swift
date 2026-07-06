import SwiftUI

/// Design tokens for the Merc lesson flow — from `MERC_HANDOFF.md` Part B §0.
///
/// Deliberately self-contained (NOT the app's `DesignSystem`) so this module
/// stays isolated and the handoff's `Brand` / `MercState` / `Merc` names don't
/// collide with the existing design system.
enum Brand {
    // The Mercurius gradient — skin, send button, progress, CTAs
    static let gradient = LinearGradient(
        colors: [Color(hex: 0x3D5AFF), Color(hex: 0x7C3AED), Color(hex: 0xB53BE8)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let blue    = Color(hex: 0x3D5AFF)
    static let violet  = Color(hex: 0x7C3AED)
    static let magenta = Color(hex: 0xB53BE8)
    static let accent  = Color(hex: 0x6C5CE7)   // light-mode indigo
    static let accentDark = Color(hex: 0xA99BFF)
    static let ink     = Color(hex: 0x241B5E)   // mascot eyes/mouth
    static let gold    = LinearGradient(colors: [Color(hex: 0xE9C768), Color(hex: 0xCAA23A)],
                                        startPoint: .leading, endPoint: .trailing)

    // Surfaces (light)
    static let bg      = Color(hex: 0xF3F4FF)
    static let card    = Color.white
    static let text    = Color(hex: 0x1C1B2E)
    static let subtext = Color(hex: 0x7D7A93)
    static let calloutBG = Color(hex: 0x6C5CE7).opacity(0.09)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8)  & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: alpha)
    }
}
