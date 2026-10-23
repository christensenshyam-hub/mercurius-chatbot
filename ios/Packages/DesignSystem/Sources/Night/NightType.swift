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

/// Night's typographic pass for prose the app draws (Merc's replies, the
/// curriculum's lines): straight quotes become curly ones, which Lexend
/// draws as quotes rather than inch marks. Code is left alone: fenced
/// blocks, `inline code`, and Markdown link destinations stay byte for
/// byte. Never applied to what the student typed.
public enum NightTypography {
    public static func curlQuotes(_ text: String) -> String {
        guard text.contains("\"") || text.contains("'") else { return text }
        var lines: [String] = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                lines.append(String(line))
            } else {
                lines.append(inFence ? String(line) : curlLine(Array(line)))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func curlLine(_ chars: [Character]) -> String {
        var out = ""
        // The last character that decides a quote's side; emphasis marks
        // ("*", "_") are looked through.
        var previous: Character?
        var index = 0
        while index < chars.count {
            let c = chars[index]
            // `code`: copied as it is, to the run of backticks that closes it.
            if c == "`" {
                var run = 0
                while index + run < chars.count, chars[index + run] == "`" { run += 1 }
                var close = index + run
                var found = false
                while close < chars.count {
                    if chars[close] == "`" {
                        var closing = 0
                        while close + closing < chars.count, chars[close + closing] == "`" { closing += 1 }
                        if closing == run {
                            found = true
                            close += closing
                            break
                        }
                        close += closing
                    } else {
                        close += 1
                    }
                }
                let end = found ? close : index + run
                out += String(chars[index..<end])
                previous = chars[end - 1]
                index = end
                continue
            }
            // "](destination)": the address stays as written.
            if c == "(", index > 0, chars[index - 1] == "]", let close = chars[index...].firstIndex(of: ")") {
                out += String(chars[index...close])
                previous = ")"
                index = close + 1
                continue
            }
            switch c {
            case "\"":
                out.append(opens(after: previous) ? "“" : "”")
            case "'":
                if let previous, previous.isLetter || previous.isNumber {
                    out.append("’")
                } else {
                    out.append(opens(after: previous) ? "‘" : "’")
                }
            default:
                out.append(c)
            }
            if c != "*" && c != "_" { previous = c }
            index += 1
        }
        return out
    }

    /// A quote opens at the start, after a space, or after an opening mark.
    private static func opens(after previous: Character?) -> Bool {
        guard let previous else { return true }
        return previous.isWhitespace || "([{—–-/“‘".contains(previous)
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
