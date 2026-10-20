#if os(macOS)
import SwiftUI
import AppKit

/// Night Studio on the Mac: a deep ink-indigo canvas lit from within.
/// Content sits on solid "lit" surfaces (never glass), chrome floats (Liquid
/// Glass on macOS 26, a material before it), and light, not paint, carries
/// meaning. `docs/mac-night-studio/SPEC.md` is the source for every value.
///
/// Mac only. On the Mac `BrandColor` reads these tokens too (§2.2), so the
/// shared views take the Night palette without per-view edits; iOS keeps
/// today's palette.
///
/// Every colour follows the window's appearance, and Increase Contrast
/// (§2.1): each token is an `NSColor` whose provider picks one of four
/// values (`NightPalette`).
public enum Night {
    // MARK: Surfaces

    /// The canvas at the top of a detail screen.
    public static let canvasTop = color(NightPalette.canvasTop)
    /// The canvas at the bottom (a little deeper).
    public static let canvasBottom = color(NightPalette.canvasBottom)
    /// A lit surface: cards, the check, the complete card.
    public static let surface = color(NightPalette.surface)
    /// One step up: answer rows, inner wells.
    public static let surfaceRaised = color(NightPalette.surfaceRaised)
    /// The sidebar's opaque fill where it isn't system glass.
    public static let sidebar = color(NightPalette.sidebar)
    /// Strokes, separators, unlit segments (translucent).
    public static let hairline = color(NightPalette.hairline)
    /// `hairline` flattened over `surface` (opaque).
    public static let border = color(NightPalette.border)

    // MARK: Text

    public static let ink = color(NightPalette.ink)
    public static let ink2 = color(NightPalette.ink2)
    /// Captions and metadata only.
    public static let ink3 = color(NightPalette.ink3)
    /// Eyebrows, links, selected glyphs, the focus ring.
    public static let accentText = color(NightPalette.accentText)
    public static let successText = color(NightPalette.successText)
    public static let errorText = color(NightPalette.errorText)

    // MARK: Fills and light

    public static let accent = color(NightPalette.accent)
    public static let violet = color(NightPalette.violet)
    /// The lamp: glows, lit edges, washes.
    public static let lumen = color(NightPalette.lumen)
    public static let success = color(NightPalette.success)
    public static let error = color(NightPalette.error)
    /// The one prominent button per screen.
    public static let prominent = color(NightPalette.prominent)
    public static let prominentHover = color(NightPalette.prominentHover)
    public static let prominentPressed = color(NightPalette.prominentPressed)
    /// A text field's boundary.
    public static let fieldStroke = color(NightPalette.fieldStroke)
    /// Keyboard focus.
    public static let focusRing = accentText

    /// The hero's three stops. Only `NightHeroSurface` draws them.
    static let heroStops: [Color] = NightPalette.hero.map(color)
    static let heroLamp = color(NightPalette.heroLamp)
    /// Secondary text on the hero (white 92%; solid under HC).
    public static let heroSecondary = color(NightPalette.heroSecondary)

    static let shadowInk = fixed(NightPalette.shadowInk)
    static let heroShadow = fixed(NightPalette.heroShadow)

    /// The brand light for progress strokes 6 pt or thinner (the week ring,
    /// the unit meter, the path thread): indigo to violet. Flat `accentText`
    /// under Increase Contrast (§2.1).
    public static func progressLight(increasedContrast: Bool) -> AnyShapeStyle {
        if increasedContrast { return AnyShapeStyle(accentText) }
        return AnyShapeStyle(LinearGradient(colors: [accent, violet], startPoint: .leading, endPoint: .trailing))
    }

    // MARK: Shape and space (§2.7)

    public enum Radius {
        /// Today's Up next, the lesson-complete card.
        public static let hero: CGFloat = 24
        /// Lit cards.
        public static let card: CGFloat = 18
        /// Answer rows, rows inside cards, source chips.
        public static let row: CGFloat = 12
        /// Token chips.
        public static let chip: CGFloat = 8
    }

    public enum Space {
        /// The page gutter when the detail column is 900 pt or wider.
        public static let gutterWide: CGFloat = 32
        /// The page gutter below that.
        public static let gutter: CGFloat = 24
        /// Between sections.
        public static let section: CGFloat = 24
        /// Inside a stack.
        public static let stack: CGFloat = 12
        /// Inside a lit card.
        public static let card: CGFloat = 20
        /// Inside the hero.
        public static let hero: CGFloat = 24
        /// A row's padding.
        public static let rowHorizontal: CGFloat = 14
        public static let rowVertical: CGFloat = 10

        /// The page gutter for a detail column this wide.
        public static func pageGutter(forWidth width: CGFloat) -> CGFloat {
            width >= 900 ? gutterWide : gutter
        }
    }

    // MARK: Tints (§2.3: each one's contrast is computed)

    /// The alphas of Night's tinted surfaces, for views outside this module.
    /// `NightContrastTests` checks text on each.
    public enum Tint {
        /// A picked answer row: `accent` over `surface`.
        public static func selected(dark: Bool) -> Double { NightPalette.Tint.selected(dark: dark) }
        /// The student's turn: `accent` over the canvas.
        public static func student(dark: Bool) -> Double { NightPalette.Tint.student(dark: dark) }
        /// The student's turn's edge: `lumen`.
        public static func studentEdge(dark: Bool) -> Double { dark ? 0.30 : 0.18 }
        /// The KEY / Your turn wash: `lumen` from the top-leading corner.
        public static func keyWash(dark: Bool) -> Double { NightPalette.Tint.keyWash(dark: dark) }
        /// Correct and wrong rows: `success` / `error` over `surface`.
        public static let answer = NightPalette.Tint.answer
        /// Hover on a clickable lit surface: `lumen` over it.
        public static let hover = NightPalette.Tint.hover
        /// A source chip's icon well: `lumen` over `surface`.
        public static let well = 0.14
    }

    // MARK: Motion (§4.1)

    public enum Motion {
        /// Selecting an answer, toggles, a highlight moving.
        public static let tap = Animation.snappy(duration: 0.2)
        /// Reveals, a card appearing, a check locking in.
        public static let layout = Animation.smooth(duration: 0.35)
        /// The lesson-complete card's arrival and Merc's celebrate only.
        public static let milestone = Animation.spring(duration: 0.6, bounce: 0.25)
        /// Everything, under Reduce Motion.
        public static let fade = Animation.easeInOut(duration: 0.2)
        /// Hover tints.
        public static let hover = Animation.easeOut(duration: 0.12)

        /// `animation`, or the crossfade under Reduce Motion.
        public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? fade : animation
        }
    }

    // MARK: DEBUG overrides (§8.4)
    //
    // The screenshot harness can't flip the Mac's own accessibility settings
    // (they're the founder's), and SwiftUI's environment values for them are
    // read-only, so DEBUG builds take launch overrides. Each flag carries a
    // value: `-NightContrast increased`, `-NightReduceTransparency YES`,
    // `-NightReduceMotion YES`, `-NightNoGlass YES`.

    /// `-NightContrast increased`: the Increase Contrast tokens and variants.
    public static let debugIncreasedContrast: Bool = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "NightContrast") == "increased"
        #else
        return false
        #endif
    }()

    /// `-NightReduceTransparency YES`: the opaque chrome.
    public static let debugReduceTransparency: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "NightReduceTransparency")
        #else
        return false
        #endif
    }()

    /// `-NightReduceMotion YES`: the Reduce Motion fallbacks.
    public static let debugReduceMotion: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "NightReduceMotion")
        #else
        return false
        #endif
    }()

    /// `-NightNoGlass YES`: the macOS 14–25 (and every CI build's) material
    /// fallback, drawn on macOS 26, so it can be reviewed and photographed.
    public static let debugForcesMaterial: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "NightNoGlass")
        #else
        return false
        #endif
    }()

    // MARK: Building colours

    /// A token as a SwiftUI colour that follows the drawing appearance.
    static func color(_ quad: NightPalette.Quad) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(quad.shade(variant(for: appearance)))
        })
    }

    /// One fixed shade (shadows).
    static func fixed(_ shade: NightPalette.Shade) -> Color {
        Color(.sRGB, red: shade.red, green: shade.green, blue: shade.blue, opacity: shade.alpha)
    }

    static func nsColor(_ shade: NightPalette.Shade) -> NSColor {
        NSColor(srgbRed: CGFloat(shade.red), green: CGFloat(shade.green), blue: CGFloat(shade.blue),
                alpha: CGFloat(shade.alpha))
    }

    /// The variant `appearance` draws in (`NightPalette.variant`).
    static func variant(for appearance: NSAppearance) -> NightPalette.Variant {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua,
                                                .accessibilityHighContrastAqua,
                                                .accessibilityHighContrastDarkAqua])
        let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let highContrastName = match == .accessibilityHighContrastAqua
            || match == .accessibilityHighContrastDarkAqua
        return NightPalette.variant(appearanceIsDark: dark,
                                    appearanceIsHighContrast: highContrastName,
                                    systemIncreasesContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                    forcedIncreasedContrast: debugIncreasedContrast)
    }
}

// MARK: - The accessibility settings Night reads

/// The three settings that change how Night draws (§2.9): the system's, or
/// the DEBUG launch overrides.
public struct NightAccessibility: Equatable, Sendable {
    /// Increase Contrast: the HC tokens; no pools, stars, glows or shadows;
    /// solid edges; opaque chrome; a 3 pt focus ring.
    public var increasedContrast: Bool
    /// Reduce Transparency: opaque chrome.
    public var reduceTransparency: Bool
    /// Reduce Motion: crossfades, a still Merc, instant scrolls.
    public var reduceMotion: Bool

    public init(increasedContrast: Bool, reduceTransparency: Bool, reduceMotion: Bool) {
        self.increasedContrast = increasedContrast
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
    }

    /// Chrome is opaque (`surface` + `hairline`) rather than glass or a
    /// material.
    public var opaqueChrome: Bool { increasedContrast || reduceTransparency }

    /// The focus ring's width.
    public var focusRingWidth: CGFloat { increasedContrast ? 3 : 2 }

    /// `animation`, or the crossfade under Reduce Motion.
    public func animation(_ animation: Animation) -> Animation {
        Night.Motion.resolved(animation, reduceMotion: reduceMotion)
    }
}

/// Reads the Night accessibility settings in any view, sheet or window:
/// SwiftUI's own environment values (which re-render the view when the
/// system setting changes) OR the DEBUG overrides.
///
///     @NightSettings private var night
///     … if night.increasedContrast { … }
@propertyWrapper
public struct NightSettings: DynamicProperty {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var wrappedValue: NightAccessibility {
        NightAccessibility(
            increasedContrast: contrast == .increased || Night.debugIncreasedContrast,
            reduceTransparency: reduceTransparency || Night.debugReduceTransparency,
            reduceMotion: reduceMotion || Night.debugReduceMotion
        )
    }
}
#endif
