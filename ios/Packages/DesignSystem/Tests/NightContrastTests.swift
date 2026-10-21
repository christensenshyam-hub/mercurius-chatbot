#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// WCAG 2.x contrast for Night Studio's tokens on the Mac (SPEC.md §2.3), in
/// all four appearances: light, dark, and both under Increase Contrast.
/// Computed from `NightPalette`, the raw values every `Night` colour is
/// built from. Translucent fills are composited in sRGB over their base, the
/// model `BrandContrastTests` uses. `docs/mac-night-studio/night_contrast.py`
/// is the reference: the same pairs, the same minimums, the same numbers.
@Suite("Night Studio contrast")
struct NightContrastTests {
    typealias Variant = NightPalette.Variant

    /// A colour as drawn, 0...1 per channel.
    struct RGB {
        let r: Double
        let g: Double
        let b: Double

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        init(_ hex: UInt32) {
            self.init(NightPalette.Shade(hex))
        }

        /// The shade's opaque colour (its alpha is applied by `over`).
        init(_ shade: NightPalette.Shade) {
            r = shade.red
            g = shade.green
            b = shade.blue
        }

        static let white = RGB(r: 1, g: 1, b: 1)

        func over(_ base: RGB, alpha: Double) -> RGB {
            RGB(r: r * alpha + base.r * (1 - alpha),
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

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let hi = max(a.luminance, b.luminance)
        let lo = min(a.luminance, b.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// A token in a variant, composited over `base` when it is translucent.
    static func rgb(_ quad: NightPalette.Quad, _ variant: Variant, over base: RGB? = nil) -> RGB {
        let shade = quad.shade(variant)
        guard let base, shade.alpha < 1 else { return RGB(shade) }
        return RGB(shade).over(base, alpha: shade.alpha)
    }

    /// WCAG AA for normal text.
    static let textMinimum = 4.5
    /// What Increase Contrast holds the text tokens to on plain surfaces.
    static let textMinimumHC = 7.0
    /// WCAG 1.4.11: UI components and focus indicators.
    static let nonTextMinimum = 3.0

    static let textTokens: [(String, NightPalette.Quad)] = [
        ("ink", NightPalette.ink),
        ("ink2", NightPalette.ink2),
        ("ink3", NightPalette.ink3),
        ("accentText", NightPalette.accentText),
        ("successText", NightPalette.successText),
        ("errorText", NightPalette.errorText),
    ]

    /// Where Night text sits. The canvas is also taken under each light
    /// pool at its peak: the darkest the light canvas gets, the brightest
    /// the dark one does.
    static func surfaces(_ v: Variant) -> [(String, RGB)] {
        let top = rgb(NightPalette.canvasTop, v)
        let bottom = rgb(NightPalette.canvasBottom, v)
        return [
            ("canvasTop", top),
            ("canvasBottom", bottom),
            ("canvasPool", rgb(NightPalette.accent, v).over(top, alpha: NightPalette.poolAccentAlpha(v))),
            ("canvasViolet", rgb(NightPalette.violet, v).over(bottom, alpha: NightPalette.poolVioletAlpha(v))),
            ("surface", rgb(NightPalette.surface, v)),
            ("surfaceRaised", rgb(NightPalette.surfaceRaised, v)),
            ("sidebar", rgb(NightPalette.sidebar, v)),
        ]
    }

    /// A text colour on a tinted or special surface: (name, text, background).
    static func tintedUses(_ v: Variant) -> [(String, RGB, RGB)] {
        let dark = v.isDark
        let surface = rgb(NightPalette.surface, v)
        let pool = surfaces(v)[2].1
        let selected = rgb(NightPalette.accent, v).over(surface, alpha: NightPalette.Tint.selected(dark: dark))
        let correct = rgb(NightPalette.success, v).over(surface, alpha: NightPalette.Tint.answer)
        let wrong = rgb(NightPalette.error, v).over(surface, alpha: NightPalette.Tint.answer)
        let student = rgb(NightPalette.accent, v).over(pool, alpha: NightPalette.Tint.student(dark: dark))
        let keyWash = rgb(NightPalette.lumen, v).over(surface, alpha: NightPalette.Tint.keyWash(dark: dark))
        let chip = rgb(NightPalette.lumen, v).over(surface, alpha: NightPalette.Tint.chip(dark: dark))
        let ink = rgb(NightPalette.ink, v)
        var uses: [(String, RGB, RGB)] = [
            ("option text, selected row", ink, selected),
            ("option letter, selected row", rgb(NightPalette.accentText, v), selected),
            ("option text, correct row", ink, correct),
            ("correct mark, correct row", rgb(NightPalette.successText, v), correct),
            ("option text, wrong row", ink, wrong),
            ("wrong mark, wrong row", rgb(NightPalette.errorText, v), wrong),
            ("student turn text", ink, student),
            ("KEY idea text under the lumen wash", ink, keyWash),
            ("KEY eyebrow under the lumen wash", rgb(NightPalette.accentText, v), keyWash),
            ("token chip text", rgb(NightPalette.accentText, v), chip),
            ("caption (ink3) on the KEY wash", rgb(NightPalette.ink3, v), keyWash),
        ]
        // The hero: white and its secondary on every stop, and under the
        // lamp at Merc's corner.
        let lamp = NightPalette.heroLamp.shade(v)
        let secondary = NightPalette.heroSecondary.shade(v)
        for (index, quad) in NightPalette.hero.enumerated() {
            let stop = rgb(quad, v)
            let lit = RGB(lamp).over(stop, alpha: lamp.alpha)
            uses.append(("white on hero stop \(index + 1)", .white, stop))
            uses.append(("white on hero stop \(index + 1) under the lamp", .white, lit))
            uses.append(("hero secondary on stop \(index + 1)", RGB.white.over(stop, alpha: secondary.alpha), stop))
            uses.append(("hero secondary on stop \(index + 1) under the lamp",
                         RGB.white.over(lit, alpha: secondary.alpha), lit))
        }
        // Floating chrome without glass: the surface tint over a material
        // that, at worst, blurs a line of ink.
        let chrome = rgb(NightPalette.surface, v).over(ink, alpha: NightPalette.chromeTint)
        uses.append(("placeholder (ink3) on fallback chrome, worst case", rgb(NightPalette.ink3, v), chrome))
        uses.append(("accentText on fallback chrome, worst case", rgb(NightPalette.accentText, v), chrome))
        uses.append(("hero button label (prominent on white)", rgb(NightPalette.prominent, v), .white))
        uses.append(("white on prominentHover", .white, rgb(NightPalette.prominentHover, v)))
        uses.append(("white on prominent", .white, rgb(NightPalette.prominent, v)))
        uses.append(("white on prominentPressed", .white, rgb(NightPalette.prominentPressed, v)))
        return uses
    }

    /// Strokes that must read as a boundary or a focus indicator.
    static func nonTextUses(_ v: Variant) -> [(String, RGB, RGB)] {
        let canvas = rgb(NightPalette.canvasTop, v)
        let pool = surfaces(v)[2].1
        let surface = rgb(NightPalette.surface, v)
        let raised = rgb(NightPalette.surfaceRaised, v)
        let ring = rgb(NightPalette.accentText, v)
        var uses: [(String, RGB, RGB)] = [
            ("focus ring on canvas", ring, canvas),
            ("focus ring on pool", ring, pool),
            ("focus ring on surface", ring, surface),
            ("selected-row stroke on raised", ring, raised),
            ("field stroke on canvas", rgb(NightPalette.fieldStroke, v, over: canvas), canvas),
            ("field stroke on pool", rgb(NightPalette.fieldStroke, v, over: pool), pool),
            ("field stroke on surface", rgb(NightPalette.fieldStroke, v, over: surface), surface),
        ]
        if v.isIncreasedContrast {
            // Every edge is a solid hairline that must itself be a boundary.
            uses.append(("hairline on surface", rgb(NightPalette.hairline, v, over: surface), surface))
            uses.append(("hairline on canvas", rgb(NightPalette.hairline, v, over: canvas), canvas))
        }
        return uses
    }

    static func ratio(_ ratio: Double) -> String { String(format: "%.2f", ratio) }

    // MARK: - Floors

    @Test("Every text token reads at 4.5:1 (7:1 under Increase Contrast) on every surface, the light pools included",
          arguments: Variant.allCases)
    func textOnSurfaces(variant: Variant) {
        let floor = variant.isIncreasedContrast ? Self.textMinimumHC : Self.textMinimum
        for (textName, text) in Self.textTokens {
            for (surfaceName, surface) in Self.surfaces(variant) {
                let r = Self.contrast(Self.rgb(text, variant), surface)
                #expect(r >= floor, "\(textName) on \(surfaceName) (\(variant)) is \(Self.ratio(r)):1")
            }
        }
    }

    @Test("Text on the tints, the hero and the prominent fill reads at 4.5:1 or better", arguments: Variant.allCases)
    func textOnTints(variant: Variant) {
        for (name, text, background) in Self.tintedUses(variant) {
            let r = Self.contrast(text, background)
            #expect(r >= Self.textMinimum, "\(name) (\(variant)) is \(Self.ratio(r)):1")
        }
    }

    @Test("Focus rings and field strokes read at 3:1 or better; under Increase Contrast, so do hairlines",
          arguments: Variant.allCases)
    func nonText(variant: Variant) {
        for (name, stroke, background) in Self.nonTextUses(variant) {
            let r = Self.contrast(stroke, background)
            #expect(r >= Self.nonTextMinimum, "\(name) (\(variant)) is \(Self.ratio(r)):1")
        }
    }

    // MARK: - The reference numbers

    /// The lowest ratio of a text token over every surface in a variant.
    static func floorOf(_ quad: NightPalette.Quad, _ variant: Variant) -> Double {
        surfaces(variant).map { contrast(rgb(quad, variant), $0.1) }.min() ?? 0
    }

    @Test("The lowest ratios match SPEC.md §2.3's table (night_contrast.py)")
    func matchesTheSpecTable() {
        let expected: [(Variant, [Double])] = [
            (.light, [14.18, 6.66, 4.83, 4.87, 5.53, 5.01]),
            (.dark, [12.93, 7.80, 5.45, 7.21, 9.35, 7.57]),
            (.lightHC, [17.67, 11.31, 9.29, 8.79, 8.06, 7.35]),
            (.darkHC, [16.28, 12.47, 9.90, 10.92, 12.70, 11.25]),
        ]
        for (variant, values) in expected {
            for ((name, quad), value) in zip(Self.textTokens, values) {
                let got = Self.floorOf(quad, variant)
                #expect(abs(got - value) < 0.01, "\(name) (\(variant)) floor is \(Self.ratio(got)), the spec says \(value)")
            }
        }
    }

    @Test("Under the concept's overlapping pools, its ink3 failed: the token and the pools moved for a reason")
    func conceptInk3WouldFail() {
        // The concept's #5A6286 / #8E96C4 where its two pools overlapped at
        // their peaks (16% indigo + 10% violet light, 34% + 22% dark): 4.08
        // and 3.43:1 (ARCHITECTURE.md §2.3).
        func pooled(_ canvas: UInt32, _ indigo: Double, _ violet: Double) -> RGB {
            RGB(0x8B5CF6).over(RGB(0x6366F1).over(RGB(canvas), alpha: indigo), alpha: violet)
        }
        #expect(Self.contrast(RGB(0x5A6286), pooled(0xF6F5FC, 0.16, 0.10)) < 4.5)
        #expect(Self.contrast(RGB(0x8E96C4), pooled(0x0B0E2E, 0.34, 0.22)) < 4.5)
        // Night's ink3 at Night's capped pools, overlapped the same way.
        #expect(Self.contrast(Self.rgb(NightPalette.ink3, .light), pooled(0xF6F5FC, 0.12, 0.08)) >= 4.5)
        #expect(Self.contrast(Self.rgb(NightPalette.ink3, .dark), pooled(0x0B0E2E, 0.24, 0.16)) >= 4.5)
    }

    @Test("ink3 holds 4.5:1 everywhere on the canvas as NightCanvas draws it, both pools on",
          arguments: [Variant.light, .dark])
    func ink3AcrossTheDrawnCanvas(variant: Variant) {
        // Samples the canvas at the window sizes the spec designs for: the
        // gradient, then each pool's linear falloff from its peak.
        for size in [CGSize(width: 1040, height: 748), CGSize(width: 700, height: 548),
                     CGSize(width: 1600, height: 1000)] {
            let indigo = NightCanvas.indigoPool(in: size)
            let violet = NightCanvas.violetPool(in: size)
            let top = Self.rgb(NightPalette.canvasTop, variant)
            let bottom = Self.rgb(NightPalette.canvasBottom, variant)
            var worst = Double.infinity
            for x in stride(from: 0.0, through: Double(size.width), by: 10) {
                for y in stride(from: 0.0, through: Double(size.height), by: 10) {
                    let base = bottom.over(top, alpha: y / Double(size.height))
                    let d1 = hypot(x - Double(indigo.center.x), y - Double(indigo.center.y))
                    let d2 = hypot(x - Double(violet.center.x), y - Double(violet.center.y))
                    let a1 = NightPalette.poolAccentAlpha(variant) * max(0, 1 - d1 / Double(indigo.radius))
                    let a2 = NightPalette.poolVioletAlpha(variant) * max(0, 1 - d2 / Double(violet.radius))
                    let lit = Self.rgb(NightPalette.violet, variant)
                        .over(Self.rgb(NightPalette.accent, variant).over(base, alpha: a1), alpha: a2)
                    worst = min(worst, Self.contrast(Self.rgb(NightPalette.ink3, variant), lit))
                }
            }
            #expect(worst >= Self.textMinimum, "ink3 (\(variant)) at \(size) falls to \(Self.ratio(worst)):1")
        }
    }

    // MARK: - Resolving

    @Test("A variant is dark or light from the appearance, and increased from any of three sources")
    func variants() {
        #expect(NightPalette.variant(appearanceIsDark: false, appearanceIsHighContrast: false,
                                     systemIncreasesContrast: false, forcedIncreasedContrast: false) == .light)
        #expect(NightPalette.variant(appearanceIsDark: true, appearanceIsHighContrast: false,
                                     systemIncreasesContrast: false, forcedIncreasedContrast: false) == .dark)
        #expect(NightPalette.variant(appearanceIsDark: false, appearanceIsHighContrast: true,
                                     systemIncreasesContrast: false, forcedIncreasedContrast: false) == .lightHC)
        #expect(NightPalette.variant(appearanceIsDark: true, appearanceIsHighContrast: false,
                                     systemIncreasesContrast: true, forcedIncreasedContrast: false) == .darkHC)
        #expect(NightPalette.variant(appearanceIsDark: false, appearanceIsHighContrast: false,
                                     systemIncreasesContrast: false, forcedIncreasedContrast: true) == .lightHC)
    }

    @Test("Increase Contrast flattens the canvas and puts out the pools, the lamp and the hero's soft text")
    func increasedContrastIsFlat() {
        for variant in [Variant.lightHC, .darkHC] {
            #expect(NightPalette.canvasTop.shade(variant) == NightPalette.canvasBottom.shade(variant))
            #expect(NightPalette.poolAccentAlpha(variant) == 0)
            #expect(NightPalette.poolVioletAlpha(variant) == 0)
            #expect(NightPalette.heroLamp.shade(variant).alpha == 0)
            #expect(NightPalette.heroSecondary.shade(variant).alpha == 1)
            #expect(NightPalette.fieldStroke.shade(variant).alpha == 1)
        }
    }

    @Test("BrandColor.border is Night's hairline flattened over a surface")
    func borderIsTheFlattenedHairline() {
        for variant in Variant.allCases {
            let surface = Self.rgb(NightPalette.surface, variant)
            let flattened = Self.rgb(NightPalette.hairline, variant, over: surface)
            let border = Self.rgb(NightPalette.border, variant)
            #expect(abs(flattened.r - border.r) * 255 < 1.6, "\(variant)")
            #expect(abs(flattened.g - border.g) * 255 < 1.6, "\(variant)")
            #expect(abs(flattened.b - border.b) * 255 < 1.6, "\(variant)")
        }
    }
}

/// On the Mac, `BrandColor` reads Night Studio's palette (SPEC.md §2.2), so
/// the shared views take it without per-view edits.
@Suite("BrandColor on the Mac reads Night")
@MainActor
struct NightPaletteMappingTests {

    /// `color` drawn in `appearance`, as 0xRRGGBB.
    static func drawn(_ color: Color, in name: NSAppearance.Name) -> UInt32? {
        guard let appearance = NSAppearance(named: name) else { return nil }
        let ns = NSColor(color)
        var hex: UInt32?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = ns.usingColorSpace(.sRGB) else { return }
            let r = UInt32((srgb.redComponent * 255).rounded())
            let g = UInt32((srgb.greenComponent * 255).rounded())
            let b = UInt32((srgb.blueComponent * 255).rounded())
            hex = (r << 16) | (g << 8) | b
        }
        return hex
    }

    static let mapping: [(String, Color, NightPalette.Quad)] = [
        ("background", BrandColor.background, NightPalette.canvasTop),
        ("surface", BrandColor.surface, NightPalette.surface),
        ("surfaceElevated", BrandColor.surfaceElevated, NightPalette.surfaceRaised),
        ("border", BrandColor.border, NightPalette.border),
        ("text", BrandColor.text, NightPalette.ink),
        ("textSecondary", BrandColor.textSecondary, NightPalette.ink2),
        ("accentText", BrandColor.accentText, NightPalette.accentText),
        ("successText", BrandColor.successText, NightPalette.successText),
        ("errorText", BrandColor.errorText, NightPalette.errorText),
        ("success", BrandColor.success, NightPalette.success),
        ("error", BrandColor.error, NightPalette.error),
    ]

    @Test("Each BrandColor token draws its Night value, light and dark")
    func mapping() throws {
        // A Mac with Increase Contrast on draws the HC column instead.
        try #require(!NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        for (name, color, quad) in Self.mapping {
            #expect(Self.drawn(color, in: .aqua) == quad.light.hex, "\(name), light")
            #expect(Self.drawn(color, in: .darkAqua) == quad.dark.hex, "\(name), dark")
        }
    }

    @Test("The fixed hues stay fixed")
    func fixedHues() {
        #expect(Self.drawn(BrandColor.accent, in: .aqua) == 0x6366F1)
        #expect(Self.drawn(BrandColor.accent, in: .darkAqua) == 0x6366F1)
        #expect(Self.drawn(BrandColor.mercViolet, in: .darkAqua) == 0x7C3AED)
    }

    @Test("BrandPalette, the iPhone's values, is untouched")
    func iPhonePaletteUnchanged() {
        #expect(BrandPalette.background == .init(light: 0xF7FAFC, dark: 0x0B0F30))
        #expect(BrandPalette.text == .init(light: 0x0F142A, dark: 0xE6E9F5))
        #expect(BrandPalette.accentText == .init(light: 0x4F46E5, dark: 0xA5B4FC))
        #expect(BrandPalette.errorText == .init(light: 0xB91C1C, dark: 0xF87171))
    }
}

/// The pairs the lesson reader and the chat add (step 02): the check's
/// discs, the part strip and the mode switch on floating chrome.
@Suite("Night Studio contrast: lesson and chat")
struct NightReadingContrastTests {
    typealias Variant = NightPalette.Variant
    typealias RGB = NightContrastTests.RGB

    func rgb(_ quad: NightPalette.Quad, _ v: Variant, over base: RGB? = nil) -> RGB {
        NightContrastTests.rgb(quad, v, over: base)
    }

    @Test("Text on the part strip, the mode switch and the composer's chrome reads at 4.5:1", arguments: Variant.allCases)
    func chromeText(variant v: Variant) {
        let ink = rgb(NightPalette.ink, v)
        // Fallback chrome at its worst: the surface tint over a line of ink.
        let chrome = rgb(NightPalette.surface, v).over(ink, alpha: NightPalette.chromeTint)
        for (name, quad) in [("ink", NightPalette.ink), ("ink2", NightPalette.ink2), ("ink3", NightPalette.ink3),
                             ("accentText", NightPalette.accentText)] {
            let r = NightContrastTests.contrast(rgb(quad, v), chrome)
            #expect(r >= NightContrastTests.textMinimum, "\(name) on fallback chrome (\(v)) is \(NightContrastTests.ratio(r)):1")
        }
        // The selected mode and the send circle: white on the opaque prominent fill.
        #expect(NightContrastTests.contrast(.white, rgb(NightPalette.prominent, v)) >= NightContrastTests.textMinimum)
    }

    @Test("The check's discs: the picked letter, the correct and the wrong letters", arguments: Variant.allCases)
    func discs(variant v: Variant) {
        let surface = rgb(NightPalette.surface, v)
        let selected = rgb(NightPalette.accent, v).over(surface, alpha: NightPalette.Tint.selected(dark: v.isDark))
        let correct = rgb(NightPalette.success, v).over(surface, alpha: NightPalette.Tint.answer)
        let wrong = rgb(NightPalette.error, v).over(surface, alpha: NightPalette.Tint.answer)
        let raised = rgb(NightPalette.surfaceRaised, v)
        // Text (4.5:1): the picked disc's white letter on prominent; the
        // graded rows' letters (every row keeps its letter); a resting
        // letter in ink2 on the raised row.
        #expect(NightContrastTests.contrast(.white, rgb(NightPalette.prominent, v)) >= 4.5)
        #expect(NightContrastTests.contrast(rgb(NightPalette.successText, v), correct) >= 4.5)
        #expect(NightContrastTests.contrast(rgb(NightPalette.errorText, v), wrong) >= 4.5)
        #expect(NightContrastTests.contrast(rgb(NightPalette.ink2, v), raised) >= 4.5)
        // Non-text (3:1): the picked row's state, its 2 pt `accentText`
        // edge, against the row inside it and the card around it. (The
        // disc's fill against the row is decoration: 1.7:1 in dark, and the
        // edge and the white letter carry the state.)
        for (name, base) in [("row", selected), ("card", surface)] {
            let edge = NightContrastTests.contrast(rgb(NightPalette.accentText, v), base)
            #expect(edge >= 3, "picked edge on the \(name) (\(v)) is \(NightContrastTests.ratio(edge)):1")
        }
    }

    @Test("White on accent would fail for the picked letter: why the disc is prominent")
    func whiteOnAccentFails() {
        #expect(NightContrastTests.contrast(.white, rgb(NightPalette.accent, .light)) < 4.5)
    }
}
#endif

#if os(macOS)
/// Step 03's screens (the unit page, lesson complete, the unit check, the
/// gate, Settings): the pairs they add to SPEC.md §2.3.
@Suite("Night Studio contrast: the path, lesson complete, the unit check")
struct NightRestContrastTests {
    typealias Variant = NightPalette.Variant
    typealias RGB = NightContrastTests.RGB

    func rgb(_ quad: NightPalette.Quad, _ v: Variant, over base: RGB? = nil) -> RGB {
        NightContrastTests.rgb(quad, v, over: base)
    }

    /// The lesson-complete card draws its own canvas, both pools on, at a
    /// card's size: the pools sit closer together there than in a window.
    /// Every text token on it, sampled across the card as NightCanvas draws
    /// it, reads at 4.5:1.
    @Test("Text on the complete card's own canvas reads at 4.5:1 everywhere", arguments: [Variant.light, .dark])
    func completeCardCanvas(variant: Variant) {
        for size in [CGSize(width: 520, height: 640), CGSize(width: 520, height: 500),
                     CGSize(width: 472, height: 500)] {
            let indigo = NightCanvas.indigoPool(in: size)
            let violet = NightCanvas.violetPool(in: size)
            let top = rgb(NightPalette.canvasTop, variant)
            let bottom = rgb(NightPalette.canvasBottom, variant)
            for (name, quad) in NightContrastTests.textTokens {
                var worst = Double.infinity
                for x in stride(from: 0.0, through: Double(size.width), by: 8) {
                    for y in stride(from: 0.0, through: Double(size.height), by: 8) {
                        let base = bottom.over(top, alpha: y / Double(size.height))
                        let d1 = hypot(x - Double(indigo.center.x), y - Double(indigo.center.y))
                        let d2 = hypot(x - Double(violet.center.x), y - Double(violet.center.y))
                        let a1 = NightPalette.poolAccentAlpha(variant) * max(0, 1 - d1 / Double(indigo.radius))
                        let a2 = NightPalette.poolVioletAlpha(variant) * max(0, 1 - d2 / Double(violet.radius))
                        let lit = rgb(NightPalette.violet, variant)
                            .over(rgb(NightPalette.accent, variant).over(base, alpha: a1), alpha: a2)
                        worst = min(worst, NightContrastTests.contrast(rgb(quad, variant), lit))
                    }
                }
                #expect(worst >= NightContrastTests.textMinimum,
                        "\(name) (\(variant)) on a \(size) card falls to \(NightContrastTests.ratio(worst)):1")
            }
        }
    }

    @Test("The path's nodes: the done check, the mastered check, a node's number", arguments: Variant.allCases)
    func pathNodes(variant v: Variant) {
        let surface = rgb(NightPalette.surface, v)
        // The done node's check (non-text, 3:1): white on each stop of the
        // brand light, or `surface` on the flat HC fill.
        if v.isIncreasedContrast {
            let check = NightContrastTests.contrast(surface, rgb(NightPalette.accentText, v))
            #expect(check >= 3, "done check under HC (\(v)) is \(NightContrastTests.ratio(check)):1")
        } else {
            for stop in [NightPalette.accent, NightPalette.violet] {
                let check = NightContrastTests.contrast(.white, rgb(stop, v))
                #expect(check >= 3, "done check (\(v)) is \(NightContrastTests.ratio(check)):1")
            }
        }
        // The mastered check node: `surface` on `successText`.
        #expect(NightContrastTests.contrast(surface, rgb(NightPalette.successText, v)) >= 3)
        // Numbers in nodes (text): accentText on surface (current), ink2 on
        // the canvas (ahead).
        #expect(NightContrastTests.contrast(rgb(NightPalette.accentText, v), surface) >= 4.5)
        #expect(NightContrastTests.contrast(rgb(NightPalette.ink2, v), rgb(NightPalette.canvasTop, v)) >= 4.5)
        // The ahead node's ring against the canvas (non-text).
        #expect(NightContrastTests.contrast(rgb(NightPalette.ink3, v), rgb(NightPalette.canvasTop, v)) >= 3)
    }

    @Test("The written answer's well: its edge, its text and its placeholder", arguments: Variant.allCases)
    func writtenAnswerWell(variant v: Variant) {
        let raised = rgb(NightPalette.surfaceRaised, v)
        let edge = rgb(NightPalette.fieldStroke, v, over: raised)
        #expect(NightContrastTests.contrast(edge, raised) >= 3,
                "field edge on the well (\(v)) is \(NightContrastTests.ratio(NightContrastTests.contrast(edge, raised))):1")
        for quad in [NightPalette.ink, NightPalette.ink3] {
            #expect(NightContrastTests.contrast(rgb(quad, v), raised) >= 4.5)
        }
    }

    @Test("The complete card's week well and its text", arguments: Variant.allCases)
    func weekWell(variant v: Variant) {
        let raised = rgb(NightPalette.surfaceRaised, v)
        for quad in [NightPalette.ink, NightPalette.ink2] {
            let floor = v.isIncreasedContrast ? NightContrastTests.textMinimumHC : NightContrastTests.textMinimum
            #expect(NightContrastTests.contrast(rgb(quad, v), raised) >= floor)
        }
    }
}
#endif
