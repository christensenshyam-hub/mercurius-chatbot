import SwiftUI
import Testing
@testable import DesignSystem

/// The iPhone's night-sky card (Lesson 1.1's interactive): its colours are
/// Night Studio's night in both of the iPhone's appearances, flattened
/// under Reduce Transparency, and every word on it reads at 4.5:1 (7:1
/// under Increase Contrast). Shared: the values are checked on the macOS
/// host, where `swift test` runs.
@Suite("The iPhone's night-sky card")
struct NightSkyCardTests {
    typealias Shade = NightPalette.Shade

    // MARK: Contrast (WCAG 2.x)

    static func luminance(_ s: Shade) -> Double {
        func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(s.red) + 0.7152 * channel(s.green) + 0.0722 * channel(s.blue)
    }

    static func contrast(_ a: Shade, _ b: Shade) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `top` (with its own alpha, times `alpha`) over an opaque `base`.
    static func over(_ top: Shade, _ base: Shade, alpha: Double = 1) -> Shade {
        NightSkyCard.flattened(Shade(top.hex), alpha: top.alpha * alpha, over: base)
    }

    static let white = Shade(0xFFFFFF)

    /// The card's backgrounds for text: the card, its wells, and a token
    /// chip's wash (lumen at 16% over the card).
    static func backgrounds(_ hc: Bool) -> [(String, Shade)] {
        let v: NightPalette.Variant = hc ? .darkHC : .dark
        let surface = NightPalette.surface.shade(v)
        return [
            ("surface", surface),
            ("raised", NightPalette.surfaceRaised.shade(v)),
            ("chip wash", over(NightPalette.lumen.shade(v), surface, alpha: 0.16)),
        ]
    }

    @Test("Every word on the card reads at 4.5:1, 7:1 under Increase Contrast", arguments: [false, true])
    func words(increasedContrast hc: Bool) {
        let v: NightPalette.Variant = hc ? .darkHC : .dark
        let floor = hc ? 7.0 : 4.5
        let inks: [(String, NightPalette.Quad)] = [("ink", NightPalette.ink), ("ink2", NightPalette.ink2),
                                                    ("ink3", NightPalette.ink3), ("accentText", NightPalette.accentText)]
        for (bgName, bg) in Self.backgrounds(hc) {
            for (name, quad) in inks {
                let ratio = Self.contrast(quad.shade(v), bg)
                #expect(ratio >= floor, "\(name) on \(bgName) (\(hc ? "HC" : "standard")): \(ratio)")
            }
        }
    }

    @Test("White on the picked opening, on bank's indigo and on the typed sentence's bubble")
    func white() {
        for v in [NightPalette.Variant.dark, .darkHC] {
            #expect(Self.contrast(Self.white, NightPalette.prominent.shade(v)) >= 7)
            for stop in NightPalette.skyBank { #expect(Self.contrast(Self.white, stop.shade(v)) >= 7) }
        }
        // The student's bubble a step deeper: accentDark → mercViolet.
        #expect(Self.contrast(Self.white, Shade(0x4C51BF)) >= 5.5)
        #expect(Self.contrast(Self.white, Shade(0x7C3AED)) >= 5.5)
        // The iPhone's own bubble hues would not do on the card.
        #expect(Self.contrast(Self.white, Shade(0x6366F1)) < 4.5)
    }

    @Test("Under Reduce Transparency the map's other words are solid and still read")
    func solidMapWords() {
        let solid = NightPalette.skyInk2.darkHC
        #expect(solid.alpha == 1)
        for sky in [NightPalette.skyTop.dark, NightPalette.skyBottom.dark] {
            #expect(Self.contrast(solid, sky) >= 7)
        }
    }

    @Test("Flattening mixes in sRGB, as the card's translucent wash would draw")
    func flattened() {
        let mid = NightSkyCard.flattened(Shade(0xFFFFFF), alpha: 0.5, over: Shade(0x000000))
        #expect(mid.hex == 0x808080)
        #expect(NightSkyCard.flattened(Shade(0x123456), alpha: 1, over: Shade(0xABCDEF)).hex == 0x123456)
        #expect(NightSkyCard.flattened(Shade(0x123456), alpha: 0, over: Shade(0xABCDEF)).hex == 0xABCDEF)
    }

    @Test("The card is Night's night: the same in both appearances, HC under Increase Contrast")
    func variants() {
        #expect(NightSkyCard(increasedContrast: false).variant == .dark)
        #expect(NightSkyCard(increasedContrast: true).variant == .darkHC)
        #expect(NightSkyCard(increasedContrast: false).lit)
        #expect(!NightSkyCard(increasedContrast: true).lit)
        #expect(!NightSkyCard(increasedContrast: false, reduceTransparency: true).lit)
        #expect(NightSkyCard(increasedContrast: false, reduceTransparency: true).glowAlpha(lit: true) == 0)
        #expect(NightSkyCard(increasedContrast: true).glowAlpha(lit: true) == 0)
        #expect(NightSkyCard(increasedContrast: false).glowAlpha(lit: true) > 0)
    }
}
