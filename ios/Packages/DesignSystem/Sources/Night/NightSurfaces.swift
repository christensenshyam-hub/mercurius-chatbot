#if os(macOS)
import SwiftUI

// MARK: - The canvas (§2.4)

/// The background of a detail screen: an ink gradient, up to two pools of
/// light, and in dark mode a still star field. Under Increase Contrast it is
/// flat: no pools, no stars. Decoration only: hidden from VoiceOver and
/// never hit-tested.
public struct NightCanvas: View {
    public enum Pools: Sendable {
        /// Indigo at the top-trailing corner and violet at the leading edge
        /// (Today, the learning path, lesson complete).
        case both
        /// The indigo pool only (lesson, chat, unit check, the gate).
        case indigo
        /// Flat (the crisis view, errors that replace a screen).
        case flat
    }

    private let pools: Pools
    private let stars: Bool

    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    public init(pools: Pools = .both, stars: Bool = true) {
        self.pools = pools
        self.stars = stars
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let variant = NightPalette.Variant(dark: scheme == .dark, increasedContrast: night.increasedContrast)
            ZStack {
                if night.increasedContrast || pools == .flat {
                    Night.canvasTop
                } else {
                    LinearGradient(colors: [Night.canvasTop, Night.canvasBottom],
                                   startPoint: .top, endPoint: .bottom)
                    let indigo = Self.indigoPool(in: geo.size)
                    pool(Night.accent, alpha: NightPalette.poolAccentAlpha(variant),
                         at: indigo.center, radius: indigo.radius)
                    if pools == .both {
                        let violet = Self.violetPool(in: geo.size)
                        pool(Night.violet, alpha: NightPalette.poolVioletAlpha(variant),
                             at: violet.center, radius: violet.radius)
                    }
                    if stars && scheme == .dark {
                        NightStarField(count: Int(min(140, w * h / 9000)))
                    }
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Pool 1: indigo, centred at 85% of the width on the top edge.
    static func indigoPool(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: size.width * 0.85, y: 0), min(0.65 * size.width, 720))
    }

    /// Pool 2: violet, on the leading edge 55% down.
    static func violetPool(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: 0, y: size.height * 0.55), min(0.5 * size.width, 560))
    }

    private func pool(_ color: Color, alpha: Double, at center: CGPoint, radius: CGFloat) -> some View {
        // Fades to the same hue at zero, not to `.clear` (clear black would
        // grey the falloff).
        RadialGradient(colors: [color.opacity(alpha), color.opacity(0)],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }
}

// MARK: - Lit surfaces (§2.6)

/// How content sits on the canvas: an opaque fill, a 1 pt lit edge, and one
/// shadow on the shape, in light mode only (none in dark, none under
/// Increase Contrast, where the edge becomes a solid hairline).
struct NightLit: ViewModifier {
    let radius: CGFloat
    let fill: Color
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let castsShadow = scheme == .light && !night.increasedContrast
        content
            .background {
                shape.fill(fill)
                    .shadow(color: castsShadow ? Night.shadowInk : .clear, radius: 12, x: 0, y: 4)
            }
            .overlay { shape.strokeBorder(edge, lineWidth: 1).allowsHitTesting(false) }
    }

    private var edge: AnyShapeStyle {
        if night.increasedContrast { return AnyShapeStyle(Night.hairline) }
        let colors: [Color] = scheme == .dark
            ? [.white.opacity(0.14), .white.opacity(0.04), .white.opacity(0.02)]
            : [.white.opacity(0.9), Night.fixed(NightPalette.Shade(0x1B1F4B, alpha: 0.06)),
               Night.fixed(NightPalette.Shade(0x1B1F4B, alpha: 0.10))]
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }
}

public extension View {
    /// A lit surface (§2.6): Night's card.
    func nightLit(radius: CGFloat = Night.Radius.card, fill: Color = Night.surface) -> some View {
        modifier(NightLit(radius: radius, fill: fill))
    }
}

/// The KEY / Your turn wash (§2.6): `lumen` at 12% (light) or 16% (dark)
/// from the top-leading corner, fading out by 320 pt, inside the card's
/// shape. A glow, so none under Increase Contrast. Apply before
/// `nightLit`, so it sits over the surface and under the text.
struct NightWash: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    func body(content: Content) -> some View {
        content.background {
            if !night.increasedContrast {
                RadialGradient(colors: [Night.lumen.opacity(NightPalette.Tint.keyWash(dark: scheme == .dark)),
                                        Night.lumen.opacity(0)],
                               center: .topLeading, startRadius: 0, endRadius: 320)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

public extension View {
    /// The KEY / Your turn wash, inside a card of `radius` (§2.6).
    func nightWash(radius: CGFloat = Night.Radius.card) -> some View {
        modifier(NightWash(radius: radius))
    }
}

/// Today's Up next card's background: the **only** gradient fill in the app
/// (§2.5). The hero gradient, the lamp at Merc's corner, a few stars, a
/// light edge and its one shadow (light mode only). Under Increase Contrast:
/// the deeper stops, no lamp, no stars, no shadow.
public struct NightHeroSurface: View {
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    public init() {}

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.hero, style: .continuous)
        let castsShadow = scheme == .light && !night.increasedContrast
        ZStack {
            shape
                .fill(LinearGradient(colors: Night.heroStops, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: castsShadow ? Night.heroShadow : .clear, radius: 20, x: 0, y: 8)
            if !night.increasedContrast {
                RadialGradient(colors: [Night.heroLamp, Night.heroLamp.opacity(0)],
                               center: .topTrailing, startRadius: 0, endRadius: 300)
                    .clipShape(shape)
                NightStarField(count: 24, brightness: 0.9)
                    .clipShape(shape)
            }
            shape.strokeBorder(
                night.increasedContrast
                    ? AnyShapeStyle(Color.white.opacity(0.5))
                    : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06)],
                                                   startPoint: .top, endPoint: .bottom)),
                lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Floating chrome (§2.8)

/// Floating chrome: Liquid Glass on macOS 26 when built with Swift 6.2+; a
/// material under a 92% surface tint and a hairline on macOS 14–25, on every
/// CI build (Xcode 16.2), and under `-NightNoGlass`; an opaque surface and a
/// hairline under Reduce Transparency or Increase Contrast. Never for
/// content.
struct NightChrome<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    @NightSettings private var night

    func body(content: Content) -> some View {
        if night.opaqueChrome {
            content
                .background(Night.surface, in: shape)
                .overlay(shape.strokeBorder(Night.hairline, lineWidth: 1).allowsHitTesting(false))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *), !Night.debugForcesMaterial {
                content.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
            } else {
                material(content)
            }
            #else
            material(content)
            #endif
        }
    }

    private func material(_ content: Content) -> some View {
        content
            .background {
                shape.fill(.regularMaterial)
                    .overlay(shape.fill(Night.surface.opacity(NightPalette.chromeTint)))
            }
            .overlay(shape.strokeBorder(Night.hairline, lineWidth: 1).allowsHitTesting(false))
    }
}

public extension View {
    /// Floating chrome in `shape` (§2.8). `interactive` for buttons.
    func nightChrome<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(NightChrome(shape: shape, interactive: interactive))
    }
}

// MARK: - Window chrome (§2.8)

public extension View {
    /// The window toolbar's background: the system's Liquid Glass on macOS 26
    /// (built with Swift 6.2+), the canvas colour on macOS 14–25 and every CI
    /// build.
    @ViewBuilder
    func nightToolbarBackground() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !Night.debugForcesMaterial {
            self
        } else {
            nightToolbarFallback()
        }
        #else
        nightToolbarFallback()
        #endif
    }

    /// A window title bar with no toolbar of its own (the first-run gate):
    /// the canvas runs up under it, as in the shell, instead of a neutral
    /// band with a hairline. macOS 15 and later hide the bar's background;
    /// macOS 14 paints it the canvas colour.
    @ViewBuilder
    func nightCanvasTitleBar() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            nightToolbarFallback()
        }
    }

    private func nightToolbarFallback() -> some View {
        toolbarBackground(Night.canvasTop, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
    }

    /// A detail screen's canvas, mirrored under macOS 26's floating glass
    /// sidebar so the ink shows through it. Elsewhere (macOS 14–25, CI
    /// builds, `-NightNoGlass`, Reduce Transparency, Increase Contrast) the
    /// sidebar is opaque and the canvas stays in its column.
    @ViewBuilder
    func nightExtendsUnderSidebar(_ night: NightAccessibility) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !Night.debugForcesMaterial, !night.opaqueChrome {
            self.backgroundExtensionEffect()
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The sidebar's background: the system's glass sidebar on macOS 26 (built
    /// with Swift 6.2+); an opaque `Night.sidebar` on macOS 14–25, every CI
    /// build, `-NightNoGlass`, and under Reduce Transparency or Increase
    /// Contrast. Apply to the sidebar's `List`.
    @ViewBuilder
    func nightSidebarBackground(_ night: NightAccessibility) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !Night.debugForcesMaterial, !night.opaqueChrome {
            self
        } else {
            nightOpaqueSidebar()
        }
        #else
        nightOpaqueSidebar()
        #endif
    }

    private func nightOpaqueSidebar() -> some View {
        scrollContentBackground(.hidden)
            .background(Night.sidebar.ignoresSafeArea())
    }
}

// MARK: - Hover and focus (§4.2, §4.4)

/// A clickable lit surface or row under the pointer: a `lumen` 6% tint and a
/// 1 pt `accentText` 50% stroke on its shape, in 0.12 s (instant under
/// Reduce Motion). No scale, no lift, no pointing hand.
struct NightHover: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    @State private var hovering = false
    @NightSettings private var night

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                shape.fill(Night.lumen.opacity(NightPalette.Tint.hover))
                    .overlay(shape.strokeBorder(Night.accentText.opacity(0.5), lineWidth: 1))
                    .opacity(hovering && isEnabled ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(night.reduceMotion ? nil : Night.Motion.hover, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Night's own keyboard focus ring: 2 pt `focusRing` (3 pt under Increase
/// Contrast), 3 pt outside the shape and following it, shown while the view
/// has keyboard focus, with no animation. The system's rectangle is turned
/// off so it doesn't double it.
struct NightFocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    let color: Color
    @FocusState private var focused: Bool
    @NightSettings private var night

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                if focused {
                    shape
                        .inset(by: -3 - night.focusRingWidth / 2)
                        .stroke(color, lineWidth: night.focusRingWidth)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

public extension View {
    /// Night's hover for a clickable surface or row (§4.2).
    func nightHover(cornerRadius: CGFloat, isEnabled: Bool = true) -> some View {
        modifier(NightHover(cornerRadius: cornerRadius, isEnabled: isEnabled))
    }

    /// Night's focus ring around `shape` (§4.4). `color` is `focusRing`
    /// except on the hero, where it is white.
    func nightFocusRing<S: InsettableShape>(_ shape: S, color: Color = Night.focusRing) -> some View {
        modifier(NightFocusRing(shape: shape, color: color))
    }
}
#endif
