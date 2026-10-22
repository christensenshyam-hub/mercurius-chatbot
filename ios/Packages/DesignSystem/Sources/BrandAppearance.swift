import SwiftUI

/// Mercurius has one appearance: Night Studio's dark, on the iPhone and the
/// Mac alike (docs/ios-night-only/PR.md).
///
/// - Every scene root applies `colorScheme`, so SwiftUI draws dark whatever
///   the system or a student's old setting says.
/// - The iPhone's Info.plist also sets `UIUserInterfaceStyle = Dark`
///   (`ios/project.yml`), so the launch, the keyboard, alerts and the
///   system's share and print sheets are dark too, with no light flash.
/// - The Mac sets `NSApp.appearance` to Dark Aqua at launch
///   (`MacAppDelegate`), so its menus and panels follow.
///
/// The System / Light / Dark choice earlier versions offered is gone from
/// Settings; a stored choice (`ThemePreferenceStore`) is no longer read.
/// `BrandColor` holds Night's dark values on the iPhone whatever the trait
/// says, and Night's own colours on the Mac.
public enum BrandAppearance {
    /// The colour scheme of every window, sheet and preview host.
    public static let colorScheme: ColorScheme = .dark
}
