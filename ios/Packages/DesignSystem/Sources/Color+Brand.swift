import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Mercurius brand palette.
///
/// Colors are defined as semantic tokens rather than raw hex values so
/// features depend on intent ("accent") rather than appearance ("#C9922A").
/// On iOS, dark/light variants are selected automatically via
/// `UIColor` dynamic providers. On macOS (logic-test host only) we fall
/// back to the light-mode color — the package isn't used on macOS.
public enum BrandColor {
    // MARK: Surface

    public static let background = adaptive(
        light: Components(r: 0xF5, g: 0xF8, b: 0xF6),
        dark: Components(r: 0x08, g: 0x0F, b: 0x0B)
    )

    public static let surface = adaptive(
        light: Components(r: 0xFF, g: 0xFF, b: 0xFF),
        dark: Components(r: 0x10, g: 0x1E, b: 0x16)
    )

    public static let surfaceElevated = adaptive(
        light: Components(r: 0xED, g: 0xF4, b: 0xEF),
        dark: Components(r: 0x18, g: 0x2C, b: 0x22)
    )

    // MARK: Content

    public static let text = adaptive(
        light: Components(r: 0x1A, g: 0x17, b: 0x14),
        dark: Components(r: 0xE8, g: 0xED, b: 0xE9)
    )

    public static let textSecondary = adaptive(
        light: Components(r: 0x6B, g: 0x7A, b: 0x6E),
        dark: Components(r: 0x8A, g: 0x9E, b: 0x90)
    )

    // MARK: Accent

    public static let accent = Color(red: 0xC9 / 255, green: 0x92 / 255, blue: 0x2A / 255)
    public static let accentLight = Color(red: 0xE8 / 255, green: 0xB8 / 255, blue: 0x4B / 255)
    public static let accentDark = Color(red: 0x9A / 255, green: 0x6D / 255, blue: 0x18 / 255)

    // MARK: Message bubbles

    public static let userBubble = accent
    public static let userBubbleText = Color.white

    public static let assistantBubble = surfaceElevated
    public static let assistantBubbleText = text

    // MARK: Semantic

    public static let border = adaptive(
        light: Components(r: 0xD4, g: 0xDD, b: 0xD7),
        dark: Components(r: 0x1C, g: 0x38, b: 0x28)
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
    /// Returns a `Color` that adapts to the system appearance on iOS,
    /// or a static light-mode color on other platforms.
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
