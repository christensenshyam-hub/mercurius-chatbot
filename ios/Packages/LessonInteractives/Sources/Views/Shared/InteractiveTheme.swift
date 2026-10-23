import SwiftUI
import DesignSystem

/// The styling hooks: one set of roles (colours, type, spacing, targets and
/// the accessibility settings) that every shared block and card draws
/// with, filled per platform. The card shell computes it and hands it down
/// (`\.interactiveTheme`), so a card's view never asks which platform it is
/// on to pick a colour or a font.
///
/// - **iPhone:** today's lesson design. The card is a night-sky island
///   (`NightSkyCard`: Night's dark values, the same in the app's light and
///   dark appearances, HC values under Increase Contrast, solid under
///   Reduce Transparency), with the iPhone's type (`BrandFont`, Dynamic
///   Type), spacing (`BrandSpacing`) and 44 pt targets.
/// - **Mac:** Night Studio's tokens (`Night`, adaptive light and dark), its
///   fixed type ramp (`nightFont`), 36 pt controls and its focus ring.
///
/// Every text colour here reads at 4.5:1 or better on `surface` and
/// `raised` (`NightSkyCardContrastTests` and Night's palette tests), and
/// white reads at 4.5:1 or better on `prominent`. Use only these roles.
public struct InteractiveTheme: Equatable, Sendable {
    public enum Platform: Equatable, Sendable { case phone, mac }

    public let platform: Platform
    public let increasedContrast: Bool
    public let reduceTransparency: Bool
    public let reduceMotion: Bool
    /// The accessibility text sizes (iPhone): charts, grids and arrays are
    /// drawn as text or tables, and decoration goes. Never on the Mac.
    public let usesTables: Bool

    // MARK: Colours
    /// Titles and the main numbers.
    public let ink: Color
    /// Reading text.
    public let ink2: Color
    /// Captions and labels' secondary text.
    public let ink3: Color
    /// The eyebrow, step numbers, a picked item's words.
    public let accentText: Color
    /// The card.
    public let surface: Color
    /// Wells on the card: a chip not yet picked, a counter, a reveal.
    public let raised: Color
    /// A picked chip, the main button (white on it).
    public let prominent: Color
    /// Edges of wells and chips under Increase Contrast.
    public let hairline: Color
    /// The card's own edge.
    public let edge: Color
    /// Lit edges and washes.
    public let lumen: Color
    /// The keyboard focus ring (the Mac).
    public let focusRing: Color

    // MARK: Metrics
    /// The smallest a control may be: 44 pt on the iPhone, 36 pt on the Mac.
    public let minTarget: CGFloat
    /// Between the card's sections (header, prediction, control, reveal).
    public let sectionSpacing: CGFloat
    /// Between rows inside a section.
    public let rowSpacing: CGFloat
    /// Between chips.
    public let chipSpacing: CGFloat
    /// The card's inner padding.
    public let padding: CGFloat

    private let sky: NightSkyCard

    /// Light on the card (glows, stars): not under Increase Contrast or
    /// Reduce Transparency.
    public var lit: Bool { !increasedContrast && !reduceTransparency }

    /// The keyboard ring's width (the Mac): 3 pt under Increase Contrast.
    public var focusRingWidth: CGFloat { increasedContrast ? 3 : 2 }

    /// `lumen` at `alpha` over the card (solid under Reduce Transparency on
    /// the iPhone).
    public func wash(_ alpha: Double) -> Color {
        platform == .phone ? sky.lumenWash(alpha) : lumen.opacity(alpha)
    }

    /// A well's or chip's edge: solid under Increase Contrast.
    public var wellEdge: Color {
        increasedContrast ? hairline : ink3.opacity(0.5)
    }

    /// `animation`, or the crossfade under Reduce Motion.
    public func animation(_ animation: Animation) -> Animation {
        InteractiveMotion.animation(animation, reduceMotion: reduceMotion)
    }

    /// How a piece arrives (a fade only, under Reduce Motion).
    public func transition(edge: Edge = .bottom) -> AnyTransition {
        InteractiveMotion.transition(reduceMotion: reduceMotion, edge: edge)
    }

    // MARK: The two platforms

    /// The iPhone's night-sky card.
    public static func phone(increasedContrast: Bool, reduceTransparency: Bool, reduceMotion: Bool,
                             typeSize: DynamicTypeSize) -> InteractiveTheme {
        let sky = NightSkyCard(increasedContrast: increasedContrast, reduceTransparency: reduceTransparency)
        let large = typeSize.isAccessibilitySize
        return InteractiveTheme(
            platform: .phone, increasedContrast: increasedContrast, reduceTransparency: reduceTransparency,
            reduceMotion: reduceMotion, usesTables: InteractiveLayout.usesTables(typeSize),
            ink: sky.ink, ink2: sky.ink2, ink3: sky.ink3, accentText: sky.accentText,
            surface: sky.surface, raised: sky.raised, prominent: sky.prominent, hairline: sky.hairline,
            edge: sky.edge, lumen: sky.lumen, focusRing: sky.accentText,
            minTarget: InteractiveLayout.phoneMinTarget,
            sectionSpacing: large ? BrandSpacing.xxl : BrandSpacing.xl,
            rowSpacing: BrandSpacing.md, chipSpacing: BrandSpacing.sm,
            padding: InteractiveLayout.phonePadding, sky: sky
        )
    }

    #if os(macOS)
    /// The Mac's Night Studio card.
    public static func mac(_ night: NightAccessibility) -> InteractiveTheme {
        InteractiveTheme(
            platform: .mac, increasedContrast: night.increasedContrast,
            reduceTransparency: night.reduceTransparency, reduceMotion: night.reduceMotion, usesTables: false,
            ink: Night.ink, ink2: Night.ink2, ink3: Night.ink3, accentText: Night.accentText,
            surface: Night.surface, raised: Night.surfaceRaised, prominent: Night.prominent,
            hairline: Night.hairline, edge: Night.hairline, lumen: Night.lumen, focusRing: Night.focusRing,
            minTarget: InteractiveLayout.macMinTarget, sectionSpacing: 22, rowSpacing: 12, chipSpacing: 8,
            padding: InteractiveLayout.macPadding,
            sky: NightSkyCard(increasedContrast: night.increasedContrast, reduceTransparency: night.reduceTransparency)
        )
    }
    #endif

    /// The platform's theme with no accessibility setting on.
    public static var standard: InteractiveTheme {
        #if os(macOS)
        mac(NightAccessibility(increasedContrast: false, reduceTransparency: false, reduceMotion: false))
        #else
        phone(increasedContrast: false, reduceTransparency: false, reduceMotion: false, typeSize: .large)
        #endif
    }
}

private struct InteractiveThemeKey: EnvironmentKey {
    static let defaultValue = InteractiveTheme.standard
}

extension EnvironmentValues {
    /// The card's theme, set by `InteractiveCardShell` (and the gallery).
    public var interactiveTheme: InteractiveTheme {
        get { self[InteractiveThemeKey.self] }
        set { self[InteractiveThemeKey.self] = newValue }
    }
}

// MARK: - Type

/// A card's text roles, drawn in each platform's type: the iPhone's
/// Dynamic Type styles (they scale to AX5), the Mac's fixed Night ramp.
public enum InteractiveTextRole: Sendable {
    /// The card's title.
    case title
    /// A step's or section's name; a prediction's question.
    case heading
    /// Reading text.
    case body
    /// Notes, prompts, a reveal's result.
    case callout
    /// A chip's or button's label.
    case calloutStrong
    /// Labels and captions (never under 12 pt on the Mac).
    case caption
    /// The uppercase eyebrow ("INTERACTIVE"); uppercase the text yourself.
    case eyebrow
    /// A counter's number.
    case number
    /// Machine text (a token, a code).
    case machine
}

public extension View {
    /// This text in the card's type for `role`.
    func interactiveText(_ role: InteractiveTextRole) -> some View {
        modifier(InteractiveTextModifier(role: role))
    }
}

struct InteractiveTextModifier: ViewModifier {
    let role: InteractiveTextRole
    #if os(iOS)
    @ScaledMetric(relativeTo: .caption2) private var eyebrowSize: CGFloat = 11
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        switch role {
        case .title: content.nightFont(.title2)
        case .heading: content.nightFont(.headline)
        case .body: content.nightFont(.body)
        case .callout: content.nightFont(.callout)
        case .calloutStrong: content.nightFont(.calloutStrong)
        case .caption: content.nightFont(.caption)
        case .eyebrow: content.nightFont(.eyebrow)
        case .number: content.font(NightType.lexend(26, semibold: true)).monospacedDigit()
        case .machine: content.nightFont(.machine)
        }
        #else
        switch role {
        case .title: content.font(BrandFont.roundedTitle3)
        case .heading: content.font(BrandFont.roundedHeadline)
        case .body: content.font(BrandFont.body)
        case .callout: content.font(.callout)
        case .calloutStrong: content.font(.system(.callout, design: .rounded, weight: .semibold))
        case .caption: content.font(BrandFont.caption)
        case .eyebrow: content.font(.system(size: eyebrowSize, weight: .heavy, design: .rounded)).tracking(1.2)
        case .number: content.font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
        case .machine: content.font(.system(.callout, design: .monospaced))
        }
        #endif
    }
}
