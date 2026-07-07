import SwiftUI

/// Rounded companion tokens for the "Duolingo-blueprint" surfaces.
///
/// ADDITIVE + OPT-IN. The base `BrandFont` ramp stays `.default` design and is
/// untouched — chat, lessons, settings, and every pinned snapshot keep their
/// typeface. Only the learning path, the gamified top bar, and the reshaped
/// profile opt into these `rounded*` tokens for the playful, gamified feel.
///
/// Like the base ramp, each token is built from a `Font.TextStyle`, so it scales
/// with Dynamic Type — including the accessibility sizes.
public extension BrandFont {
    /// Big playful display — the path hero, profile header. Scales from `.largeTitle`.
    static let roundedLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// Section / screen titles. Scales from `.title2`.
    static let roundedTitle = Font.system(.title2, design: .rounded, weight: .bold)

    /// Prominent numbers — XP, level, streak counts. Scales from `.title3`.
    static let roundedTitle3 = Font.system(.title3, design: .rounded, weight: .bold)

    /// Subheadings, unit banners, chip labels. Scales from `.headline`.
    static let roundedHeadline = Font.system(.headline, design: .rounded, weight: .semibold)

    /// Reading text on a rounded surface. Scales from `.body`.
    static let roundedBody = Font.system(.body, design: .rounded, weight: .regular)

    /// Emphasis on a rounded surface — button labels, node titles. Scales from `.body`.
    static let roundedBodyEmphasized = Font.system(.body, design: .rounded, weight: .semibold)

    /// Supporting text on a rounded surface. Scales from `.footnote`.
    static let roundedCaption = Font.system(.footnote, design: .rounded, weight: .semibold)
}
