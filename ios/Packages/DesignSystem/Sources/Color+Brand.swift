import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Mercurius brand palette — navy / indigo / purple, derived from the
/// Mercurius AI logo.
///
/// Colors are defined as semantic tokens ("accent", "background") so
/// features depend on intent, not appearance. On iOS, dark/light
/// variants are selected automatically via `UIColor` dynamic providers.
/// On macOS (logic-test host only) we fall back to light-mode values —
/// the package ships only on iOS.
public enum BrandColor {
    // MARK: Surface

    public static let background = adaptive(
        light: Components(r: 0xF7, g: 0xFA, b: 0xFC),
        dark: Components(r: 0x0B, g: 0x0F, b: 0x30)
    )

    public static let surface = adaptive(
        light: Components(r: 0xFF, g: 0xFF, b: 0xFF),
        dark: Components(r: 0x11, g: 0x16, b: 0x3A)
    )

    public static let surfaceElevated = adaptive(
        light: Components(r: 0xEE, g: 0xF0, b: 0xF7),
        dark: Components(r: 0x1A, g: 0x1F, b: 0x4A)
    )

    // MARK: Content

    public static let text = adaptive(
        light: Components(r: 0x0F, g: 0x14, b: 0x2A),
        dark: Components(r: 0xE6, g: 0xE9, b: 0xF5)
    )

    public static let textSecondary = adaptive(
        light: Components(r: 0x5D, g: 0x6A, b: 0x8A),
        dark: Components(r: 0x9A, g: 0xA3, b: 0xC2)
    )

    // MARK: Accent

    /// Indigo — the primary accent used for interactive elements.
    public static let accent = Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255)

    /// Violet — lighter accent for gradients / highlights.
    public static let accentLight = Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255)

    /// Deeper indigo — pressed / active states.
    public static let accentDark = Color(red: 0x4C / 255, green: 0x51 / 255, blue: 0xBF / 255)

    // MARK: Message bubbles

    public static let userBubbleTop = accent
    public static let userBubbleBottom = accentLight
    public static let userBubble = accent
    public static let userBubbleText = Color.white

    public static let assistantBubble = surfaceElevated
    public static let assistantBubbleText = text

    // MARK: Semantic

    public static let border = adaptive(
        light: Components(r: 0xD9, g: 0xDE, b: 0xEC),
        dark: Components(r: 0x24, g: 0x2A, b: 0x5A)
    )

    public static let error = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
    public static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
}

// MARK: - Adaptive color helper

private struct Components {
    let r: Int
    let g: Int
    let b: Int
}

private extension BrandColor {
    static func adaptive(light: Components, dark: Components) -> Color {
#if canImport(UIKit)
        return Color(
            UIColor { trait in
                let c = trait.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat(c.r) / 255,
                    green: CGFloat(c.g) / 255,
                    blue: CGFloat(c.b) / 255,
                    alpha: 1
                )
            }
        )
#else
        return Color(
            red: Double(light.r) / 255,
            green: Double(light.g) / 255,
            blue: Double(light.b) / 255
        )
#endif
    }
}
