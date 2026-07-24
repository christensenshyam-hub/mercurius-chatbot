import Foundation

/// blocks_v1 (Presentation P4): tokenize a tutor reply into renderable
/// blocks. Generalizes `MessageBubbleView.splitCheck`'s single-[CHECK] split
/// into the full marker vocabulary, with the same streaming guarantees:
///
///  - a trailing proper-prefix of ANY known marker ("[K", "[/CHE", "[Q") is
///    withheld so raw tags never flash mid-stream;
///  - an OPEN [KEY]/[EX]/[CHECK] with no close yet renders its interior live
///    inside its card (today's [CHECK] behavior);
///  - an OPEN [Q] renders its stem + fully-arrived option lines, untappable
///    until `[/Q]`; the `ANS:` line is NEVER emitted as renderable content —
///    complete or not.
///
/// Malformed degradation is the key safety property: a `[Q]` that closes
/// without ≥2 options or a valid `ANS:` renders as the plain open-ended
/// callout — worst case is exactly the pre-blocks UX.
enum MessageBlock: Equatable {
    case prose(String)
    case key(String)
    case example(String)
    /// Open-ended check — the existing tinted callout card.
    case check(String)
    case quiz(QuizBlock)
}

struct QuizBlock: Equatable {
    var stem: String
    var options: [String]
    /// Parsed from the `ANS: X` line; nil while streaming or when malformed.
    var answerIndex: Int?
    /// Saw the closing `[/Q]` — gates tappability.
    var isComplete: Bool

    var isWellFormed: Bool {
        guard isComplete, !stem.isEmpty, (2...4).contains(options.count),
              let answerIndex, answerIndex < options.count else { return false }
        return true
    }
}

enum BlockParser {
    private struct SpanToken {
        let open: String
        let close: String
        let build: (String, Bool) -> MessageBlock
    }

    private static let tokens: [SpanToken] = [
        .init(open: "[CHECK]", close: "[/CHECK]", build: { body, _ in .check(body.trimmingCharacters(in: .whitespacesAndNewlines)) }),
        .init(open: "[KEY]", close: "[/KEY]", build: { body, _ in .key(body.trimmingCharacters(in: .whitespacesAndNewlines)) }),
        .init(open: "[EX]", close: "[/EX]", build: { body, _ in .example(body.trimmingCharacters(in: .whitespacesAndNewlines)) }),
        .init(open: "[Q]", close: "[/Q]", build: { body, complete in .quiz(Self.parseQuiz(body, isComplete: complete)) }),
    ]

    /// All literal marker strings, for the partial-suffix hold-back.
    private static let allMarkers: [String] = tokens.flatMap { [$0.open, $0.close] }

    /// Tokenize a (possibly still-streaming) reply.
    static func parse(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var remaining = Substring(withheldPartialMarker(text))

        while let (token, openRange) = earliestOpen(in: remaining) {
            let before = String(remaining[..<openRange.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.prose(before))
            }
            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: token.close) {
                let body = String(afterOpen[..<closeRange.lowerBound])
                blocks.append(token.build(body, true))
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                // Unclosed span mid-stream: render its interior live.
                blocks.append(token.build(String(afterOpen), false))
                remaining = Substring("")
            }
        }
        let tail = String(remaining)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.prose(tail))
        }
        return blocks
    }

    /// Flatten to plain prose — markers removed, `ANS:` dropped, quiz options
    /// kept as "A) …" lines. For the report payload and VoiceOver.
    static func plainText(_ text: String) -> String {
        parse(text).map { block in
            switch block {
            case .prose(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines)
            case .key(let s), .example(let s): return s
            case .check(let s): return "Question: \(s)"
            case .quiz(let q):
                let options = q.options.enumerated().map { i, o -> String in
                    let letter = String(UnicodeScalar(65 + i)!)
                    return "\(letter)) \(o)"
                }
                return ([q.stem.isEmpty ? nil : "Question: \(q.stem)"].compactMap { $0 } + options)
                    .joined(separator: "\n")
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    // MARK: - Internals

    /// Drop a trailing proper-prefix of any known marker so it never flashes
    /// as literal text while streaming (generalizes stripCheckTokens' suffix
    /// hold-back). Only the TAIL can be a partial marker.
    private static func withheldPartialMarker(_ text: String) -> String {
        guard let idx = text.lastIndex(of: "[") else { return text }
        let tail = String(text[idx...])
        if allMarkers.contains(where: { $0.count > tail.count && $0.hasPrefix(tail) }) {
            return String(text[..<idx])
        }
        return text
    }

    private static func earliestOpen(in text: Substring) -> (SpanToken, Range<Substring.Index>)? {
        var best: (SpanToken, Range<Substring.Index>)?
        for token in tokens {
            guard let r = text.range(of: token.open) else { continue }
            if best == nil || r.lowerBound < best!.1.lowerBound { best = (token, r) }
        }
        return best
    }

    static func parseQuiz(_ interior: String, isComplete: Bool) -> QuizBlock {
        var stemLines: [String] = []
        var options: [String] = []
        var answerIndex: Int?
        for rawLine in interior.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // "A) option" … "D) option"
            if line.count > 2, let first = line.first, ("A"..."D").contains(String(first)),
               line.dropFirst().hasPrefix(") ") {
                options.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            // "ANS: X" — never rendered; parsed for local grading only.
            if line.hasPrefix("ANS:") {
                let letter = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if letter.count == 1, let scalar = letter.unicodeScalars.first,
                   (65...68).contains(Int(scalar.value)) {
                    answerIndex = Int(scalar.value) - 65
                }
                continue
            }
            // Mid-stream partial "AN"/"ANS" tails also stay hidden.
            if !isComplete, "ANS:".hasPrefix(line) { continue }
            if options.isEmpty && answerIndex == nil { stemLines.append(line) }
        }
        return QuizBlock(
            stem: stemLines.joined(separator: " "),
            options: options,
            answerIndex: answerIndex,
            isComplete: isComplete
        )
    }
}
