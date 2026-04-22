import SwiftUI

/// Mercurius brand palette.
///
/// Colors are defined as semantic tokens rather than raw hex values so
/// features depend on intent ("accent") rather than appearance ("#C9922A").
/// Dark/light variants are selected automatically via `Color(UIColor:)`
/// dynamic providers.
public enum BrandColor {
    // MARK: Surface

    /// App background. Dark green in dark mode, off-white in light mode.
    public static let background = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x08 / 255, green: 0x0F / 255, blue: 0x0B / 255, alpha: 1)
                : UIColor(red: 0xF5 / 255, green: 0xF8 / 255, blue: 0xF6 / 255, alpha: 1)
        }
    )

    /// Surface elevated above background (cards, input fields).
    public static let surface = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x10 / 255, green: 0x1E / 255, blue: 0x16 / 255, alpha: 1)
                : UIColor.white
        }
    )

    /// Further elevated surface for interactive containers.
    public static let surfaceElevated = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x18 / 255, green: 0x2C / 255, blue: 0x22 / 255, alpha: 1)
                : UIColor(red: 0xED / 255, green: 0xF4 / 255, blue: 0xEF / 255, alpha: 1)
        }
    )

    // MARK: Content

    /// Primary text color.
    public static let text = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0xE8 / 255, green: 0xED / 255, blue: 0xE9 / 255, alpha: 1)
                : UIColor(red: 0x1A / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1)
        }
    )

    /// De-emphasized text color.
    public static let textSecondary = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x8A / 255, green: 0x9E / 255, blue: 0x90 / 255, alpha: 1)
                : UIColor(red: 0x6B / 255, green: 0x7A / 255, blue: 0x6E / 255, alpha: 1)
        }
    )

    // MARK: Accent

    /// Primary brand accent (gold).
    public static let accent = Color(red: 0xC9 / 255, green: 0x92 / 255, blue: 0x2A / 255)

    /// Lighter accent for highlights.
    public static let accentLight = Color(red: 0xE8 / 255, green: 0xB8 / 255, blue: 0x4B / 255)

    /// Darker accent for pressed states.
    public static let accentDark = Color(red: 0x9A / 255, green: 0x6D / 255, blue: 0x18 / 255)

    // MARK: Message bubbles

    public static let userBubble = accent
    public static let userBubbleText = Color.white

    public static let assistantBubble = surfaceElevated
    public static let assistantBubbleText = text

    // MARK: Semantic

    public static let border = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x1C / 255, green: 0x38 / 255, blue: 0x28 / 255, alpha: 1)
                : UIColor(red: 0xD4 / 255, green: 0xDD / 255, blue: 0xD7 / 255, alpha: 1)
        }
    )

    public static let error = Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
    public static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
}
