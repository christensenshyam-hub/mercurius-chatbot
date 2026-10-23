import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Mercurius brand palette — navy / indigo / purple, derived from the
/// Mercurius AI logo.
///
/// Colors are defined as semantic tokens ("accent", "background") so
/// features depend on intent, not appearance. Dark/light variants are
/// selected automatically via dynamic providers: `UIColor` on iOS,
/// `NSColor` on the Mac.
/// On macOS (logic-test host only) we fall back to light-mode values —
/// the package ships only on iOS.
///
/// Text tokens versus fills: `accent`, `success` and `error` are fill and
/// stroke colours (a bubble, a selected row, a ring). Text and state glyphs
/// drawn in those hues use `accentText`, `successText` and `errorText`,
/// which hold at least 4.5:1 on every surface they sit on, in light and dark
/// (AUD-21; `BrandContrastTests` pins it).
public enum BrandColor {
    // MARK: Surface

    public static let background = adaptive(BrandPalette.background)

    public static let surface = adaptive(BrandPalette.surface)

    public static let surfaceElevated = adaptive(BrandPalette.surfaceElevated)

    // MARK: Content

    public static let text = adaptive(BrandPalette.text)

    public static let textSecondary = adaptive(BrandPalette.textSecondary)

    // MARK: Accent

    /// Indigo — the primary accent for fills, strokes and tints. For text or
    /// a glyph in this hue, use `accentText`.
    public static let accent = Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255)

    /// Indigo for text and state glyphs: deeper in light mode, lighter in
    /// dark, so it reads at 4.5:1 or better wherever `accent` text did not
    /// (the check question was 3.95:1 light and 3.53:1 dark).
    public static let accentText = adaptive(BrandPalette.accentText)

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

    public static let border = adaptive(BrandPalette.border)

    /// Red for fills and strokes. For text or a glyph, use `errorText`.
    public static let error = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)

    /// Red for text and state glyphs (a failed reply's reason, a wrong
    /// answer's mark). The fill red was 3.6:1 as text in light mode.
    public static let errorText = adaptive(BrandPalette.errorText)

    /// Green for fills and strokes. For text or a glyph, use `successText`.
    public static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

    /// Green for text and state glyphs ("Nailed it!", "Completed", a correct
    /// mark). The fill green was 1.8-2.3:1 as text in light mode.
    public static let successText = adaptive(BrandPalette.successText)

    /// The deep violet at the heart of the brand gradient (#7C3AED) — used for
    /// the Merc halo + accents that must match the mascot's skin tone exactly.
    public static let mercViolet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
}

/// The raw sRGB values behind the adaptive tokens, light and dark: the one
/// source `BrandColor` builds from, and what the contrast tests read (a
/// SwiftUI `Color` can't be resolved to dark mode on the macOS test host).
enum BrandPalette {
    struct RGB: Equatable, Sendable {
        let r: Int
        let g: Int
        let b: Int

        init(_ hex: UInt32) {
            r = Int((hex >> 16) & 0xFF)
            g = Int((hex >> 8) & 0xFF)
            b = Int(hex & 0xFF)
        }
    }

    struct Pair: Equatable, Sendable {
        let light: RGB
        let dark: RGB

        init(light: UInt32, dark: UInt32) {
            self.light = RGB(light)
            self.dark = RGB(dark)
        }

        /// The same value in both appearances (the fixed brand hues).
        init(fixed: UInt32) {
            self.init(light: fixed, dark: fixed)
        }
    }

    static let background = Pair(light: 0xF7FAFC, dark: 0x0B0F30)
    static let surface = Pair(light: 0xFFFFFF, dark: 0x11163A)
    static let surfaceElevated = Pair(light: 0xEEF0F7, dark: 0x1A1F4A)
    static let border = Pair(light: 0xD9DEEC, dark: 0x242A5A)

    static let text = Pair(light: 0x0F142A, dark: 0xE6E9F5)
    static let textSecondary = Pair(light: 0x5D6A8A, dark: 0x9AA3C2)

    /// The fixed fill hues, for computing the tints text sits on.
    static let accent = Pair(fixed: 0x6366F1)
    static let success = Pair(fixed: 0x22C55E)
    static let error = Pair(fixed: 0xEF4444)

    /// Indigo 600 in light mode, indigo 300 in dark.
    static let accentText = Pair(light: 0x4F46E5, dark: 0xA5B4FC)
    /// Green 800 in light mode (green 700, #15803D, falls to 3.9:1 on the
    /// tinted correct-answer row over an elevated card); the fill green in
    /// dark, where it already reads at 5:1 or better.
    static let successText = Pair(light: 0x166534, dark: 0x22C55E)
    /// Red 700 in light mode, red 400 in dark.
    static let errorText = Pair(light: 0xB91C1C, dark: 0xF87171)
}

// MARK: - Brand gradient

/// The Mercurius brand gradient — blue → violet → magenta, taken from the logo.
/// Used on the lesson send button, the progress bar, and the Merc mascot's skin.
public enum BrandGradient {
    private static let stops = [
        Color(red: 0x3D / 255, green: 0x5A / 255, blue: 0xFF / 255),
        Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255),
        Color(red: 0xB5 / 255, green: 0x3B / 255, blue: 0xE8 / 255),
    ]

    /// 135° diagonal — buttons, send circle, mascot skin.
    public static let merc = LinearGradient(
        colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)

    /// 90° horizontal — progress bars.
    public static let mercHorizontal = LinearGradient(
        colors: stops, startPoint: .leading, endPoint: .trailing)
}

// MARK: - Adaptive color helper

private extension BrandColor {
    static func adaptive(_ pair: BrandPalette.Pair) -> Color {
#if canImport(UIKit)
        return Color(
            UIColor { trait in
                let c = trait.userInterfaceStyle == .dark ? pair.dark : pair.light
                return UIColor(
                    red: CGFloat(c.r) / 255,
                    green: CGFloat(c.g) / 255,
                    blue: CGFloat(c.b) / 255,
                    alpha: 1
                )
            }
        )
#elseif canImport(AppKit)
        // The Mac app follows the window's appearance (and the student's
        // Light/Dark choice, applied as the SwiftUI colour scheme).
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = isDark ? pair.dark : pair.light
                return NSColor(
                    srgbRed: CGFloat(c.r) / 255,
                    green: CGFloat(c.g) / 255,
                    blue: CGFloat(c.b) / 255,
                    alpha: 1
                )
            }
        )
#else
        return Color(
            red: Double(pair.light.r) / 255,
            green: Double(pair.light.g) / 255,
            blue: Double(pair.light.b) / 255
        )
#endif
    }
}
