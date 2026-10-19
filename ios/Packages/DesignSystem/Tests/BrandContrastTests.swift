import Testing
import Foundation
@testable import DesignSystem

/// WCAG 2.x contrast for the brand's text tokens (AUD-21). Computed from
/// `BrandPalette`, the raw values every adaptive token is built from, so
/// both appearances are checked on the macOS test host.
@Suite("Brand text contrast")
struct BrandContrastTests {

    enum Appearance: String, CaseIterable {
        case light, dark
    }

    /// A colour as rendered in one appearance, 0...1 per channel.
    struct Shade {
        let r: Double
        let g: Double
        let b: Double

        init(_ rgb: BrandPalette.RGB) {
            r = Double(rgb.r) / 255
            g = Double(rgb.g) / 255
            b = Double(rgb.b) / 255
        }

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// `self` at `alpha` over `base`, composited in sRGB the way UIKit
        /// draws a translucent fill.
        func over(_ base: Shade, alpha: Double) -> Shade {
            Shade(r: r * alpha + base.r * (1 - alpha),
                  g: g * alpha + base.g * (1 - alpha),
                  b: b * alpha + base.b * (1 - alpha))
        }

        var luminance: Double {
            func linear(_ c: Double) -> Double {
                c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
    }

    static func shade(_ pair: BrandPalette.Pair, _ appearance: Appearance) -> Shade {
        Shade(appearance == .light ? pair.light : pair.dark)
    }

    static func contrast(_ a: Shade, _ b: Shade) -> Double {
        let hi = max(a.luminance, b.luminance)
        let lo = min(a.luminance, b.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// WCAG AA for normal-size text.
    static let minimum = 4.5

    /// Every token meant for text.
    static let textTokens: [(String, BrandPalette.Pair)] = [
        ("text", BrandPalette.text),
        ("textSecondary", BrandPalette.textSecondary),
        ("accentText", BrandPalette.accentText),
        ("successText", BrandPalette.successText),
    ]

    /// The three page and card surfaces.
    static let surfaces: [(String, BrandPalette.Pair)] = [
        ("background", BrandPalette.background),
        ("surface", BrandPalette.surface),
        ("surfaceElevated", BrandPalette.surfaceElevated),
    ]

    /// A text token over a tinted card, as it's drawn in the app.
    struct TintedUse {
        let name: String
        let text: BrandPalette.Pair
        let tint: BrandPalette.Pair
        let alpha: Double
        let base: BrandPalette.Pair
    }

    static let tintedUses: [TintedUse] = [
        // The lesson check question and the [Q] card, on the lesson bubble.
        .init(name: "check question", text: BrandPalette.accentText,
              tint: BrandPalette.accent, alpha: 0.10, base: BrandPalette.surface),
        // The KEY IDEA eyebrow, on the lesson bubble.
        .init(name: "key idea eyebrow", text: BrandPalette.accentText,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandPalette.surface),
        // The chat input hint: its arrow and its line.
        .init(name: "input hint arrow", text: BrandPalette.accentText,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandPalette.background),
        .init(name: "input hint line", text: BrandPalette.textSecondary,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandPalette.background),
        // The history row's mode chip.
        .init(name: "history mode chip", text: BrandPalette.accentText,
              tint: BrandPalette.accent, alpha: 0.12, base: BrandPalette.surface),
        // [Q] and unit-test answer rows: the correct mark on its green row,
        // on a lesson bubble (surface) or a test card (surface).
        .init(name: "correct mark, lesson [Q]", text: BrandPalette.successText,
              tint: BrandPalette.success, alpha: 0.15, base: BrandPalette.surface),
        .init(name: "correct mark, elevated card", text: BrandPalette.successText,
              tint: BrandPalette.success, alpha: 0.18, base: BrandPalette.surfaceElevated),
        // Answer text on the selected, correct and wrong rows.
        .init(name: "selected answer", text: BrandPalette.text,
              tint: BrandPalette.accent, alpha: 0.18, base: BrandPalette.surface),
        .init(name: "correct answer", text: BrandPalette.text,
              tint: BrandPalette.success, alpha: 0.18, base: BrandPalette.surface),
        .init(name: "wrong answer", text: BrandPalette.text,
              tint: BrandPalette.error, alpha: 0.15, base: BrandPalette.surface),
    ]

    @Test("Every text token reads at 4.5:1 or better on every surface, light and dark",
          arguments: Appearance.allCases)
    func textOnSurfaces(appearance: Appearance) {
        for (textName, text) in Self.textTokens {
            for (surfaceName, surface) in Self.surfaces {
                let ratio = Self.contrast(Self.shade(text, appearance), Self.shade(surface, appearance))
                #expect(ratio >= Self.minimum,
                        "\(textName) on \(surfaceName) (\(appearance)) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    @Test("Text on the tinted cards reads at 4.5:1 or better, light and dark",
          arguments: Appearance.allCases)
    func textOnTints(appearance: Appearance) {
        for use in Self.tintedUses {
            let base = Self.shade(use.base, appearance)
            let card = Self.shade(use.tint, appearance).over(base, alpha: use.alpha)
            let ratio = Self.contrast(Self.shade(use.text, appearance), card)
            #expect(ratio >= Self.minimum,
                    "\(use.name) (\(appearance)) is \(String(format: "%.2f", ratio)):1")
        }
    }

    @Test("The fill hues as text were the failures: the text tokens exist because of them")
    func fillHuesFailAsText() {
        // Documents why the split exists. If a fill hue ever passes as text
        // everywhere, the matching text token could be folded back into it.
        let accentOnTint = Self.contrast(
            Self.shade(BrandPalette.accent, .light),
            Self.shade(BrandPalette.accent, .light).over(Self.shade(BrandPalette.surface, .light), alpha: 0.10))
        #expect(accentOnTint < Self.minimum)
        let greenOnSurface = Self.contrast(Self.shade(BrandPalette.success, .light),
                                           Self.shade(BrandPalette.surface, .light))
        #expect(greenOnSurface < 3)
    }

    @Test("The audit's measurements reproduce (check question 3.95:1, 'Nailed it!' 2.28:1)")
    func reproducesAudit() {
        let check = Self.contrast(
            Self.shade(BrandPalette.accent, .light),
            Self.shade(BrandPalette.accent, .light).over(Self.shade(BrandPalette.surface, .light), alpha: 0.10))
        #expect(abs(check - 3.95) < 0.02)
        let nailedIt = Self.contrast(Self.shade(BrandPalette.success, .light),
                                     Self.shade(BrandPalette.surface, .light))
        #expect(abs(nailedIt - 2.28) < 0.02)
    }

    @Test("The palette values are the ones BrandColor was built from")
    func paletteMatchesPreviousTokens() {
        // A guard against a slip while moving the hex values into BrandPalette.
        #expect(BrandPalette.background == .init(light: 0xF7FAFC, dark: 0x0B0F30))
        #expect(BrandPalette.surface == .init(light: 0xFFFFFF, dark: 0x11163A))
        #expect(BrandPalette.surfaceElevated == .init(light: 0xEEF0F7, dark: 0x1A1F4A))
        #expect(BrandPalette.text == .init(light: 0x0F142A, dark: 0xE6E9F5))
        #expect(BrandPalette.textSecondary == .init(light: 0x5D6A8A, dark: 0x9AA3C2))
        #expect(BrandPalette.border == .init(light: 0xD9DEEC, dark: 0x242A5A))
    }
}
