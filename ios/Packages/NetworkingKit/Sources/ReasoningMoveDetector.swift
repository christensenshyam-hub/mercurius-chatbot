import Foundation

/// Lightweight, heuristics-first detection of a reasoning move in a student's
/// chat turn — the Swift mirror of `lib/gamification/heuristics.js`.
///
/// It detects PROCESS (questioning, revising, doubting), never correctness, and
/// returns at most one move (the higher-effort one when several match). The
/// caller fires a gated, fire-and-forget `recordEvent`; the SERVER still
/// validates, caps, and applies diminishing returns — this only *requests* an
/// evaluation. Cheap and synchronous; never blocks the chat send.
public enum ReasoningMoveDetector {

    /// The single best-matching reasoning move for a user turn, or nil.
    public static func detect(in userText: String) -> ProgressionReason? {
        let t = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if matches(t, Self.selfCorrection) { return .selfCorrection }
        if matches(t, Self.revision) { return .positionRevision }
        if matches(t, Self.clarifying) && t.contains("?") { return .clarifyingQuestion }
        if matches(t, Self.uncertainty) { return .uncertaintyExpressed }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let clarifying =
        #"\b(what do you mean|can you clarify|why is that|how does that|what if|is it because|could it be|what's the difference|how come)\b"#
    private static let revision =
        #"\b(i was wrong|i changed my mind|on second thought|actually,? i think|i'd revise|let me reconsider|i take that back|i now think)\b"#
    private static let selfCorrection =
        #"\b(i made a mistake|i misspoke|correction|that's not right, i|i mixed up|i confused)\b"#
    private static let uncertainty =
        #"\b(i'm not sure|i'm unsure|i don't know|i'm uncertain|not entirely sure|hard to say|i could be wrong)\b"#
}
