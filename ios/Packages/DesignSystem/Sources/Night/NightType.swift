#if os(macOS)
import SwiftUI

/// Night Studio's type on the Mac (SPEC.md §3.1). Fixed sizes: a Mac has no
/// Dynamic Type, and nothing a student reads is under 12 pt.
///
/// - Lexend carries the voice (display, titles, reading). Only Regular and
///   SemiBold are bundled: no bold, no black, no SF Rounded.
/// - New York ("keep") carries what the student keeps or answers.
/// - SF Mono ("machine") carries machine text (token chips).
/// - The system face stays for the window's own chrome (sidebar, toolbar,
///   menus, the Settings window) and the crisis view.
public enum NightType {
    public enum Role: CaseIterable, Sendable {
        /// Lexend SemiBold 30, −0.75: the greeting, "Lesson complete", gate titles.
        case display
        /// Lexend SemiBold 24, −0.5: the hero's lesson title, a unit's title.
        case title
        /// Lexend SemiBold 19, −0.3: card headlines, a check's stem.
        case title2
        /// Lexend SemiBold 15: buttons, row titles.
        case headline
        /// Lexend Regular 15, line spacing 5: reading text.
        case body
        /// Lexend Regular 14, line spacing 3: secondary lines.
        case callout
        /// Lexend SemiBold 14: reply chips, the part strip.
        case calloutStrong
        /// Lexend Regular 12: metadata.
        case caption
        /// Lexend SemiBold 12, uppercase, +1.2: the one eyebrow style.
        case eyebrow
        /// New York Medium 18, line spacing 4: what the student keeps.
        case keep
        /// SF Mono Medium 14: token chips.
        case machine

        public var size: CGFloat {
            switch self {
            case .display: return 30
            case .title: return 24
            case .title2: return 19
            case .headline, .body: return 15
            case .callout, .calloutStrong, .machine: return 14
            case .caption, .eyebrow: return 12
            case .keep: return 18
            }
        }

        public var tracking: CGFloat {
            switch self {
            case .display: return -0.75
            case .title: return -0.5
            case .title2: return -0.3
            case .eyebrow: return 1.2
            default: return 0
            }
        }

        public var lineSpacing: CGFloat {
            switch self {
            case .title2: return 2
            case .body: return 5
            case .callout: return 3
            case .keep: return 4
            default: return 0
            }
        }

        var isSemibold: Bool {
            switch self {
            case .display, .title, .title2, .headline, .calloutStrong, .eyebrow: return true
            default: return false
            }
        }

        public var font: Font {
            switch self {
            case .keep: return NightType.keep(size)
            case .machine: return .system(size: size, weight: .medium, design: .monospaced)
            default: return NightType.lexend(size, semibold: isSemibold)
            }
        }
    }

    public static let display = Role.display.font
    public static let title = Role.title.font
    public static let title2 = Role.title2.font
    public static let headline = Role.headline.font
    public static let body = Role.body.font
    public static let callout = Role.callout.font
    public static let calloutStrong = Role.calloutStrong.font
    public static let caption = Role.caption.font
    public static let eyebrow = Role.eyebrow.font
    public static let keep = Role.keep.font
    public static let machine = Role.machine.font

    /// The keep face at another size (16 in the complete card's key list).
    public static func keep(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    /// Lexend at a fixed size, from the bundled faces (registered first).
    public static func lexend(_ size: CGFloat, semibold: Bool = false) -> Font {
        BrandFontRegistrar.registerReadingFonts()
        return .custom(semibold ? "Lexend-SemiBold" : "Lexend-Regular", fixedSize: size)
    }
}

public extension View {
    /// A Night type role: its face, size, tracking and line spacing.
    func nightFont(_ role: NightType.Role) -> some View {
        font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }
}
#endif
