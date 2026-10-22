import Testing
import Foundation
@testable import DesignSystem

/// WCAG 2.x contrast for the iPhone's text tokens (AUD-21), now that the
/// iPhone is dark only and wears Night Studio's palette
/// (docs/ios-night-only/PR.md). Computed from `BrandNight` and
/// `NightPalette`, the raw values the iPhone's tokens are built from, so the
/// iPhone's values are checked on the macOS test host. The iPhone draws two
/// variants: Night's dark, and Night's dark under Increase Contrast.
/// (`NightContrastTests` checks all four of the Mac's.)
@Suite("Brand text contrast on the iPhone (Night, dark only)")
struct BrandContrastTests {
    typealias Variant = NightPalette.Variant

    /// The variants the iPhone draws.
    static let iPhoneVariants: [Variant] = [.dark, .darkHC]

    /// A colour as drawn, 0...1 per channel.
    struct Shade {
        let r: Double
        let g: Double
        let b: Double

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(_ hex: UInt32) {
            self.init(r: Double((hex >> 16) & 0xFF) / 255,
                      g: Double((hex >> 8) & 0xFF) / 255,
                      b: Double(hex & 0xFF) / 255)
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

    /// A token as the iPhone draws it in `variant`. Every iPhone token is
    /// opaque (`border` is the hairline already flattened).
    static func shade(_ quad: NightPalette.Quad, _ variant: Variant) -> Shade {
        Shade(quad.shade(variant).hex)
    }

    static func contrast(_ a: Shade, _ b: Shade) -> Double {
        let hi = max(a.luminance, b.luminance)
        let lo = min(a.luminance, b.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    static func ratio(_ value: Double) -> String { String(format: "%.2f", value) }

    /// WCAG AA for normal-size text.
    static let minimum = 4.5
    /// What Night holds its inks to under Increase Contrast, on plain
    /// surfaces (SPEC.md §2.3).
    static let minimumHC = 7.0

    /// Every token meant for text.
    static let textTokens: [(String, NightPalette.Quad)] = [
        ("text", BrandNight.text),
        ("textSecondary", BrandNight.textSecondary),
        ("accentText", BrandNight.accentText),
        ("successText", BrandNight.successText),
        ("errorText", BrandNight.errorText),
    ]

    /// The three page and card surfaces: the ink canvas and its lit
    /// surfaces. The iPhone draws the canvas flat (no light pools).
    static let surfaces: [(String, NightPalette.Quad)] = [
        ("background", BrandNight.background),
        ("surface", BrandNight.surface),
        ("surfaceElevated", BrandNight.surfaceElevated),
    ]

    /// A text token over a tinted card, as the iPhone draws it: a fixed fill
    /// hue (`BrandPalette`) at `alpha` over a Night surface.
    struct TintedUse {
        let name: String
        let text: NightPalette.Quad
        let tint: UInt32
        let alpha: Double
        let base: NightPalette.Quad
    }

    static let tintedUses: [TintedUse] = [
        // The lesson check question and the [Q] card, on the lesson bubble.
        .init(name: "check question", text: BrandNight.accentText,
              tint: BrandPalette.accent, alpha: 0.10, base: BrandNight.surface),
        // The KEY IDEA eyebrow, on the lesson bubble.
        .init(name: "key idea eyebrow", text: BrandNight.accentText,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandNight.surface),
        // The chat input hint: its arrow and its line.
        .init(name: "input hint arrow", text: BrandNight.accentText,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandNight.background),
        .init(name: "input hint line", text: BrandNight.textSecondary,
              tint: BrandPalette.accent, alpha: 0.08, base: BrandNight.background),
        // The history row's mode chip.
        .init(name: "history mode chip", text: BrandNight.accentText,
              tint: BrandPalette.accent, alpha: 0.12, base: BrandNight.surface),
        // [Q] and unit-test answer rows: the correct mark on its green row,
        // on a lesson bubble (surface) or a test card (surface).
        .init(name: "correct mark, lesson [Q]", text: BrandNight.successText,
              tint: BrandPalette.success, alpha: 0.15, base: BrandNight.surface),
        .init(name: "correct mark, elevated card", text: BrandNight.successText,
              tint: BrandPalette.success, alpha: 0.18, base: BrandNight.surfaceElevated),
        // A wrong pick's mark on its red row.
        .init(name: "wrong mark", text: BrandNight.errorText,
              tint: BrandPalette.error, alpha: 0.15, base: BrandNight.surface),
        .init(name: "wrong mark, elevated card", text: BrandNight.errorText,
              tint: BrandPalette.error, alpha: 0.15, base: BrandNight.surfaceElevated),
        // Answer text on the selected, correct and wrong rows.
        .init(name: "selected answer", text: BrandNight.text,
              tint: BrandPalette.accent, alpha: 0.18, base: BrandNight.surface),
        .init(name: "correct answer", text: BrandNight.text,
              tint: BrandPalette.success, alpha: 0.18, base: BrandNight.surface),
        .init(name: "wrong answer", text: BrandNight.text,
              tint: BrandPalette.error, alpha: 0.15, base: BrandNight.surface),
    ]

    // MARK: Dark only

    @Test("The iPhone draws Night's dark values only, whatever its trait's light/dark style")
    func darkOnly() {
        #expect(BrandNight.iPhoneVariant(increasedContrast: false) == .dark)
        #expect(BrandNight.iPhoneVariant(increasedContrast: true) == .darkHC)
        for increased in [false, true] {
            #expect(BrandNight.iPhoneVariant(increasedContrast: increased).isDark)
        }
    }

    @Test("Each iPhone token is the Night token SPEC.md §2.2 maps it to")
    func mapping() {
        #expect(BrandNight.background == NightPalette.canvasTop)
        #expect(BrandNight.surface == NightPalette.surface)
        #expect(BrandNight.surfaceElevated == NightPalette.surfaceRaised)
        #expect(BrandNight.border == NightPalette.border)
        #expect(BrandNight.text == NightPalette.ink)
        #expect(BrandNight.textSecondary == NightPalette.ink2)
        #expect(BrandNight.accentText == NightPalette.accentText)
        #expect(BrandNight.successText == NightPalette.successText)
        #expect(BrandNight.errorText == NightPalette.errorText)
    }

    @Test("The iPhone's values, as drawn: Night's dark column, and its Increase Contrast column")
    func drawnValues() {
        let expected: [(String, NightPalette.Quad, UInt32, UInt32)] = [
            ("background", BrandNight.background, 0x0B0E2E, 0x05071A),
            ("surface", BrandNight.surface, 0x121641, 0x0E1238),
            ("surfaceElevated", BrandNight.surfaceElevated, 0x1A1F52, 0x161B4A),
            ("border", BrandNight.border, 0x2E3258, 0x6E7188),
            ("text", BrandNight.text, 0xF1F2FF, 0xFFFFFF),
            ("textSecondary", BrandNight.textSecondary, 0xB7BDE2, 0xDDE0F7),
            ("accentText", BrandNight.accentText, 0xA5B4FC, 0xC7D2FE),
            ("successText", BrandNight.successText, 0x6EE7A8, 0xA7F3D0),
            ("errorText", BrandNight.errorText, 0xFCA5A5, 0xFECACA),
        ]
        for (name, quad, dark, darkHC) in expected {
            let drawn = quad.shade(BrandNight.iPhoneVariant(increasedContrast: false))
            let drawnHC = quad.shade(BrandNight.iPhoneVariant(increasedContrast: true))
            #expect(drawn.hex == dark && drawn.alpha == 1, "\(name)")
            #expect(drawnHC.hex == darkHC && drawnHC.alpha == 1, "\(name), Increase Contrast")
        }
    }

    @Test("The fixed fill hues match BrandColor's")
    func fillHues() {
        #expect(BrandPalette.accent == 0x6366F1)
        #expect(BrandPalette.success == 0x22C55E)
        #expect(BrandPalette.error == 0xEF4444)
    }

    // MARK: Contrast

    @Test("Every text token reads at 4.5:1 (7:1 under Increase Contrast) on every iPhone surface",
          arguments: [Variant.dark, .darkHC])
    func textOnSurfaces(variant: Variant) {
        let floor = variant.isIncreasedContrast ? Self.minimumHC : Self.minimum
        for (textName, text) in Self.textTokens {
            for (surfaceName, surface) in Self.surfaces {
                let ratio = Self.contrast(Self.shade(text, variant), Self.shade(surface, variant))
                #expect(ratio >= floor, "\(textName) on \(surfaceName) (\(variant)) is \(Self.ratio(ratio)):1")
            }
        }
    }

    @Test("Text on the tinted cards reads at 4.5:1 or better", arguments: [Variant.dark, .darkHC])
    func textOnTints(variant: Variant) {
        for use in Self.tintedUses {
            let base = Self.shade(use.base, variant)
            let card = Shade(use.tint).over(base, alpha: use.alpha)
            let ratio = Self.contrast(Self.shade(use.text, variant), card)
            #expect(ratio >= Self.minimum, "\(use.name) (\(variant)) is \(Self.ratio(ratio)):1")
        }
    }

    @Test("The lowest text ratios on plain surfaces: 7.74 dark, 10.92 under Increase Contrast")
    func floors() {
        func lowest(_ variant: Variant) -> Double {
            var low = Double.infinity
            for (_, text) in Self.textTokens {
                for (_, surface) in Self.surfaces {
                    low = min(low, Self.contrast(Self.shade(text, variant), Self.shade(surface, variant)))
                }
            }
            return low
        }
        #expect(abs(lowest(.dark) - 7.74) < 0.01, "\(Self.ratio(lowest(.dark)))")
        #expect(abs(lowest(.darkHC) - 10.92) < 0.01, "\(Self.ratio(lowest(.darkHC)))")
    }

    /// The tab bar's highlight behind the selected tab, as iOS 26.4 draws it
    /// on an iPhone 16 Pro Max over the path and over the chat (measured
    /// from the simulator's screenshots; the system draws it, so it isn't a
    /// token).
    static let tabHighlights: [(String, UInt32)] = [
        ("over the path", 0x393F6A),
        ("over the chat", 0x343650),
    ]

    @Test("The tab bar's selected label: the interface tint (accentText) reads at 4.5:1 on its highlight; the fill indigo didn't",
          arguments: [Variant.dark, .darkHC])
    func selectedTabLabel(variant: Variant) {
        for (name, highlight) in Self.tabHighlights {
            let tint = Self.contrast(Self.shade(BrandNight.accentText, variant), Shade(highlight))
            #expect(tint >= Self.minimum, "accentText \(name) (\(variant)) is \(Self.ratio(tint)):1")
            // The tint before the fix: the system drew the selected label
            // a little lighter than the fill (#7F85FF), 3.2:1 and 3.6:1.
            let fill = Self.contrast(Shade(BrandPalette.accent), Shade(highlight))
            #expect(fill < Self.minimum, "accent \(name) is \(Self.ratio(fill)):1")
        }
    }

    @Test("The accent fill as text fails on the ink canvas: why accentText exists")
    func accentFillFailsAsText() {
        // If the fill hue ever passes as text everywhere, accentText could be
        // folded back into it.
        for (name, surface) in Self.surfaces {
            let ratio = Self.contrast(Shade(BrandPalette.accent), Self.shade(surface, .dark))
            #expect(ratio < Self.minimum, "accent on \(name) is \(Self.ratio(ratio)):1")
        }
    }

    @Test("The audit's measurements reproduce on the retired light palette (check question 3.95:1, 'Nailed it!' 2.28:1)")
    func reproducesAudit() {
        // AUD-21 measured the pre-Night iPhone in light mode: its surface
        // was white. Kept as the record of why the text tokens split off.
        let lightSurface = Shade(0xFFFFFF)
        let check = Self.contrast(Shade(BrandPalette.accent),
                                  Shade(BrandPalette.accent).over(lightSurface, alpha: 0.10))
        #expect(abs(check - 3.95) < 0.02)
        let nailedIt = Self.contrast(Shade(BrandPalette.success), lightSurface)
        #expect(abs(nailedIt - 2.28) < 0.02)
    }
}
