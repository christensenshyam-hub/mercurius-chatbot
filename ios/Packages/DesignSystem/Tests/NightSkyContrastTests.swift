#if os(macOS)
import Foundation
import Testing
@testable import DesignSystem

/// The meaning sky (Lesson 1.1's interactive): every word on the panel, in
/// all four appearances. The panel is night in light and dark alike, so the
/// worst case is the brightest it gets: a neighbourhood's glow at its peak
/// over the panel's top. `night_contrast.py` holds the same pairs.
@Suite("Night Studio contrast: the meaning sky")
struct NightSkyContrastTests {
    typealias RGB = NightContrastTests.RGB
    typealias Variant = NightPalette.Variant

    static func rgb(_ quad: NightPalette.Quad, _ v: Variant, over base: RGB? = nil) -> RGB {
        NightContrastTests.rgb(quad, v, over: base)
    }

    /// Where a word sits: the panel's top and bottom, and under each
    /// neighbourhood's glow at its peak (lit, which is the brighter).
    static func backgrounds(_ v: Variant) -> [(String, RGB)] {
        let top = rgb(NightPalette.skyTop, v)
        let bottom = rgb(NightPalette.skyBottom, v)
        let glow = NightPalette.skyGlowAlpha(lit: true, v)
        return [
            ("sky top", top),
            ("sky bottom", bottom),
            ("indigo glow", rgb(NightPalette.accent, v).over(top, alpha: glow)),
            ("violet glow", rgb(NightPalette.violet, v).over(top, alpha: glow)),
        ]
    }

    @Test("Every word on the panel reads at 4.5:1 or better, under the glows too", arguments: Variant.allCases)
    func words(variant v: Variant) {
        for (name, background) in Self.backgrounds(v) {
            for (token, quad) in [("skyInk", NightPalette.skyInk), ("skyInk2", NightPalette.skyInk2)] {
                let ratio = NightContrastTests.contrast(Self.rgb(quad, v, over: background), background)
                let minimum = v.isIncreasedContrast ? NightContrastTests.textMinimumHC : NightContrastTests.textMinimum
                #expect(ratio >= minimum, "\(token) on \(name), \(v): \(NightContrastTests.ratio(ratio))")
            }
        }
    }

    @Test("White on bank's pill and on the followed token chip", arguments: Variant.allCases)
    func bankPill(variant v: Variant) {
        for stop in NightPalette.skyBank {
            let ratio = NightContrastTests.contrast(.white, Self.rgb(stop, v))
            #expect(ratio >= 7, "white on \(String(stop.shade(v).hex, radix: 16)): \(NightContrastTests.ratio(ratio))")
        }
    }

    @Test("bank's lines and the word dots read as marks (3:1)", arguments: Variant.allCases)
    func marks(variant v: Variant) {
        for (name, background) in Self.backgrounds(v) {
            let link = NightContrastTests.contrast(Self.rgb(NightPalette.skyLink, v), background)
            #expect(link >= NightContrastTests.nonTextMinimum, "link on \(name), \(v): \(NightContrastTests.ratio(link))")
            let dot = NightContrastTests.contrast(.white, background)
            #expect(dot >= NightContrastTests.nonTextMinimum, "dot on \(name), \(v)")
        }
    }

    @Test("The panel is night in both appearances; Increase Contrast flattens it and puts out the glows")
    func alwaysNight() {
        #expect(NightPalette.skyTop.light == NightPalette.skyTop.dark)
        #expect(NightPalette.skyBottom.light == NightPalette.skyBottom.dark)
        #expect(NightPalette.skyTop.lightHC == NightPalette.skyBottom.lightHC)
        #expect(NightPalette.skyTop.darkHC == NightPalette.skyBottom.darkHC)
        for v in Variant.allCases {
            #expect((NightPalette.skyGlowAlpha(lit: true, v) == 0) == v.isIncreasedContrast)
            #expect(NightPalette.skyGlowAlpha(lit: false, v) <= NightPalette.skyGlowAlpha(lit: true, v))
        }
        #expect(NightSky.glowAlpha(lit: true, increasedContrast: true) == 0)
    }
}
#endif
