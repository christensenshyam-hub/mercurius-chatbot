import Foundation

/// Which of the lesson's replies holds the card (BUILD_PLAN.md §1.3).
/// Inside that reply the card always goes at the end of its first [EX]
/// example's part, before any check, or (no example) at the reply's end
/// before its check. Never mid-stream, never in a cut-off part, never in a
/// thread that carried a crisis line, once per thread. ChatFeature's
/// `LessonInteractiveAnchor` applies the rule; it reads the thread only.
public enum InteractiveAnchorRule: Equatable, Hashable, Sendable {
    /// The first of Merc's replies with an [EX] example (or the first
    /// complete reply, when none has one). Lesson 1.1's rule.
    case firstExample
    /// The nth of Merc's replies in the lesson that carries a [Q] check
    /// (1-based). A reply counts once its check has begun arriving.
    case teachReply(Int)
    /// The first reply that mentions any of `terms` (case-insensitive, at
    /// the start of a word). If none has by the reply that is
    /// `teachReply(fallback)`, that reply holds the card.
    case firstReplyMentioning([String], fallback: Int)

    /// How many of Merc's replies arrive before the card can: what a DEBUG
    /// stub replay answers its way to (`-Interactive <slug>`).
    public var repliesToReach: Int {
        switch self {
        case .firstExample: return 1
        case .teachReply(let n): return max(n, 1)
        case .firstReplyMentioning(_, let fallback): return max(min(2, fallback), 1)
        }
    }
}

/// One card's row in the registry: its lesson, where it sits there, what
/// in the tutor's text spoils its prediction, and whether it ships.
public struct InteractiveSpec: Equatable, Hashable, Sendable, Identifiable {
    public let id: InteractiveID
    /// The lesson that holds it: "u6_l4" (`Curriculum.swift`'s ids).
    public let lessonID: String
    public let anchor: InteractiveAnchorRule
    /// Terms that, said by the tutor before the card (in an earlier reply,
    /// or above the card in its own), mean the card opens in its spoiled
    /// mode: it skips or swaps its prediction, and the reveal drops "You
    /// guessed". Case-insensitive, matched at the start of a word, any
    /// ending ("impossib" catches "impossibility"). Empty: never spoiled.
    public let spoilers: [String]
    /// 0: shipped before the framework (the tokenizer); 1 or 2: the
    /// slate's waves.
    public let wave: Int
    /// Compile-time: a card ships dark until its teacher review (§4.5) is
    /// signed off in its CONTENT.md. DEBUG's `-Interactive <slug>` shows a
    /// dark card in its lesson anyway.
    public let enabled: Bool

    public init(id: InteractiveID, lessonID: String, anchor: InteractiveAnchorRule,
                spoilers: [String] = [], wave: Int, enabled: Bool) {
        self.id = id
        self.lessonID = lessonID
        self.anchor = anchor
        self.spoilers = spoilers
        self.wave = wave
        self.enabled = enabled
    }

    /// The first spoiler term in `text`, if any.
    public func spoilerTerm(in text: String) -> String? {
        InteractiveTerms.firstMatch(of: spoilers, in: text)
    }

    /// This spec with `enabled` set (DEBUG forcing, tests).
    public func enabled(_ enabled: Bool) -> InteractiveSpec {
        InteractiveSpec(id: id, lessonID: lessonID, anchor: anchor, spoilers: spoilers, wave: wave, enabled: enabled)
    }
}

/// How the anchor and the spoiler scan match terms in the tutor's text:
/// case- and diacritic-insensitive, starting at the start of a word ("12%"
/// isn't found in "112%"), with any ending ("impossib" finds
/// "impossibility").
public enum InteractiveTerms {
    public static func firstMatch(of terms: [String], in text: String) -> String? {
        for term in terms where !term.isEmpty && contains(term, in: text) {
            return term
        }
        return nil
    }

    public static func contains(_ term: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive],
                                     range: searchStart..<text.endIndex) {
            if range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)]) {
                return true
            }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
