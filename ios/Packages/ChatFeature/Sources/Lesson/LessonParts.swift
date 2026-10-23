import Foundation

// A lesson reply's parts: the sections between Markdown thematic breaks
// ("---" on its own line), each with the blocks `BlockParser` finds in it.
// Shared by the Mac (Night Studio's part marks and strip) and the iPhone
// (where Lesson 1.1's interactive sits, `LessonInteractiveAnchor`). Pure and
// tested (NightReplyTextTests, TokenizerInteractiveTests). Reading the parts
// changes nothing that is drawn on the iPhone, sent or stored.

/// One part of a lesson: a section of one of Merc's replies, between
/// Markdown thematic-break lines ("---" on its own line).
struct LessonPart: Equatable {
    /// The section's blocks, in order (`BlockParser`'s, with the breaks
    /// taken out of the prose).
    var blocks: [MessageBlock]
    /// "Check" for a section with a [Q], else its first bold term when that
    /// is 32 characters or fewer, else nil ("Part 4").
    var name: String?
}

enum LessonParts {
    /// The longest a bold term may be and still name its part.
    static let maxNameLength = 32

    /// The parts in one reply. A section counts once something in it has
    /// arrived: whitespace-only sections are dropped, and so is a marker
    /// still being withheld mid-stream. While streaming, a last line that
    /// may yet become a break ("-", "--") is held back, so it never flashes
    /// as text.
    static func sections(of text: String, isStreaming: Bool) -> [LessonPart] {
        let source = isStreaming ? withholdingPartialBreak(text) : text
        var groups: [[MessageBlock]] = [[]]
        for block in BlockParser.parse(source) {
            guard case .prose(let prose) = block else {
                groups[groups.count - 1].append(block)
                continue
            }
            for (index, piece) in splitAtBreaks(prose).enumerated() {
                if index > 0 { groups.append([]) }
                if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    groups[groups.count - 1].append(.prose(piece))
                }
            }
        }
        return groups.filter { !$0.isEmpty }.map { LessonPart(blocks: $0, name: name(of: $0)) }
    }

    /// The prose between thematic-break lines. A break inside a fenced code
    /// block is code, not a break.
    static func splitAtBreaks(_ prose: String) -> [String] {
        var pieces: [String] = []
        var current: [Substring] = []
        var inFence = false
        for line in prose.split(separator: "\n", omittingEmptySubsequences: false) {
            if isFence(line) { inFence.toggle() }
            if !inFence, isThematicBreak(line) {
                pieces.append(current.joined(separator: "\n"))
                current = []
            } else {
                current.append(line)
            }
        }
        pieces.append(current.joined(separator: "\n"))
        return pieces
    }

    /// A Markdown thematic break: three or more "-", "*" or "_" (the same
    /// one), optionally spaced, indented at most three spaces.
    static func isThematicBreak(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let mark = trimmed.first, "-*_".contains(mark) else { return false }
        let leading = line.prefix { $0 == " " }.count
        guard leading <= 3 else { return false }
        var count = 0
        for character in trimmed {
            if character == mark { count += 1 } else if character != " " && character != "\t" { return false }
        }
        return count >= 3
    }

    static func isFence(_ line: Substring) -> Bool {
        let trimmed = line.drop { $0 == " " }
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// Drops a last line of one or two break characters ("-", "**") that a
    /// streaming reply may still turn into a break, a list or bold text.
    static func withholdingPartialBreak(_ text: String) -> String {
        guard let lastBreak = text.lastIndex(of: "\n") else {
            return isPartialBreak(Substring(text)) ? "" : text
        }
        let tail = text[text.index(after: lastBreak)...]
        return isPartialBreak(tail) ? String(text[...lastBreak]) : text
    }

    private static func isPartialBreak(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard (1...2).contains(trimmed.count), let mark = trimmed.first else { return false }
        return "-*_".contains(mark) && trimmed.allSatisfy { $0 == mark }
    }

    /// A part's name (SPEC §5.3.2).
    static func name(of blocks: [MessageBlock]) -> String? {
        if blocks.contains(where: { if case .quiz = $0 { return true } else { return false } }) {
            return "Check"
        }
        for block in blocks {
            let text: String
            switch block {
            case .prose(let s), .key(let s), .example(let s), .check(let s): text = s
            case .quiz: continue
            }
            if let term = firstBoldTerm(in: text) {
                return term.count <= maxNameLength ? term : nil
            }
        }
        return nil
    }

    /// The first `**bold**` (or `__bold__`) run in `text`, trimmed, without
    /// a trailing ":" or ".". Nil when there is none or it is empty.
    static func firstBoldTerm(in text: String) -> String? {
        let pattern = #"\*\*([^*\n]+?)\*\*|__([^_\n]+?)__"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: text) {
                var term = text[range].trimmingCharacters(in: .whitespaces)
                while let last = term.last, ":.,;".contains(last) { term.removeLast() }
                term = term.trimmingCharacters(in: .whitespaces)
                return term.isEmpty ? nil : term
            }
        }
        return nil
    }
}
