import SwiftUI

/// The colours of Lesson 1.1's interactive on the iPhone ("How a model
/// reads “bank”"): a night-sky card that looks the same in the iPhone's
/// light and dark appearances, because it is a picture of the meaning sky,
/// not a surface of the app. It is Night Studio's night: `NightPalette`'s
/// dark values, and its dark Increase Contrast values under Increase
/// Contrast, so the iPhone's card and the Mac's map of meaning are one sky
/// (`NightSkyCardContrastTests` holds every word on it to 4.5:1).
///
/// Under Reduce Transparency every translucent token is drawn solid: the
/// washes flattened over the card, the edges and the map's other words
/// opaque, and no glows.
///
/// Everything else on the iPhone keeps `BrandColor`.
public struct NightSkyCard: Equatable, Sendable {
    public let increasedContrast: Bool
    public let reduceTransparency: Bool

    public init(increasedContrast: Bool, reduceTransparency: Bool = false) {
        self.increasedContrast = increasedContrast
        self.reduceTransparency = reduceTransparency
    }

    var variant: NightPalette.Variant { increasedContrast ? .darkHC : .dark }

    private func color(_ quad: NightPalette.Quad) -> Color {
        color(quad.shade(variant))
    }

    private func color(_ shade: NightPalette.Shade) -> Color {
        Color(.sRGB, red: shade.red, green: shade.green, blue: shade.blue, opacity: shade.alpha)
    }

    /// `top` at `alpha` over `base`, as one opaque colour.
    static func flattened(_ top: NightPalette.Shade, alpha: Double, over base: NightPalette.Shade) -> NightPalette.Shade {
        func mix(_ a: Double, _ b: Double) -> UInt32 { UInt32((a * alpha + b * (1 - alpha)) * 255 + 0.5) }
        return NightPalette.Shade(mix(top.red, base.red) << 16 | mix(top.green, base.green) << 8
                                    | mix(top.blue, base.blue))
    }

    /// `quad` at `alpha` over the card: translucent, or flattened under
    /// Reduce Transparency.
    private func wash(_ quad: NightPalette.Quad, _ alpha: Double) -> Color {
        guard reduceTransparency else { return color(quad).opacity(alpha) }
        return color(Self.flattened(quad.shade(variant), alpha: alpha, over: NightPalette.surface.shade(variant)))
    }

    // MARK: The card

    /// The card itself: Night's lit surface, at night.
    public var surface: Color { color(NightPalette.surface) }
    /// Wells on the card: the list of numbers, an opening not yet picked.
    public var raised: Color { color(NightPalette.surfaceRaised) }
    /// The wells' edges under Increase Contrast (opaque under Reduce
    /// Transparency).
    public var hairline: Color {
        reduceTransparency ? color(NightPalette.border) : color(NightPalette.hairline)
    }
    /// The card's lit edge.
    public var edge: Color {
        increasedContrast ? hairline : wash(NightPalette.lumen, 0.35)
    }

    // MARK: Text

    /// Titles, the typed sentence, the step names.
    public var ink: Color { color(NightPalette.ink) }
    /// Reading text: the note under the map.
    public var ink2: Color { color(NightPalette.ink2) }
    /// Captions: the other notes, the token IDs.
    public var ink3: Color { color(NightPalette.ink3) }
    /// The eyebrow, the step numbers, the tokens, the opening in the
    /// finished sentence.
    public var accentText: Color { color(NightPalette.accentText) }

    // MARK: Fills

    /// Lit edges: the token chips', the step numbers' wells'.
    public var lumen: Color { color(NightPalette.lumen) }
    /// `lumen` at `alpha` over the card: the token chips' and the step
    /// numbers' washes.
    public func lumenWash(_ alpha: Double) -> Color { wash(NightPalette.lumen, alpha) }
    /// The opening picked (white on it: 7.90:1, 9.93:1 under HC).
    public var prominent: Color { color(NightPalette.prominent) }
    public var accent: Color { color(NightPalette.accent) }
    public var violet: Color { color(NightPalette.violet) }

    // MARK: The map of meaning

    /// The map's panel, top to bottom (flat and deeper under HC).
    public var skyTop: Color { color(NightPalette.skyTop) }
    public var skyBottom: Color { color(NightPalette.skyBottom) }
    /// The words "bank" sits near, "bank" itself and the panel's captions.
    public var skyInk: Color { color(NightPalette.skyInk) }
    /// The other words on the map (solid under Reduce Transparency).
    public var skyInk2: Color {
        reduceTransparency ? color(NightPalette.skyInk2.darkHC) : color(NightPalette.skyInk2)
    }
    /// The lines from "bank" to its neighbours, and its trail.
    public var skyLink: Color { color(NightPalette.skyLink) }
    /// "bank"'s pill and the token the map follows, leading to trailing.
    public var bankStops: [Color] { NightPalette.skyBank.map(color) }

    /// A neighbourhood's glow at its peak (none under Increase Contrast or
    /// Reduce Transparency).
    public func glowAlpha(lit: Bool) -> Double {
        reduceTransparency ? 0 : NightPalette.skyGlowAlpha(lit: lit, variant)
    }

    /// Light on the card itself: its glows and stars (not under Increase
    /// Contrast or Reduce Transparency).
    public var lit: Bool { !increasedContrast && !reduceTransparency }
}
