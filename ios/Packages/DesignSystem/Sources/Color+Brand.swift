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
/// features depend on intent, not appearance.
///
/// Both apps are dark only and wear Night Studio's palette
/// (docs/mac-night-studio/SPEC.md §2.2, docs/ios-night-only/PR.md): the
/// surface and text tokens read `NightPalette`.
/// - On the Mac they are Night's own colours (`Night.*`), which follow the
///   window's appearance (locked to dark) and Increase Contrast.
/// - On the iPhone they are Night's dark values (`BrandNight`), whatever the
///   trait's light/dark style says, and Night's increased-contrast dark
///   values under Increase Contrast.
///
/// Text tokens versus fills: `accent`, `success` and `error` are fill and
/// stroke colours (a bubble, a selected row, a ring). Text and state glyphs
/// drawn in those hues use `accentText`, `successText` and `errorText`,
/// which hold at least 4.5:1 on every surface they sit on (AUD-21;
/// `BrandContrastTests` pins the iPhone's, `NightContrastTests` the Mac's).
public enum BrandColor {
    // MARK: Surface

    #if os(macOS)
    // The Mac reads Night Studio's palette (docs/mac-night-studio/SPEC.md
    // §2.2), so every shared view the Mac hosts takes it without per-view
    // edits. The iPhone reads the same tokens' dark values (below).
    public static let background = Night.canvasTop

    public static let surface = Night.surface

    public static let surfaceElevated = Night.surfaceRaised
    #else
    // The iPhone is dark only and reads Night's dark values (`BrandNight`):
    // the ink canvas and its lit surfaces.
    public static let background = night(BrandNight.background)

    public static let surface = night(BrandNight.surface)

    public static let surfaceElevated = night(BrandNight.surfaceElevated)
    #endif

    // MARK: Content

    #if os(macOS)
    public static let text = Night.ink

    public static let textSecondary = Night.ink2
    #else
    public static let text = night(BrandNight.text)

    public static let textSecondary = night(BrandNight.textSecondary)
    #endif

    // MARK: Accent

    /// Indigo — the primary accent for fills, strokes and tints. For text or
    /// a glyph in this hue, use `accentText`.
    public static let accent = Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255)

    /// Indigo for text and state glyphs: Night's indigo 300 on the ink
    /// canvas, so it reads at 4.5:1 or better wherever `accent` text did not
    /// (the check question was 3.95:1 light and 3.53:1 dark).
    #if os(macOS)
    public static let accentText = Night.accentText
    #else
    public static let accentText = night(BrandNight.accentText)
    #endif

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

    #if os(macOS)
    /// Opaque: Night's hairline flattened over a surface.
    public static let border = Night.border

    /// Night's red and green fills, adaptive on the Mac.
    public static let error = Night.error

    public static let errorText = Night.errorText

    public static let success = Night.success

    public static let successText = Night.successText
    #else
    /// Night's hairline flattened over a surface (opaque).
    public static let border = night(BrandNight.border)

    /// Red for fills and strokes. For text or a glyph, use `errorText`.
    public static let error = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)

    /// Red for text and state glyphs (a failed reply's reason, a wrong
    /// answer's mark): Night's red 300.
    public static let errorText = night(BrandNight.errorText)

    /// Green for fills and strokes. For text or a glyph, use `successText`.
    public static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

    /// Green for text and state glyphs ("Nailed it!", "Completed", a correct
    /// mark): Night's green on ink.
    public static let successText = night(BrandNight.successText)
    #endif

    /// The deep violet at the heart of the brand gradient (#7C3AED) — used for
    /// the Merc halo + accents that must match the mascot's skin tone exactly.
    public static let mercViolet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
}

/// The Night Studio token each `BrandColor` surface and text token reads:
/// SPEC.md §2.2's mapping. The Mac's branch spells it out with `Night.*`;
/// the iPhone's reads it from here. Platform-neutral, so the tests on the
/// macOS host check the iPhone's values (`BrandContrastTests`).
enum BrandNight {
    static let background = NightPalette.canvasTop
    static let surface = NightPalette.surface
    static let surfaceElevated = NightPalette.surfaceRaised
    static let border = NightPalette.border

    static let text = NightPalette.ink
    static let textSecondary = NightPalette.ink2

    static let accentText = NightPalette.accentText
    static let successText = NightPalette.successText
    static let errorText = NightPalette.errorText

    /// The variant the iPhone draws: Night's dark value, or its
    /// increased-contrast dark value under Increase Contrast. Never a light
    /// value, whatever the trait's light/dark style says (a subtree pinned to
    /// `.light`, a preview): the iPhone app is dark only.
    static func iPhoneVariant(increasedContrast: Bool) -> NightPalette.Variant {
        increasedContrast ? .darkHC : .dark
    }
}

/// The iPhone's fixed fill hues as raw sRGB, for computing the tints text
/// sits on (`BrandContrastTests`): `BrandColor.accent`, `.success` and
/// `.error`, which are the same in every appearance.
enum BrandPalette {
    static let accent: UInt32 = 0x6366F1
    static let success: UInt32 = 0x22C55E
    static let error: UInt32 = 0xEF4444
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

// MARK: - The iPhone's Night colours

#if canImport(UIKit)
private extension BrandColor {
    /// A Night token as the iPhone draws it (`BrandNight.iPhoneVariant`):
    /// dark, or dark with increased contrast. The trait's light/dark style
    /// is ignored.
    static func night(_ quad: NightPalette.Quad) -> Color {
        Color(
            UIColor { trait in
                let variant = BrandNight.iPhoneVariant(increasedContrast: trait.accessibilityContrast == .high)
                let shade = quad.shade(variant)
                return UIColor(
                    red: CGFloat(shade.red),
                    green: CGFloat(shade.green),
                    blue: CGFloat(shade.blue),
                    alpha: CGFloat(shade.alpha)
                )
            }
        )
    }
}
#endif
