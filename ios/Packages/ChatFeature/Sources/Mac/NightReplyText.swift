#if os(macOS)
import Foundation
import AppKit
import CoreGraphics
import NetworkingKit

// Night Studio on the Mac (SPEC.md §5.3–§5.4): how Merc's reply text is read
// before it is drawn. Everything here is pure and tested (NightReplyTextTests):
// the parts a lesson is split into, the sources Merc cites, the closing
// question that becomes "Your turn", the crisis guard, and the token line an
// example card may draw. None of it changes what is sent or stored: the
// reply's text stays exactly what the server streamed, and Copy, Report and
// VoiceOver still read it through `BlockParser.plainText`.

// MARK: - Parts

/// One part of a lesson: a section of one of Merc's replies, between
/// Markdown thematic-break lines ("---" on its own line).
struct NightSection: Equatable {
    /// The section's blocks, in order (`BlockParser`'s, with the breaks
    /// taken out of the prose).
    var blocks: [MessageBlock]
    /// "Check" for a section with a [Q], else its first bold term when that
    /// is 32 characters or fewer, else nil ("Part 4").
    var name: String?
}

/// A part of the lesson thread so far, for the part strip.
struct NightPartInfo: Equatable, Identifiable {
    /// 1-based, counted across the whole thread, only over parts that exist.
    let number: Int
    let name: String?
    var id: Int { number }
}

enum NightParts {
    /// The longest a bold term may be and still name its part.
    static let maxNameLength = 32

    /// The parts in one reply. A section counts once something in it has
    /// arrived: whitespace-only sections are dropped, and so is a marker
    /// still being withheld mid-stream. While streaming, a last line that
    /// may yet become a break ("-", "--") is held back, so it never flashes
    /// as text.
    static func sections(of text: String, isStreaming: Bool) -> [NightSection] {
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
        return groups.filter { !$0.isEmpty }.map { NightSection(blocks: $0, name: name(of: $0)) }
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

/// The lesson thread's parts so far: where each reply's numbering starts,
/// and every part's number and name, for the strip.
struct NightPartPlan: Equatable {
    var starts: [UUID: Int] = [:]
    var parts: [NightPartInfo] = []

    /// Counts across the thread, in order, over Merc's replies only. A
    /// reply that failed before any text has no parts.
    static func make(_ messages: [ChatMessage], sections: (ChatMessage) -> [NightSection]) -> NightPartPlan {
        var plan = NightPartPlan()
        var next = 1
        for message in messages where message.role == .assistant {
            plan.starts[message.id] = next
            for section in sections(message) {
                plan.parts.append(NightPartInfo(number: next, name: section.name))
                next += 1
            }
        }
        return plan
    }
}

/// Splits each reply into parts once per change of its text (a lesson
/// thread re-renders on every streamed delta), and the thread's plan once
/// per change of the thread.
@MainActor
final class NightPartIndex {
    private struct Entry {
        let content: String
        let isStreaming: Bool
        let sections: [NightSection]
    }

    private struct Key: Equatable {
        let id: UUID
        let length: Int
        let isStreaming: Bool
    }

    private var entries: [UUID: Entry] = [:]
    private var planKey: [Key] = []
    private var lastPlan = NightPartPlan()

    func sections(for message: ChatMessage) -> [NightSection] {
        guard message.role == .assistant else { return [] }
        let streaming = message.status == .streaming
        if let entry = entries[message.id], entry.isStreaming == streaming, entry.content == message.content {
            return entry.sections
        }
        let sections = NightParts.sections(of: message.content, isStreaming: streaming)
        entries[message.id] = Entry(content: message.content, isStreaming: streaming, sections: sections)
        return sections
    }

    func plan(for messages: [ChatMessage]) -> NightPartPlan {
        let key = messages.map { Key(id: $0.id, length: $0.content.utf8.count, isStreaming: $0.status == .streaming) }
        if key == planKey { return lastPlan }
        planKey = key
        let ids = Set(messages.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        lastPlan = NightPartPlan.make(messages) { sections(for: $0) }
        return lastPlan
    }
}

/// Where the lesson's part marks sit in the list (0 is the top of the
/// reading area), for the strip's "now reading". A class, so every scroll
/// frame can update it without re-rendering the list.
@MainActor
final class NightPartMarks {
    var positions: [Int: CGFloat] = [:]

    /// How far below the top of the reading area a mark may sit and still
    /// count as reached (a jump puts it at 0; this allows for its padding).
    static let reachedLine: CGFloat = 48

    /// The part being read: the last whose mark has reached the top of the
    /// reading area, else part 1. At the end of the thread, the last part
    /// with its mark in view (a short last part never reaches the top).
    func current(partCount: Int, viewportHeight: CGFloat, atBottom: Bool = false) -> Int {
        let line = atBottom ? max(viewportHeight, 1) : Self.reachedLine
        var current = 1
        for (number, minY) in positions where number <= partCount && minY <= line && number > current {
            current = number
        }
        return current
    }
}

// MARK: - Sources

/// A source Merc cited, from "[SOURCE: label — domain/path]" (what the
/// server sends today) or from the plain-text forms the server writes for
/// blocks_v1 clients once PR #46 is live ("Source: label (domain)",
/// "(Source: label, domain)"). The chip shows the domain only.
struct NightSource: Equatable, Hashable {
    /// The title as Merc wrote it, without surrounding quotes. May be empty
    /// when the tag was only an address.
    let label: String
    /// "dl.acm.org", nil when the tag had no address.
    let domain: String?
    /// The address's path ("/doi/10.1145/…"), raw tags only. Kept for the
    /// record, never opened: the model often invents it (AUD-38).
    let path: String?

    /// What the chip's title says.
    var title: String { label.isEmpty ? (domain ?? "") : label }

    /// Where the chip opens: `https://<domain>` only, when that passes
    /// `ReplyLinkPolicy` (https, a host, no credentials). The path the model
    /// wrote is dropped, as the server's own rewrite drops it: the audit
    /// found invented deep links (two runs, two made-up CourtListener
    /// dockets). Nil keeps the chip an inert citation.
    var url: URL? {
        guard let domain else { return nil }
        return URL(string: "https://\(domain)").flatMap { ReplyLinkPolicy.allows($0) ? $0 : nil }
    }

    /// The plain-text form, as the server's rewrite writes it (for a reply
    /// shown plainly, under the crisis guard).
    var plainText: String {
        if !label.isEmpty, let domain { return "Source: \(label) (\(domain))" }
        return "Source: \(label.isEmpty ? (domain ?? "") : label)"
    }
}

/// A run of a reply's prose with its sources taken out: the Markdown to
/// draw, and the chips that follow it.
enum NightProseSegment: Equatable {
    case markdown(String)
    case source(NightSource)
}

enum NightSourceParser {
    static let openTag = "[SOURCE:"
    /// The longest raw tag held, "[" through "]" (the server's bound).
    static let maxTagLength = 400

    private static let host = #"(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,24}"#
    /// scheme? www.? host (port)? (path)?  — groups: host, path.
    private static let address = #"(?:https?://)?(?:www\.)?("# + host + #")(?::\d{2,5})?([/?#]\S*)?"#

    private static let addressOnly = regex("^" + address + "$")
    private static let labelSeparatorAddress = regex(#"^(.*?)(?:\s*[—–]\s*|\s+-\s+|:\s+|,\s+|\s+\|\s+)"# + address + "$")
    private static let labelParenAddress = regex(#"^(.*?)\s*\(\s*"# + address + #"\s*\)$"#)
    private static let labelSpaceAddress = regex(#"^(.*\S)\s+(?:https?://)?(?:www\.)?("# + host + #")(?::\d{2,5})?([/?#]\S*)$"#)
    private static let labelSpaceScheme = regex(#"^(.*\S)\s+https?://(?:www\.)?("# + host + #")(?::\d{2,5})?([/?#]\S*)?$"#)
    private static let hostOnly = regex("^" + host + "$")

    /// "Source: label (domain)" as a whole line, the domain closing it.
    private static let standaloneWithDomain = regex(#"^Source:\s+([^\n]{1,240}?)\s*\(("# + host + #")\)\s*$"#)
    /// "… sentence. Source: label (domain)" with the domain closing the
    /// line. The label can't hold a question mark: a question is prose.
    private static let trailingWithDomain = regex(#"([.!?…:]["'”’)*_]*)[ \t]+Source:\s+([^\n?]{1,240}?)\s*\(("# + host + #")\)[ \t]*$"#)
    /// "(Source: label, domain)" or "(Source: label)" anywhere.
    private static let inline = regex(#"\(Source:\s+((?:[^()\n]|\([^()\n]*\))*?)\)"#)
    /// A Markdown link's destination right after a raw tag's "]": "(http://
    /// d.org)". The server's LINK_DEST_RE (lib/sourceTags.js): an address,
    /// no spaces, optional angle brackets. Group 1: the host.
    private static let linkDestination = regex(#"^\(<?(?:https?://)?(?:www\.)?("# + host + #")(?::\d{2,5})?(?:[/?#][^\s()]*)?>?\)$"#)
    /// The longest link destination taken with a tag, "(" through ")".
    static let maxLinkLength = 300

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a typo is a programming error the
        // tests catch on the first run.
        try! NSRegularExpression(pattern: pattern)
    }

    // MARK: Reading one tag

    /// A raw tag's inside ("\"Title\" — dl.acm.org/doi/…") as a source. Nil
    /// for an empty tag. Mirrors the server's `parseSourceTag`
    /// (lib/sourceTags.js), keeping the path for the chip's link.
    static func parseTag(_ inner: String, fallbackDomain: String? = nil) -> NightSource? {
        guard let parsed = parseTagInner(inner) else {
            return fallbackDomain.map { NightSource(label: "", domain: $0, path: nil) }
        }
        // A Markdown link around the tag lends its host to a tag without one.
        if parsed.domain == nil, let fallbackDomain {
            return NightSource(label: parsed.label, domain: fallbackDomain, path: nil)
        }
        return parsed
    }

    private static func parseTagInner(_ inner: String) -> NightSource? {
        let text = inner.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let m = match(addressOnly, text) {
            return NightSource(label: "", domain: m[0]?.lowercased(), path: m[1])
        }
        if let m = match(labelSeparatorAddress, text) ?? match(labelParenAddress, text) {
            return source(label: m[0] ?? "", domain: m[1], path: m[2])
        }
        if let m = match(labelSpaceScheme, text) ?? match(labelSpaceAddress, text) {
            return source(label: m[0] ?? "", domain: m[1], path: m[2])
        }
        return source(label: text, domain: nil, path: nil)
    }

    /// "label, domain" or "label" (the inside of "(Source: …)").
    static func parseInline(_ inner: String) -> NightSource? {
        let text = inner.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if let comma = text.range(of: ", ", options: .backwards) {
            let tail = String(text[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
            if match(hostOnly, tail) != nil {
                return source(label: String(text[..<comma.lowerBound]), domain: tail, path: nil)
            }
        }
        if match(hostOnly, text) != nil { return NightSource(label: "", domain: text, path: nil) }
        return source(label: text, domain: nil, path: nil)
    }

    private static func source(label: String, domain: String?, path: String?) -> NightSource? {
        let cleaned = cleanLabel(label)
        if cleaned.isEmpty && domain == nil { return nil }
        return NightSource(label: cleaned, domain: domain?.lowercased(), path: path)
    }

    /// Trims separators and one pair of surrounding quotes ("Title", “Title”).
    static func cleanLabel(_ label: String) -> String {
        var text = label.trimmingCharacters(in: .whitespaces)
        while let last = text.last, " —–:,|-".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in pairs where text.count >= 2 && text.first == open && text.last == close {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            break
        }
        return text
    }

    /// The capture groups of `regex`'s first match on the whole of `text`
    /// (index 0 is group 1), or nil.
    private static func match(_ regex: NSRegularExpression, _ text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<m.numberOfRanges).map { group in
            Range(m.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    // MARK: Taking sources out of prose

    /// The prose as Markdown runs and source chips, each chip right after
    /// the paragraph it was cited in. A tag still arriving mid-stream is
    /// held back (never shown as raw text); a complete reply's look-alike
    /// that never closes stays as written.
    static func segments(_ prose: String, isStreaming: Bool) -> [NightProseSegment] {
        var segments: [NightProseSegment] = []
        var pending: [String] = []
        func flush() {
            let text = pending.joined(separator: "\n\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segments.append(.markdown(text)) }
            pending = []
        }
        let source = isStreaming ? withholdingPartialTag(prose) : prose
        let paragraphs = paragraphs(of: source)
        // Mid-stream, the last line may still go on past what looks like a
        // citation's end ("Source: X (x.org) backs …"): its plain forms wait
        // for the line to end.
        let lastLineOpen = isStreaming && !source.hasSuffix("\n")
        for (index, paragraph) in paragraphs.enumerated() {
            if NightParts.isFence(Substring(paragraph)) {
                pending.append(paragraph)
                continue
            }
            let (text, sources) = extract(from: paragraph,
                                          lastLineOpen: lastLineOpen && index == paragraphs.count - 1)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pending.append(text) }
            if !sources.isEmpty {
                flush()
                segments += sources.map(NightProseSegment.source)
            }
        }
        flush()
        return segments
    }

    /// The prose with every source as the server's plain text ("Source:
    /// label (domain)"), for a reply shown plainly.
    static func plainText(_ prose: String) -> String {
        replacingRawTags(in: prose) { source, _ in source?.plainText ?? "" }
    }

    /// A card's text (a [KEY], [EX], [CHECK] or a check's question) without
    /// its sources, and the sources, to follow the card as chips. Text with
    /// nothing that could be a source comes back exactly as it was.
    static func strip(_ text: String, isStreaming: Bool) -> (text: String, sources: [NightSource]) {
        guard text.contains("[") || text.contains("Source:") else { return (text, []) }
        var kept: [String] = []
        var sources: [NightSource] = []
        for segment in segments(text, isStreaming: isStreaming) {
            switch segment {
            case .markdown(let run): kept.append(run)
            case .source(let source): sources.append(source)
            }
        }
        if sources.isEmpty && !isStreaming { return (text, []) }
        return (kept.joined(separator: "\n\n"), sources)
    }

    /// Every raw tag in `text` (with a Markdown link wrapped around it, as
    /// the model sometimes writes it: "[SOURCE: X — x.org](http://x.org)")
    /// replaced by `replacement` of its source (nil for an empty tag) and
    /// whether the tag is a sentence's subject: it opens a sentence and the
    /// sentence goes on in lower case ("[SOURCE: X — x.org] backs your
    /// data"). A look-alike that never closes stays as written.
    private static func replacingRawTags(in text: String,
                                         with replacement: (NightSource?, _ isSubject: Bool) -> String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: openTag) {
            out += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            if let close = closingBracket(in: afterOpen) {
                let afterClose = afterOpen[afterOpen.index(after: close)...]
                let link = linkAfterTag(afterClose)
                let after = afterClose.dropFirst(link?.length ?? 0)
                let isSubject = opensSentence(before: out) && continuesInLowercase(after)
                out += replacement(parseTag(String(afterOpen[..<close]), fallbackDomain: link?.host), isSubject)
                rest = after
            } else {
                out += rest[open]
                rest = afterOpen
            }
        }
        return out + rest
    }

    /// The text so far ends where a sentence may start: nothing on its line
    /// yet, or the end of a sentence (closing quotes or emphasis allowed).
    private static func opensSentence(before text: String) -> Bool {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        var core = line.trimmingCharacters(in: .whitespaces)
        while let last = core.last, "\"'”’)*_".contains(last) { core.removeLast() }
        guard let last = core.last else { return true }
        return ".!?…:".contains(last)
    }

    /// The text after a tag goes on with a lower-case word on the same line.
    private static func continuesInLowercase(_ text: Substring) -> Bool {
        guard let first = text.drop(while: { $0 == " " || $0 == "\t" }).first else { return false }
        return first.isLowercase
    }

    /// The Markdown link destination right after a tag's "]": "(" at once,
    /// an address with no space or "(", and ")" within `maxLinkLength`
    /// (the server's `linkAfter`). Its length and host, or nil.
    static func linkAfterTag(_ text: Substring) -> (length: Int, host: String)? {
        guard text.first == "(" else { return nil }
        var length = 0
        for (offset, c) in text.enumerated() {
            if offset >= maxLinkLength { return nil }
            if c == ")" {
                length = offset + 1
                break
            }
            if offset > 0 && (c.isWhitespace || c == "(") { return nil }
        }
        guard length > 0, let m = match(linkDestination, String(text.prefix(length))), let host = m[0] else {
            return nil
        }
        return (length, host.lowercased())
    }

    /// One paragraph's text without its sources, and the sources in order.
    /// Only the forms the server writes count, in their full shape: a raw
    /// tag; "(Source: label[, domain])"; and "Source: label (domain)" as a
    /// whole line or closing a line after a sentence. Prose that merely
    /// says "Source:" (a checklist, a question, PR #46's rewrite used as a
    /// sentence's subject) stays prose. `lastLineOpen`: the paragraph's
    /// last line is still streaming, so its line-end forms wait.
    static func extract(from paragraph: String, lastLineOpen: Bool = false) -> (text: String, sources: [NightSource]) {
        var sources: [NightSource] = []

        // Raw tags, anywhere. A tag used as a sentence's subject leaves its
        // title in the sentence ("Gender Shades backs your data"); its chip
        // still follows.
        let text = replacingRawTags(in: paragraph) { found, isSubject in
            guard let found else { return "" }
            sources.append(found)
            return isSubject ? found.title : ""
        }

        // The server's plain-text forms, line by line.
        var lines: [String] = []
        let rawLines = text.components(separatedBy: "\n")
        for (index, rawLine) in rawLines.enumerated() {
            var line = takeInline(from: rawLine, into: &sources)
            if lastLineOpen && index == rawLines.count - 1 {
                lines.append(line)
                continue
            }
            if let m = match(standaloneWithDomain, line.trimmingCharacters(in: .whitespaces)),
               let found = source(label: m[0] ?? "", domain: m[1], path: nil) {
                sources.append(found)
                continue
            }
            line = takeTrailing(from: line, into: &sources)
            lines.append(line)
        }
        let joined = lines.joined(separator: "\n")
        // Only a paragraph a source left gaps in is tidied: anything else
        // stays byte for byte (two trailing spaces are a line break).
        return (sources.isEmpty ? joined : tidy(joined), sources)
    }

    private static func takeInline(from line: String, into sources: inout [NightSource]) -> String {
        let ns = line as NSString
        let matches = inline.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return line }
        var out = ""
        var cursor = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            if let found = parseInline(ns.substring(with: m.range(at: 1))) { sources.append(found) }
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    private static func takeTrailing(from line: String, into sources: inout [NightSource]) -> String {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        guard let m = trailingWithDomain.firstMatch(in: line, range: whole) else { return line }
        let label = ns.substring(with: m.range(at: 2))
        // One citation, not another sentence of prose.
        guard !label.contains(". "), !label.contains("! "),
              let found = source(label: label, domain: ns.substring(with: m.range(at: 3)), path: nil) else { return line }
        sources.append(found)
        return ns.substring(to: m.range.location) + ns.substring(with: m.range(at: 1))
    }

    /// Collapses what a removed tag leaves behind: doubled spaces, a space
    /// before punctuation, empty parentheses.
    static func tidy(_ text: String) -> String {
        var out = text
        for (pattern, replacement) in [(#"\(\s*\)"#, ""), (#"[ \t]{2,}"#, " "), (#" +([.,;:!?)])"#, "$1"),
                                        (#"\( +"#, "("), (#"[ \t]+\n"#, "\n"), (#"[ \t]+$"#, "")] {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return out
    }

    /// The tag's "]": before any newline or "[", within the length bound.
    private static func closingBracket(in afterOpen: Substring) -> Substring.Index? {
        var count = openTag.count
        for index in afterOpen.indices {
            count += 1
            if count >= maxTagLength { return nil }
            let c = afterOpen[index]
            if c == "]" { return index }
            if c == "\n" || c == "[" { return nil }
        }
        return nil
    }

    /// Mid-stream: a trailing "[SOURCE: …" without its "]" yet, or a
    /// trailing start of "[SOURCE:", is held back.
    static func withholdingPartialTag(_ text: String) -> String {
        if let open = text.range(of: openTag, options: .backwards) {
            let afterOpen = text[open.upperBound...]
            // A closed tag whose Markdown link is still arriving: hold the
            // "(…" until its ")" says whether it is the tag's link.
            if let close = closingBracket(in: afterOpen) {
                let afterClose = afterOpen[afterOpen.index(after: close)...]
                if afterClose.first == "(", !afterClose.contains(")"), afterClose.count < maxLinkLength,
                   !afterClose.dropFirst().contains(where: { $0.isWhitespace || $0 == "(" }) {
                    return String(text[..<afterClose.startIndex])
                }
            }
            let unterminated = !afterOpen.contains("]") && !afterOpen.contains("\n") && !afterOpen.contains("[")
                && text.distance(from: open.lowerBound, to: text.endIndex) < maxTagLength
            if unterminated { return String(text[..<open.lowerBound]) }
        }
        if let bracket = text.lastIndex(of: "[") {
            let tail = text[bracket...]
            if tail.count < openTag.count, openTag.hasPrefix(tail) { return String(text[..<bracket]) }
        }
        return text
    }

    /// Paragraphs (blank-line separated), keeping a fenced code block whole.
    static func paragraphs(of text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [Substring] = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if NightParts.isFence(line) { inFence.toggle() }
            if !inFence, line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
        return paragraphs
    }
}

// MARK: - A reply, as the pieces Night draws

/// What a Night reply is drawn from, in order.
enum NightReplyPiece: Equatable {
    /// The mark before a lesson part (never before part 1).
    case partMark(number: Int, name: String?)
    /// Reading text (Markdown).
    case markdown(String)
    /// A source chip, after the paragraph that cited it.
    case source(NightSource)
    /// [EX]: the example card.
    case example(String)
    /// [KEY]: the key-idea card.
    case key(String)
    /// [CHECK] (or a malformed [Q]): Merc's open question, as the Your turn
    /// card.
    case openQuestion(String)
    /// [Q]: the check with Lock it in.
    case quiz(QuizBlock)
    /// Free chat: the latest reply's closing question, as the Your turn card.
    case yourTurn(String)
    /// Under the crisis guard: plain reading text, nothing styled.
    case plain(String)
    /// Lesson 1.1's interactive ("How a model reads “bank”"), where
    /// `NightInteractiveAnchor` puts it.
    case interactive
}

enum NightReplyLayout {
    /// A lesson reply: its parts, numbered from `firstPart`, each after its
    /// mark (part 1 has none). Under the crisis guard every block is plain
    /// text, but the marks stay, so the count stays true.
    static func lesson(sections: [NightSection], firstPart: Int, crisis: Bool, isStreaming: Bool,
                       interactiveAfter: NightInteractivePosition? = nil) -> [NightReplyPiece] {
        var pieces: [NightReplyPiece] = []
        // Lesson 1.1's interactive goes after its block (never under the
        // crisis guard).
        let interactive = crisis ? nil : interactiveAfter
        for (offset, section) in sections.enumerated() {
            let number = firstPart + offset
            if number > 1 { pieces.append(.partMark(number: number, name: section.name)) }
            let lastSection = offset == sections.count - 1
            for (index, block) in section.blocks.enumerated() {
                if index > 0, interactive == NightInteractivePosition(section: offset, afterBlock: index - 1) {
                    pieces.append(.interactive)
                }
                let streamingTail = isStreaming && lastSection && index == section.blocks.count - 1
                if crisis {
                    pieces.append(.plain(plainText(block)))
                    continue
                }
                switch block {
                case .prose(let text):
                    pieces += NightSourceParser.segments(MessageBubbleView.stripCheckTokens(text),
                                                         isStreaming: streamingTail).map(piece)
                // A card's sources follow it as chips: raw tags inside
                // [KEY], [EX], [CHECK] and a check's question never show.
                case .key(let text):
                    let card = NightSourceParser.strip(text, isStreaming: streamingTail)
                    if !card.text.isEmpty { pieces.append(.key(card.text)) }
                    pieces += card.sources.map(NightReplyPiece.source)
                case .example(let text):
                    let card = NightSourceParser.strip(text, isStreaming: streamingTail)
                    if !card.text.isEmpty { pieces.append(.example(card.text)) }
                    pieces += card.sources.map(NightReplyPiece.source)
                case .check(let text):
                    let card = NightSourceParser.strip(text, isStreaming: streamingTail)
                    if !card.text.isEmpty { pieces.append(.openQuestion(card.text)) }
                    pieces += card.sources.map(NightReplyPiece.source)
                case .quiz(let quiz):
                    let stem = NightSourceParser.strip(quiz.stem, isStreaming: streamingTail)
                    if quiz.isComplete && !quiz.isWellFormed {
                        // The pre-blocks degradation: the interior as an
                        // open question.
                        pieces.append(.openQuestion(([stem.text] + quiz.options).filter { !$0.isEmpty }
                            .joined(separator: " ")))
                    } else {
                        // Only the question's words change; the options
                        // (what "I picked B) …" sends) are the reply's own.
                        var shown = quiz
                        if !stem.text.isEmpty { shown.stem = stem.text }
                        pieces.append(.quiz(shown))
                    }
                    pieces += stem.sources.map(NightReplyPiece.source)
                }
            }
            // At the end of its part.
            if let at = interactive, at.section == offset, at.afterBlock >= section.blocks.count - 1 {
                pieces.append(.interactive)
            }
        }
        return pieces.filter { if case .plain(let s) = $0 { return !s.isEmpty } else { return true } }
    }

    /// A free-chat reply: prose with its sources as chips, and, when
    /// `yourTurn` (the latest completed reply), its closing question as the
    /// Your turn card. Under the crisis guard: one plain run of text.
    static func chat(content: String, isStreaming: Bool, yourTurn: Bool, crisis: Bool) -> [NightReplyPiece] {
        // A lesson-only marker never belongs in free chat; strip it so it
        // can't surface literally (as the iPhone's bubble does).
        let prose = MessageBubbleView.stripCheckTokens(content)
        if crisis {
            let plain = NightSourceParser.plainText(prose)
            return plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.plain(plain)]
        }
        if yourTurn, !isStreaming, let split = NightYourTurn.split(prose) {
            return NightSourceParser.segments(split.before, isStreaming: false).map(piece)
                + [.yourTurn(split.question)]
                + split.trailingSources.map(NightReplyPiece.source)
        }
        return NightSourceParser.segments(prose, isStreaming: isStreaming).map(piece)
    }

    private static func piece(_ segment: NightProseSegment) -> NightReplyPiece {
        switch segment {
        case .markdown(let text): return .markdown(text)
        case .source(let source): return .source(source)
        }
    }

    /// A block as plain text (the crisis guard): markers gone, sources as
    /// the server's plain text, a [Q]'s options kept and its answer key
    /// never.
    static func plainText(_ block: MessageBlock) -> String {
        switch block {
        case .prose(let text): return NightSourceParser.plainText(MessageBubbleView.stripCheckTokens(text))
        case .key(let text), .example(let text), .check(let text): return NightSourceParser.plainText(text)
        case .quiz(let quiz):
            let options = quiz.options.enumerated().map { "\(ChatAnnouncement.letter($0.offset))) \($0.element)" }
            return ([NightSourceParser.plainText(quiz.stem)] + options).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }
}

// MARK: - The closing question ("Your turn")

enum NightYourTurn {
    /// The longest closing paragraph that becomes the card.
    static let maxLength = 400

    /// The modes whose closing question is the student's turn: Socratic,
    /// where the question back is the method. Debate's and Discussion's
    /// closing lines stay prose.
    static let modes: Set<ChatMode> = [.socratic]

    /// A reply's prose split for the Your turn card: everything before its
    /// closing question, the question, and any sources cited after it. Nil
    /// when the reply doesn't really end with a question: its last
    /// paragraph (sources aside) must end in "?" (closing emphasis or
    /// quotes allowed), be 400 characters or fewer, and be a plain
    /// paragraph (not a list item, heading, quote, table or code).
    static func split(_ prose: String) -> (before: String, question: String, trailingSources: [NightSource])? {
        var paragraphs = NightSourceParser.paragraphs(of: prose)
        var trailing: [NightSource] = []
        while let last = paragraphs.last {
            let (text, sources) = NightSourceParser.extract(from: last)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !sources.isEmpty {
                trailing.insert(contentsOf: sources, at: 0)
                paragraphs.removeLast()
            } else {
                break
            }
        }
        guard let last = paragraphs.last else { return nil }
        let (questionText, inlineSources) = NightSourceParser.extract(from: last)
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isQuestion(question) else { return nil }
        paragraphs.removeLast()
        return (paragraphs.joined(separator: "\n\n"), question, inlineSources + trailing)
    }

    /// The thread's latest reply is Merc's, settled, and ends on the Your
    /// turn card (the mode asks, and the crisis guard doesn't hold it).
    static func latestReplyAsks(_ messages: [ChatMessage], mode: ChatMode) -> Bool {
        guard modes.contains(mode), let last = messages.last, last.role == .assistant, last.status == .idle,
              !NightCrisisGuard.guardedReplies(in: messages).contains(last.id) else { return false }
        return split(MessageBubbleView.stripCheckTokens(last.content)) != nil
    }

    static func isQuestion(_ paragraph: String) -> Bool {
        guard !paragraph.isEmpty, paragraph.count <= maxLength else { return false }
        let starts = ["#", ">", "- ", "* ", "+ ", "|", "```", "~~~", "["]
        if starts.contains(where: { paragraph.hasPrefix($0) }) { return false }
        if paragraph.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil { return false }
        var core = Substring(paragraph)
        while let last = core.last, "*_\"'”’)".contains(last) { core = core.dropLast() }
        return core.hasSuffix("?")
    }
}

// MARK: - The crisis guard

enum NightCrisisGuard {
    /// The server's own crisis-reply signal (server.js CRISIS_RESOURCE_RE):
    /// 988 or 741741 as a whole word. A reply that carries a crisis line is
    /// drawn as plain reading text: no Your turn card, no source chips, no
    /// serif, no wash. Calm beats styled.
    static func applies(to reply: String) -> Bool {
        reply.range(of: #"\b988\b|\b741741\b"#, options: .regularExpression) != nil
    }

    /// The thread's replies drawn plainly: once a reply in the thread carried
    /// a crisis line, it and every reply after it. Merc's follow-ups there
    /// rarely repeat the numbers, but the safety core says not to resume
    /// tutoring, so no Your turn card, chip or card frames them either. A
    /// new thread starts clear.
    static func guardedReplies(in messages: [ChatMessage]) -> Set<UUID> {
        guard let first = messages.firstIndex(where: { $0.role == .assistant && applies(to: $0.content) }) else {
            return []
        }
        return Set(messages[first...].filter { $0.role == .assistant }.map(\.id))
    }
}

/// `NightCrisisGuard.guardedReplies`, worked out once per change of the
/// thread (the list asks for every row, on every streamed delta).
@MainActor
final class NightCrisisIndex {
    private var ids: [UUID] = []
    private var lengths: [Int] = []
    private var cached: Set<UUID> = []

    func guardedReplies(in messages: [ChatMessage]) -> Set<UUID> {
        let newIds = messages.map(\.id)
        let newLengths = messages.map { $0.content.utf8.count }
        if newIds == ids && newLengths == lengths { return cached }
        ids = newIds
        lengths = newLengths
        cached = NightCrisisGuard.guardedReplies(in: messages)
        return cached
    }
}

// MARK: - The example's token line

/// "The word "unbelievable" might become three tokens: "un", "believ",
/// "able"." → unbelievable → [un] [believ] [able]. Only this pattern: a
/// quoted word, then in the same sentence "token(s)" and two or more quoted
/// pieces that join to exactly that word. The pieces are Merc's own words;
/// nothing is tokenised here.
enum NightTokenLine {
    struct Match: Equatable {
        let word: String
        let pieces: [String]
    }

    static func recognize(_ text: String) -> Match? {
        for sentence in sentences(of: text) {
            let quotes = quoted(in: sentence)
            for (wordIndex, word) in quotes.enumerated() where !word.text.contains(" ") && word.text.count >= 2 {
                let afterWord = sentence[word.end...]
                guard let tokenWord = afterWord.range(of: #"\btokens?\b"#, options: [.regularExpression, .caseInsensitive]) else {
                    continue
                }
                let pieces = quotes[(wordIndex + 1)...].filter { $0.start >= tokenWord.upperBound }.map(\.text)
                guard pieces.count >= 2 else { continue }
                var joined = ""
                for (count, piece) in pieces.enumerated() {
                    joined += piece
                    if joined == word.text, count + 1 >= 2 {
                        return Match(word: word.text, pieces: Array(pieces[...count]))
                    }
                    if !word.text.hasPrefix(joined) { break }
                }
            }
        }
        return nil
    }

    private struct Quoted {
        let text: String
        let start: String.Index
        let end: String.Index
    }

    /// Straight or curly double-quoted runs.
    private static func quoted(in sentence: Substring) -> [Quoted] {
        var found: [Quoted] = []
        var index = sentence.startIndex
        while index < sentence.endIndex {
            let c = sentence[index]
            if c == "\"" || c == "“" {
                let close: Character = c == "\"" ? "\"" : "”"
                let contentStart = sentence.index(after: index)
                if let end = sentence[contentStart...].firstIndex(where: { $0 == close || (close == "”" && $0 == "\"") }) {
                    let text = String(sentence[contentStart..<end])
                    found.append(Quoted(text: text, start: index, end: sentence.index(after: end)))
                    index = sentence.index(after: end)
                    continue
                }
            }
            index = sentence.index(after: index)
        }
        return found
    }

    /// Sentences, split at ".", "!" or "?" outside quotes when followed by a
    /// space or the end.
    private static func sentences(of text: String) -> [Substring] {
        var sentences: [Substring] = []
        var start = text.startIndex
        var inStraight = false
        var curlyDepth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            switch c {
            case "\"": inStraight.toggle()
            case "“": curlyDepth += 1
            case "”": curlyDepth = max(0, curlyDepth - 1)
            case ".", "!", "?":
                let next = text.index(after: index)
                if !inStraight, curlyDepth == 0, next == text.endIndex || text[next].isWhitespace {
                    sentences.append(text[start..<next])
                    start = next
                }
            default: break
            }
            index = text.index(after: index)
        }
        if start < text.endIndex { sentences.append(text[start...]) }
        return sentences
    }
}

// MARK: - The check from the keyboard

enum NightCheckKeys {
    /// A key the lesson hands its waiting check.
    enum Key: Equatable {
        /// A–D or 1–4: that option (the card checks it exists).
        case option(Int)
        /// ↑ (−1) or ↓ (+1).
        case move(Int)
        /// Return (or Enter): lock the pick in.
        case lockIn
    }

    /// The check's key for a key press with no ⌘, ⌃ or ⌥: A–D / 1–4, the
    /// up and down arrows, Return and Enter. Nil for anything else (it goes
    /// on to the window as usual).
    static func key(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Key? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
            .subtracting([.shift, .capsLock, .function, .numericPad])
        guard flags.isEmpty else { return nil }
        switch keyCode {
        case 36, 76: return .lockIn          // Return, Enter
        case 126: return .move(-1)           // ↑
        case 125: return .move(1)            // ↓
        default: break
        }
        guard let characters, let index = optionIndex(forKey: characters, optionCount: 4) else { return nil }
        return .option(index)
    }

    /// The option a key picks: A–D (either case) or 1–4, within the
    /// question's options. Nil for anything else.
    static func optionIndex(forKey characters: String, optionCount: Int) -> Int? {
        guard characters.count == 1, let c = characters.uppercased().unicodeScalars.first else { return nil }
        let index: Int
        switch c.value {
        case 65...68: index = Int(c.value) - 65
        case 49...52: index = Int(c.value) - 49
        default: return nil
        }
        return index < optionCount ? index : nil
    }

    /// ↑/↓ from `current` (nil: none picked yet), clamped to the options.
    static func moved(_ current: Int?, by step: Int, optionCount: Int) -> Int? {
        guard optionCount > 0 else { return nil }
        guard let current else { return step > 0 ? 0 : optionCount - 1 }
        return min(max(current + step, 0), optionCount - 1)
    }

    /// Whether the latest reply holds a check the student can still answer
    /// with Lock it in: a well-formed, complete [Q] in the last message,
    /// which is Merc's, while nothing is in flight.
    static func hasAnswerableCheck(messages: [ChatMessage], isIdle: Bool) -> Bool {
        guard isIdle, let last = messages.last, last.role == .assistant else { return false }
        return BlockParser.parse(last.content).contains {
            if case .quiz(let quiz) = $0 { return quiz.isWellFormed } else { return false }
        }
    }
}

// MARK: - Who the tutor is

/// The tutor is Merc on every Mac screen; "Mercurius" is the app's name only
/// (the window title, Settings, the consent text). The iPhone's shared
/// strings that call the tutor "Mercurius" are overridden here, for the Mac
/// only (`ModeDescription` itself is unchanged).
public enum NightModeCopy {
    /// What a mode is for, in the tutor's own name.
    public static func purpose(_ mode: ChatMode) -> String {
        switch mode {
        case .socratic: return "Merc asks questions back instead of handing you the answer."
        case .debate: return "Merc argues back. You take a side, he pushes the other."
        case .discussion: return "Merc treats you as an intellectual peer — exploring ideas together, not teaching you."
        }
    }

    /// The free chat's composer: "Ask Merc…", or "Your answer…" when Merc's
    /// latest reply ends on the Your turn card.
    static let askPlaceholder = "Ask Merc…"
    static let answerPlaceholder = "Your answer…"

    static func chatPlaceholder(messages: [ChatMessage], mode: ChatMode) -> String {
        NightYourTurn.latestReplyAsks(messages, mode: mode) ? answerPlaceholder : askPlaceholder
    }
}

// MARK: - Copy

/// Every new line of UI text the Mac's Night lesson and chat say (SPEC §6),
/// in one place so `NightReplyCopyTests` can hold it to the honest-copy
/// rules: no notebook, no "saved", no part totals, no time estimates, no
/// features that don't exist.
enum NightReplyCopy {
    // Parts
    static func partNumber(_ number: Int) -> String { String(format: "%02d", number) }
    static func partLabel(_ number: Int) -> String { "Part \(number)" }
    static func partStripTitle(_ number: Int, name: String?) -> String {
        name.map { "Part \(number) · \($0)" } ?? "Part \(number)"
    }
    static func partAccessibility(_ number: Int, name: String?) -> String {
        name.map { "Part \(number), \($0)" } ?? "Part \(number)"
    }
    static func stripAccessibilityLabel(count: Int, current: Int, name: String?) -> String {
        let now = name.map { "Now reading part \(current), \($0)." } ?? "Now reading part \(current)."
        return "Lesson parts so far: \(count). \(now)"
    }
    static let stripAccessibilityHint = "Swipe up or down to move between parts."
    static func segmentHelp(_ number: Int, name: String?) -> String {
        "Go to \(partStripTitle(number, name: name))"
    }
    static let moreMayFollowHelp = "More parts may follow as Merc goes on."

    // Blocks
    static let example = "Example"
    static let keyIdea = "Key idea"
    static let yourTurn = "Your turn"
    static func tokenLineAccessibility(_ match: NightTokenLine.Match) -> String {
        "\(match.word) becomes \(match.pieces.count) tokens: \(match.pieces.joined(separator: ", "))."
    }

    // The check. The strip ("Part 3 · Check") and the part's mark already
    // name it, so the card's eyebrow says what to do, not "Check" again.
    static let checkOpen = "Your turn first"
    /// Basics says what to do in plain words (review 2026-10-22).
    static let checkOpenBasics = "Pick one"
    static let checkAnswered = "Answered"
    static let checkInert = "Check"
    static let lockIn = "Lock it in"
    static func lockInAccessibility(letter: String) -> String { "Lock in answer \(letter)" }
    static let lockInHelp = "Grade your pick and send it to Merc (Return)"
    static let checkCardHelp = "Pick with A–D or the arrow keys, then press Return to lock it in."
    static let checkPlaceholder = "Or answer in your own words…"

    // Sources
    static let sourceCitedBy = "Cited by Merc"
    static func sourceCaption(domain: String?) -> String {
        domain.map { "\(sourceCitedBy) · \($0)" } ?? sourceCitedBy
    }
    static let sourceHelp = "Merc picked this source. Open it and check that it says what Merc says."
    static let sourceInertHelp = "Merc named this source without an address to open."
    static func sourceAccessibility(_ source: NightSource, opens: Bool) -> String {
        let place = source.domain.map { ", \($0)" } ?? ""
        let title = source.label.isEmpty ? "" : source.label
        let opening = opens ? " Opens in your browser." : ""
        return "Source Merc cited: \(title.isEmpty ? (source.domain ?? "") : title + place).\(opening)"
    }

    // Who is speaking
    static let merc = "Merc"
    static let aiTutor = "AI tutor"
    static let mercAccessibility = "Merc, AI tutor."
    static func studentAccessibility(_ text: String) -> String { "You: \(text)" }
}
#endif
