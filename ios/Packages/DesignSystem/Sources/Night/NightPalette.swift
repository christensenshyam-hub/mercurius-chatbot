import Foundation

/// Night Studio's raw colour values: the one source the Mac's `Night`
/// colour tokens and the iPhone's `BrandColor` tokens are built from, and
/// what `NightContrastTests` and `BrandContrastTests` read (a SwiftUI
/// `Color` can't be resolved per appearance on the test host).
///
/// Every token has four values: light, dark, and the same two under Increase
/// Contrast ("HC"). The values are SPEC.md §2.1's;
/// `docs/mac-night-studio/night_contrast.py` is the reference calculation,
/// and the tests hold the same pairs to the same minimums. Change a value
/// in all three places, or none.
///
/// Both platforms compile it (Foundation only). The Mac draws all four
/// variants; the iPhone is dark only and draws `dark`, or `darkHC` under
/// Increase Contrast (`BrandNight`; docs/ios-night-only/PR.md). Lesson 1.1's
/// interactive reads the same dark values through `NightSkyCard`.
enum NightPalette {
    /// One sRGB colour, with an alpha for the translucent tokens (hairlines,
    /// the field stroke, the hero's lamp).
    struct Shade: Equatable, Sendable {
        let hex: UInt32
        let alpha: Double

        init(_ hex: UInt32, alpha: Double = 1) {
            self.hex = hex
            self.alpha = alpha
        }

        var red: Double { Double((hex >> 16) & 0xFF) / 255 }
        var green: Double { Double((hex >> 8) & 0xFF) / 255 }
        var blue: Double { Double(hex & 0xFF) / 255 }
    }

    /// The four appearances a token is drawn in.
    enum Variant: String, CaseIterable, Sendable {
        case light, dark, lightHC, darkHC

        init(dark: Bool, increasedContrast: Bool) {
            switch (dark, increasedContrast) {
            case (false, false): self = .light
            case (true, false): self = .dark
            case (false, true): self = .lightHC
            case (true, true): self = .darkHC
            }
        }

        var isDark: Bool { self == .dark || self == .darkHC }
        var isIncreasedContrast: Bool { self == .lightHC || self == .darkHC }
    }

    /// A token: its value in each of the four appearances.
    struct Quad: Equatable, Sendable {
        let light: Shade
        let dark: Shade
        let lightHC: Shade
        let darkHC: Shade

        init(light: Shade, dark: Shade, lightHC: Shade, darkHC: Shade) {
            self.light = light
            self.dark = dark
            self.lightHC = lightHC
            self.darkHC = darkHC
        }

        init(light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32) {
            self.init(light: Shade(light), dark: Shade(dark), lightHC: Shade(lightHC), darkHC: Shade(darkHC))
        }

        /// The same hue everywhere (the fixed fills).
        init(fixed: UInt32) {
            self.init(light: fixed, dark: fixed, lightHC: fixed, darkHC: fixed)
        }

        func shade(_ variant: Variant) -> Shade {
            switch variant {
            case .light: return light
            case .dark: return dark
            case .lightHC: return lightHC
            case .darkHC: return darkHC
            }
        }
    }

    // MARK: Surfaces

    /// Every detail screen's background, top to bottom. Flat under HC.
    static let canvasTop = Quad(light: 0xF6F5FC, dark: 0x0B0E2E, lightHC: 0xFAFAFE, darkHC: 0x05071A)
    static let canvasBottom = Quad(light: 0xECEBF8, dark: 0x05071A, lightHC: 0xFAFAFE, darkHC: 0x05071A)
    /// Lit surfaces: cards, the check, the complete card.
    static let surface = Quad(light: 0xFFFFFF, dark: 0x121641, lightHC: 0xFFFFFF, darkHC: 0x0E1238)
    /// Answer rows, inner wells, hover on lit rows.
    static let surfaceRaised = Quad(light: 0xF2F1FB, dark: 0x1A1F52, lightHC: 0xF1F0FA, darkHC: 0x161B4A)
    /// The sidebar's opaque fill where it isn't system glass (§2.8).
    static let sidebar = Quad(light: 0xEEEDF7, dark: 0x0A0D29, lightHC: 0xF1F0FA, darkHC: 0x05071A)
    /// Strokes, separators, unlit segments.
    static let hairline = Quad(light: Shade(0x1B1F4B, alpha: 0.10), dark: Shade(0xFFFFFF, alpha: 0.12),
                               lightHC: Shade(0x1B1F4B, alpha: 0.55), darkHC: Shade(0xFFFFFF, alpha: 0.40))
    /// `hairline` flattened over `surface`, for `BrandColor.border`.
    static let border = Quad(light: 0xE8E9ED, dark: 0x2E3258, lightHC: 0x82849C, darkHC: 0x6E7188)

    // MARK: Text

    static let ink = Quad(light: 0x0E1230, dark: 0xF1F2FF, lightHC: 0x05071A, darkHC: 0xFFFFFF)
    static let ink2 = Quad(light: 0x434A6E, dark: 0xB7BDE2, lightHC: 0x2A3052, darkHC: 0xDDE0F7)
    /// Captions and metadata. Moved from the concept's #5A6286 / #8E96C4 to
    /// keep a margin over 4.5:1 on the canvas under its light pools.
    static let ink3 = Quad(light: 0x575F83, dark: 0x959DCB, lightHC: 0x363D62, darkHC: 0xC3C8EA)
    static let accentText = Quad(light: 0x4F46E5, dark: 0xA5B4FC, lightHC: 0x3730A3, darkHC: 0xC7D2FE)
    static let successText = Quad(light: 0x166534, dark: 0x6EE7A8, lightHC: 0x14532D, darkHC: 0xA7F3D0)
    /// Red 300 in dark (7.57:1 at worst), not the iPhone's red 400.
    static let errorText = Quad(light: 0xB91C1C, dark: 0xFCA5A5, lightHC: 0x991B1B, darkHC: 0xFECACA)

    // MARK: Fills and light (never text, except white on the fills noted)

    static let accent = Quad(fixed: 0x6366F1)
    static let violet = Quad(fixed: 0x8B5CF6)
    /// Glows, lit edges, the current node's halo, washes.
    static let lumen = Quad(light: 0x6366F1, dark: 0x9EA4FF, lightHC: 0x4F46E5, darkHC: 0xC7D2FE)
    static let success = Quad(light: 0x16A34A, dark: 0x34D399, lightHC: 0x15803D, darkHC: 0x34D399)
    static let error = Quad(light: 0xDC2626, dark: 0xF87171, lightHC: 0xB91C1C, darkHC: 0xF87171)
    /// The one prominent button per screen. White on it: 7.90:1 (9.93:1 HC).
    static let prominent = Quad(light: 0x4338CA, dark: 0x4338CA, lightHC: 0x3730A3, darkHC: 0x3730A3)
    static let prominentHover = Quad(light: 0x4F46E5, dark: 0x4F46E5, lightHC: 0x312E81, darkHC: 0x312E81)
    static let prominentPressed = Quad(light: 0x3730A3, dark: 0x3730A3, lightHC: 0x312E81, darkHC: 0x312E81)
    /// The composer's and the defense field's boundary (3:1 or better).
    static let fieldStroke = Quad(light: Shade(0x4F46E5, alpha: 0.72), dark: Shade(0xA5B4FC, alpha: 0.62),
                                  lightHC: Shade(0x3730A3), darkHC: Shade(0xC7D2FE))

    /// Today's Up next card, and nothing else (§2.5): three stops, top
    /// leading to bottom trailing.
    static let hero: [Quad] = [
        Quad(light: 0x4338CA, dark: 0x2B2486, lightHC: 0x3730A3, darkHC: 0x1E1B4B),
        Quad(light: 0x5B32D6, dark: 0x3B2A92, lightHC: 0x4C1D95, darkHC: 0x2E1065),
        Quad(light: 0x6D28D9, dark: 0x4E2A8E, lightHC: 0x5B21B6, darkHC: 0x3B0764),
    ]
    /// The radial light at Merc's corner of the hero. None under HC.
    static let heroLamp = Quad(light: Shade(0xB9B7FF, alpha: 0.22), dark: Shade(0xB9B7FF, alpha: 0.22),
                               lightHC: Shade(0xB9B7FF, alpha: 0), darkHC: Shade(0xB9B7FF, alpha: 0))
    /// Secondary text on the hero: white at 92%, solid white under HC.
    static let heroSecondary = Quad(light: Shade(0xFFFFFF, alpha: 0.92), dark: Shade(0xFFFFFF, alpha: 0.92),
                                    lightHC: Shade(0xFFFFFF), darkHC: Shade(0xFFFFFF))

    // MARK: The meaning sky (Lesson 1.1's interactive)

    /// The map of meaning is always night, in both appearances: an
    /// instrument panel inside a lit card, not a surface of its own. Flat
    /// and deeper under HC.
    static let skyTop = Quad(light: 0x0D1035, dark: 0x0D1035, lightHC: 0x05071A, darkHC: 0x05071A)
    static let skyBottom = Quad(light: 0x070923, dark: 0x070923, lightHC: 0x05071A, darkHC: 0x05071A)
    /// The words "bank" sits near, and "bank" itself: white.
    static let skyInk = Quad(fixed: 0xFFFFFF)
    /// The other words: white 74%, solid under HC.
    static let skyInk2 = Quad(light: Shade(0xFFFFFF, alpha: 0.74), dark: Shade(0xFFFFFF, alpha: 0.74),
                              lightHC: Shade(0xDDE0F7), darkHC: Shade(0xDDE0F7))
    /// The lines from "bank" to its neighbours, and its trail (marks: 3:1).
    static let skyLink = Quad(light: 0xC7CBFF, dark: 0xC7CBFF, lightHC: 0xFFFFFF, darkHC: 0xFFFFFF)
    /// "bank"'s pill: the hero's first two light stops (white on each is 7:1
    /// or better; white on `accent` would be 4.47:1).
    static let skyBank: [Quad] = [Quad(fixed: 0x4338CA), Quad(fixed: 0x5B32D6)]

    /// A neighbourhood's glow at its peak: the one "bank" sits in, and the
    /// other. None under HC.
    static func skyGlowAlpha(lit: Bool, _ variant: Variant) -> Double {
        guard !variant.isIncreasedContrast else { return 0 }
        return lit ? 0.42 : 0.16
    }

    /// A lit surface's one shadow (light mode only).
    static let shadowInk = Shade(0x1B1F4B, alpha: 0.07)
    /// The hero's one shadow (light mode only).
    static let heroShadow = Shade(0x4338CA, alpha: 0.18)

    // MARK: Light pools and tints (alphas)

    /// The canvas's light pools at their peak, by variant (§2.4). None
    /// under HC.
    static func poolAccentAlpha(_ variant: Variant) -> Double {
        switch variant {
        case .light: return 0.12
        case .dark: return 0.24
        case .lightHC, .darkHC: return 0
        }
    }

    static func poolVioletAlpha(_ variant: Variant) -> Double {
        switch variant {
        case .light: return 0.08
        case .dark: return 0.16
        case .lightHC, .darkHC: return 0
        }
    }

    /// The tints text sits on, light / dark (the same under HC).
    enum Tint {
        /// A picked answer row: `accent` over `surface`.
        static func selected(dark: Bool) -> Double { dark ? 0.20 : 0.10 }
        /// The student's turn: `accent` over the pooled canvas.
        static func student(dark: Bool) -> Double { dark ? 0.24 : 0.11 }
        /// The KEY / Your turn wash: `lumen` over `surface`.
        static func keyWash(dark: Bool) -> Double { dark ? 0.16 : 0.12 }
        /// A token chip's wash: `lumen` over `surface`.
        static func chip(dark: Bool) -> Double { dark ? 0.16 : 0.12 }
        /// Correct and wrong rows: `success` / `error` over `surface`.
        static let answer = 0.14
        /// Hover on a clickable lit surface: `lumen` over it.
        static let hover = 0.06
    }

    /// Floating chrome without glass: `surface` at this alpha over a material.
    static let chromeTint = 0.92

    // MARK: Resolving

    /// The variant an appearance draws in. Increase Contrast counts when the
    /// appearance carries a high-contrast name, when the system says so (a
    /// window forced to Dark by `.preferredColorScheme` may not carry the
    /// name), or under the DEBUG `-NightContrast increased` override.
    static func variant(appearanceIsDark dark: Bool, appearanceIsHighContrast: Bool,
                        systemIncreasesContrast: Bool, forcedIncreasedContrast: Bool) -> Variant {
        Variant(dark: dark, increasedContrast: appearanceIsHighContrast || systemIncreasesContrast
                    || forcedIncreasedContrast)
    }
}
