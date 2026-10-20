import SwiftUI

/// Mercurius typography scale.
///
/// On iOS every style is built from a `Font.TextStyle` so it scales
/// automatically with the user's Dynamic Type setting — including the
/// accessibility sizes. On the Mac, which has no Dynamic Type, the styles are
/// the explicit sizes of `MacTypeRamp`. Never use `Font.system(size:)` for
/// reading text in features; route through this file so sizes stay
/// consistent and scale for users who need them to.
///
/// Note: the pre-iOS-16 workaround in this file (a `.with(relativeTo:)` helper
/// that silently returned `self`) was a no-op — Dynamic Type did NOT scale.
/// The `Font.system(_:design:weight:)` API used below is the supported path
/// from iOS 16 onward, which is below our iOS 17 deployment target.
public enum BrandFont {
    #if os(macOS)
    // The Mac's ramp: explicit sizes from `MacTypeRamp`. macOS gives SwiftUI
    // apps no Dynamic Type, and its text styles are sized for dense Mac UI
    // (body 13 pt, footnote 10 pt) — beside Merc's replies in the reading
    // face, the student's own words and every caption read a size smaller.
    // One ramp, in one place, keeps the whole window on one scale.
    public static let largeTitle = Font.system(size: MacTypeRamp.largeTitle, weight: .bold)
    public static let title = Font.system(size: MacTypeRamp.title, weight: .bold)
    public static let subheading = Font.system(size: MacTypeRamp.subheading, weight: .semibold)
    public static let body = Font.system(size: MacTypeRamp.body, weight: .regular)
    public static let bodyEmphasized = Font.system(size: MacTypeRamp.body, weight: .semibold)
    public static let caption = Font.system(size: MacTypeRamp.caption, weight: .regular)
    public static let mono = Font.system(size: MacTypeRamp.caption, weight: .regular, design: .monospaced)
    #else
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
    #endif
}

/// The Mac's type sizes, in points: the one place the Mac's text is sized.
/// `BrandFont` (and its rounded and reading companions) read them on macOS;
/// iOS keeps its Dynamic Type text styles.
///
/// Body is 15 pt — between the Mac's 13 pt UI text and the iPhone's 17 pt
/// reading text — and Merc's replies use the same size in the reading face
/// (`reading`), so a thread reads as one scale. Captions stay at 12 pt or
/// above: nothing a student has to read is set in the Mac's 10 pt footnote.
public enum MacTypeRamp {
    public static let largeTitle: CGFloat = 28
    public static let title: CGFloat = 22
    /// Prominent numbers (streak counts, XP).
    public static let title3: CGFloat = 18
    public static let subheading: CGFloat = 16
    public static let body: CGFloat = 15
    public static let caption: CGFloat = 12
    /// Merc's replies, in the reading face (`BrandFont.readingFace`).
    public static let reading: CGFloat = 15
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
