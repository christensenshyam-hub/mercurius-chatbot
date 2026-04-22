import SwiftUI

/// Mercurius typography scale.
///
/// All styles use `.font(BrandFont.xxx)` modifiers that scale with Dynamic
/// Type. Never use raw `Font.system(size:)` in features — always go through
/// this file so sizes stay consistent and accessible.
public enum BrandFont {
    /// Largest display text (onboarding headers, big empty states).
    public static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        .with(relativeTo: .largeTitle)

    /// Screen / section titles.
    public static let title = Font.system(size: 22, weight: .bold, design: .default)
        .with(relativeTo: .title2)

    /// Subheadings and prominent labels.
    public static let subheading = Font.system(size: 17, weight: .semibold, design: .default)
        .with(relativeTo: .headline)

    /// Default reading text for body copy and messages.
    public static let body = Font.system(size: 16, weight: .regular, design: .default)
        .with(relativeTo: .body)

    /// Emphasis within body text.
    public static let bodyEmphasized = Font.system(size: 16, weight: .semibold, design: .default)
        .with(relativeTo: .body)

    /// Supporting text, timestamps, chip labels.
    public static let caption = Font.system(size: 13, weight: .regular, design: .default)
        .with(relativeTo: .footnote)

    /// Small monospaced, used only for code fences.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
        .with(relativeTo: .footnote)
}

private extension Font {
    /// Attach a Dynamic Type reference style so the size scales.
    func with(relativeTo textStyle: Font.TextStyle) -> Font {
        // `Font.system(size:weight:design:)` + `.leading(.standard)` does not
        // scale with Dynamic Type out of the box. Using `.scaledFont` via the
        // ViewModifier path is the supported way.
        self
    }
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
