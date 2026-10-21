#if os(macOS)
import SwiftUI

/// The meaning sky's colours (Lesson 1.1's interactive, the map of
/// meaning): an instrument panel that is night in both appearances, so its
/// tokens don't follow the window's appearance, only Increase Contrast.
/// The values are `NightPalette`'s; `NightSkyContrastTests` checks every
/// word on it.
public enum NightSky {
    /// The panel, top to bottom (flat under Increase Contrast).
    public static let top = Night.color(NightPalette.skyTop)
    public static let bottom = Night.color(NightPalette.skyBottom)
    /// The words "bank" sits near, "bank" itself and the panel's captions.
    public static let ink = Night.color(NightPalette.skyInk)
    /// The other words.
    public static let ink2 = Night.color(NightPalette.skyInk2)
    /// The lines from "bank" to its neighbours, and its trail.
    public static let link = Night.color(NightPalette.skyLink)
    /// "bank"'s pill, leading to trailing.
    public static let bankStops: [Color] = NightPalette.skyBank.map(Night.color)

    /// A neighbourhood's glow at its peak (0 under Increase Contrast).
    public static func glowAlpha(lit: Bool, increasedContrast: Bool) -> Double {
        NightPalette.skyGlowAlpha(lit: lit, increasedContrast ? .darkHC : .dark)
    }
}
#endif
