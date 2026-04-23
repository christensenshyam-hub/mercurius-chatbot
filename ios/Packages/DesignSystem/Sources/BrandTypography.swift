import SwiftUI

/// Mercurius typography scale.
///
/// Every style is built from a `Font.TextStyle` so it scales automatically
/// with the user's Dynamic Type setting — including the accessibility sizes.
/// Never use `Font.system(size:)` for reading text in features; route through
/// this file so sizes stay consistent and scale for users who need them to.
///
/// Note: the pre-iOS-16 workaround in this file (a `.with(relativeTo:)` helper
/// that silently returned `self`) was a no-op — Dynamic Type did NOT scale.
/// The `Font.system(_:design:weight:)` API used below is the supported path
/// from iOS 16 onward, which is below our iOS 17 deployment target.
public enum BrandFont {
    /// Largest display text (onboarding headers, big empty states).
    /// Scales from `.largeTitle`.
    public static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)

    /// Screen / section titles. Scales from `.title2`.
    public static let title = Font.system(.title2, design: .default, weight: .bold)

    /// Subheadings and prominent labels. Scales from `.headline`.
    public static let subheading = Font.system(.headline, design: .default, weight: .semibold)

    /// Default reading text for body copy and messages. Scales from `.body`.
    public static let body = Font.system(.body, design: .default, weight: .regular)

    /// Emphasis within body text. Same scaling as `.body`, heavier weight.
    public static let bodyEmphasized = Font.system(.body, design: .default, weight: .semibold)

    /// Supporting text, timestamps, chip labels. Scales from `.footnote`.
    public static let caption = Font.system(.footnote, design: .default, weight: .regular)

    /// Small monospaced, used only for code fences. Scales from `.footnote`.
    public static let mono = Font.system(.footnote, design: .monospaced, weight: .regular)
}

/// Standard spacing scale. Use these instead of raw numbers.
public enum BrandSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

/// Corner radius scale.
public enum BrandRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 22
    public static let pill: CGFloat = 999
}
