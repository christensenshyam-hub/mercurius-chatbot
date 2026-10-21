import Foundation
import LessonInteractives

// Where a lesson's interactive sits in its thread, on the Mac and the
// iPhone alike: the anchor rules (`LessonInteractiveAnchor`), the spoiler
// scan, the once-per-thread memory (`LessonInteractiveIndex`) and, for the
// iPhone's bubble, where the card cuts a reply's blocks
// (`LessonInteractiveSplit`). Which lesson holds which card, and by which
// rule, is LessonInteractives' `InteractiveRegistry`. Pure and tested
// (TokenizerInteractiveTests, InteractivePlacementTests). Nothing here
// changes what is sent or stored.

/// The interactive's place in a lesson reply: after block `afterBlock` of
/// part `section` (0-based, `LessonParts.sections` order).
struct LessonInteractivePosition: Equatable, Hashable, Sendable {
    let section: Int
    let afterBlock: Int
}

/// Which card a reply holds, and whether it opens in its spoiled mode.
struct LessonInteractiveCardRef: Equatable, Hashable, Sendable {
    let id: InteractiveID
    let spoiled: Bool

    /// Lesson 1.1's card, as the list has always drawn it.
    static let tokenizer = LessonInteractiveCardRef(id: .tokenizer, spoiled: false)
}

struct LessonInteractivePlacement: Equatable, Sendable {
    let messageID: UUID
    let position: LessonInteractivePosition
    /// The card (the lesson's spec's).
    let card: InteractiveID
    /// The tutor said one of the card's spoiler terms before it: in an
    /// earlier reply, or above the card in its own. Worked out once, when
    /// the place is found, and kept with it.
    let spoiled: Bool

    init(messageID: UUID, position: LessonInteractivePosition, card: InteractiveID, spoiled: Bool = false) {
        self.messageID = messageID
        self.position = position
        self.card = card
        self.spoiled = spoiled
    }

    var cardRef: LessonInteractiveCardRef { LessonInteractiveCardRef(id: card, spoiled: spoiled) }
}

/// Where a lesson's card goes in its thread, once per thread. Which reply
/// holds it is the card's anchor rule (`InteractiveAnchorRule`); inside
/// that reply the place is always the same:
///
/// - At the end of the part its first [EX] example is in, and before any
///   check that follows in that part (so the check never comes first). The
///   card waits until that part has finished arriving: a later part has
///   begun, a check has begun, or the reply is complete. It then sits where
///   text has stopped arriving.
/// - If the reply has no example, at its end, before its check.
/// - A reply cut off before the example's part finished, or one that
///   failed before any text, is passed over: the next reply decides (a
///   Retry replaces the cut reply and decides again).
/// - "Complete" counts as proof that a part finished only for the thread's
///   last message. A cut reply the student answered instead of retrying
///   (AUD-29) is saved, and comes back from storage as `.idle` like any
///   other reply, so a reply with anything after it has to show its part
///   ended: a later part, or a check after the example (or, with no
///   example, a check to sit before).
/// - Never in a thread that has carried a crisis line (988 or 741741):
///   not in, after or before that reply.
/// - Only in the lesson the registry gives the card, and only in lessons
///   (the list asks only for them).
///
/// The anchor rules:
/// - `.firstExample` (Lesson 1.1's): the first reply with an example, or
///   the first complete reply when it has none.
/// - `.teachReply(n)`: the nth reply carrying a [Q] check. A reply counts
///   once its check has begun; one that can't hold the card (its check is
///   its very first block) hands the card to the next teach reply.
/// - `.firstReplyMentioning(terms, fallback: n)`: the first reply whose
///   text has a term (`InteractiveTerms`); a reply still arriving without
///   one may yet say it, so the rule waits for it. If none has by the nth
///   teach reply, that reply holds the card.
///
/// The rules read the thread and nothing else. `LessonInteractiveIndex`
/// keeps the first answer for the thread, so the card never moves (and its
/// spoiled flag never flips) while the lesson is open or when it is
/// reopened in the same run of the app.
enum LessonInteractiveAnchor {
    /// The card lesson `lessonID` shows (the registry's), placed. Lesson
    /// 1.1's rule and card, as before the registry, for `u1_l1`.
    static func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                          sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard let spec = InteractiveRegistry.spec(forLesson: lessonID) else { return nil }
        return placement(spec: spec, messages: messages, crisisReplies: crisisReplies, sections: sections)
    }

    /// `spec`'s card, placed by its anchor rule, with its spoiled flag.
    static func placement(spec: InteractiveSpec, messages: [ChatMessage], crisisReplies: Set<UUID>,
                          sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard crisisReplies.isEmpty else { return nil }
        let found: (message: ChatMessage, position: LessonInteractivePosition)?
        switch spec.anchor {
        case .firstExample:
            found = firstExample(messages: messages, sections: sections)
        case .teachReply(let n):
            found = teachReply(n, messages: messages, sections: sections)
        case .firstReplyMentioning(let terms, let fallback):
            found = firstMention(of: terms, fallback: fallback, messages: messages, sections: sections)
        }
        guard let found else { return nil }
        let spoiled = isSpoiled(spec, messages: messages, at: found.message.id, position: found.position,
                                sections: sections)
        return LessonInteractivePlacement(messageID: found.message.id, position: found.position, card: spec.id,
                                          spoiled: spoiled)
    }

    // MARK: Inside one reply

    /// What one reply says about holding the card.
    enum Decision: Equatable {
        /// It holds the card here.
        case place(LessonInteractivePosition)
        /// It may yet (it is still arriving): nothing is placed meanwhile.
        case wait
        /// It can't (cut, failed, or nowhere to sit): the next reply decides.
        case passOver
    }

    /// Where `message` would hold the card: after its first example's part,
    /// else (a settled reply) before its check or at its end.
    static func decision(_ message: ChatMessage, parts: [LessonPart], isLast: Bool) -> Decision {
        let complete = message.status == .idle && isLast
        if let example = firstExample(in: parts) {
            if let position = afterExamplePart(parts, example: example, replyComplete: complete) {
                return .place(position)
            }
            // The example's part is still arriving, or was cut off.
            return message.status == .streaming ? .wait : .passOver
        }
        switch message.status {
        case .streaming:
            return .wait
        case .idle:
            return fallback(parts, replyComplete: complete).map(Decision.place) ?? .passOver
        case .failed, .interrupted:
            return .passOver
        }
    }

    // MARK: The rules

    /// `.firstExample`: the first reply that can hold the card.
    static func firstExample(messages: [ChatMessage], sections: (ChatMessage) -> [LessonPart])
        -> (message: ChatMessage, position: LessonInteractivePosition)? {
        let last = messages.last?.id
        for message in messages where message.role == .assistant {
            switch decision(message, parts: sections(message), isLast: message.id == last) {
            case .place(let position): return (message, position)
            case .wait: return nil
            case .passOver: continue
            }
        }
        return nil
    }

    /// `.teachReply(n)`: the nth reply with a [Q] check (or, if that one
    /// can't hold the card, the next teach reply that can).
    static func teachReply(_ n: Int, messages: [ChatMessage], sections: (ChatMessage) -> [LessonPart])
        -> (message: ChatMessage, position: LessonInteractivePosition)? {
        let last = messages.last?.id
        var teachReplies = 0
        for message in messages where message.role == .assistant {
            let parts = sections(message)
            guard hasQuiz(parts) else {
                // Still arriving: its check may yet begin.
                if message.status == .streaming { return nil }
                continue
            }
            teachReplies += 1
            guard teachReplies >= n else { continue }
            switch decision(message, parts: parts, isLast: message.id == last) {
            case .place(let position): return (message, position)
            case .wait: return nil
            case .passOver: continue
            }
        }
        return nil
    }

    /// `.firstReplyMentioning(terms, fallback:)`: the first reply that
    /// mentions a term, else `teachReply(fallback)`.
    static func firstMention(of terms: [String], fallback: Int, messages: [ChatMessage],
                             sections: (ChatMessage) -> [LessonPart])
        -> (message: ChatMessage, position: LessonInteractivePosition)? {
        let last = messages.last?.id
        var teachReplies = 0
        for message in messages where message.role == .assistant {
            let parts = sections(message)
            let teaches = hasQuiz(parts)
            if teaches { teachReplies += 1 }
            let mentions = InteractiveTerms.firstMatch(of: terms, in: message.content) != nil
            if !mentions {
                // Still arriving: it may yet say a term.
                if message.status == .streaming { return nil }
                // The fallback: the nth teach reply (or, if it can't hold
                // the card, the next one).
                guard teaches, teachReplies >= fallback else { continue }
            }
            switch decision(message, parts: parts, isLast: message.id == last) {
            case .place(let position): return (message, position)
            case .wait: return nil
            case .passOver: continue
            }
        }
        return nil
    }

    // MARK: Spoilers

    /// Whether the tutor said one of `spec`'s spoiler terms before the card:
    /// anywhere in an earlier reply, or above the card in its own reply
    /// (what follows the card isn't read first, and wasn't there yet when a
    /// streaming reply's card was placed: the flag is the same whenever it
    /// is worked out).
    static func isSpoiled(_ spec: InteractiveSpec, messages: [ChatMessage], at messageID: UUID,
                          position: LessonInteractivePosition, sections: (ChatMessage) -> [LessonPart]) -> Bool {
        guard !spec.spoilers.isEmpty else { return false }
        for message in messages where message.role == .assistant {
            if message.id == messageID {
                return spec.spoilerTerm(in: textAbove(position, in: sections(message))) != nil
            }
            if spec.spoilerTerm(in: message.content) != nil { return true }
        }
        return false
    }

    /// The text of a reply's blocks up to and including `position`.
    static func textAbove(_ position: LessonInteractivePosition, in parts: [LessonPart]) -> String {
        var pieces: [String] = []
        for (s, part) in parts.enumerated() where s <= position.section {
            for (b, block) in part.blocks.enumerated() where s < position.section || b <= position.afterBlock {
                pieces.append(text(of: block))
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    static func text(of block: MessageBlock) -> String {
        switch block {
        case .prose(let text), .key(let text), .example(let text), .check(let text): return text
        case .quiz(let quiz): return ([quiz.stem] + quiz.options).joined(separator: "\n")
        }
    }

    // MARK: Positions

    /// The first [EX] block: (part, block).
    static func firstExample(in parts: [LessonPart]) -> (section: Int, block: Int)? {
        for (s, part) in parts.enumerated() {
            for (b, block) in part.blocks.enumerated() {
                if case .example = block { return (s, b) }
            }
        }
        return nil
    }

    /// The end of the example's part, before a check in it; nil while that
    /// part may still grow.
    static func afterExamplePart(_ parts: [LessonPart], example: (section: Int, block: Int),
                                 replyComplete: Bool) -> LessonInteractivePosition? {
        let blocks = parts[example.section].blocks
        if let quiz = blocks.indices.first(where: { $0 > example.block && isQuiz(blocks[$0]) }) {
            // A check has begun after the example: everything before it is in.
            return LessonInteractivePosition(section: example.section, afterBlock: quiz - 1)
        }
        let finished = replyComplete || example.section < parts.count - 1
        guard finished else { return nil }
        return LessonInteractivePosition(section: example.section, afterBlock: blocks.count - 1)
    }

    /// A complete reply without an example: its end, before its first check.
    /// An earlier reply (`replyComplete` false) needs a check to sit before:
    /// without one, its end may be where it was cut off.
    static func fallback(_ parts: [LessonPart], replyComplete: Bool = true) -> LessonInteractivePosition? {
        guard let last = parts.indices.last, !parts[last].blocks.isEmpty else { return nil }
        for (s, part) in parts.enumerated() {
            if let q = part.blocks.firstIndex(where: isQuiz) {
                if q > 0 { return LessonInteractivePosition(section: s, afterBlock: q - 1) }
                if s > 0 { return LessonInteractivePosition(section: s - 1, afterBlock: parts[s - 1].blocks.count - 1) }
                break
            }
        }
        guard replyComplete else { return nil }
        return LessonInteractivePosition(section: last, afterBlock: parts[last].blocks.count - 1)
    }

    /// Whether a reply carries a [Q] check (begun or whole).
    static func hasQuiz(_ parts: [LessonPart]) -> Bool {
        parts.contains { $0.blocks.contains(where: isQuiz) }
    }

    private static func isQuiz(_ block: MessageBlock) -> Bool {
        if case .quiz = block { return true }
        return false
    }
}

/// Where the card went in each thread during this run of the app, by the
/// thread's first message (its id survives a reopen). Kept in memory
/// only: nothing is stored.
@MainActor
final class LessonInteractiveMemory {
    static let shared = LessonInteractiveMemory()
    private var placements: [UUID: LessonInteractivePlacement] = [:]

    subscript(thread: UUID) -> LessonInteractivePlacement? {
        get { placements[thread] }
        set { placements[thread] = newValue }
    }
}

/// `LessonInteractiveAnchor.placement`, worked out once per change of the
/// thread (the list asks on every streamed delta), and kept: once the card
/// has a place (and a spoiled flag) it stays there while its reply is in
/// the thread (a Retry replaces the reply, and the rule decides again),
/// including when the lesson is reopened in the same run of the app
/// (`LessonInteractiveMemory`). A crisis line still removes it.
@MainActor
final class LessonInteractiveIndex {
    private struct Key: Equatable {
        let id: UUID
        let length: Int
        let status: ChatMessage.Status
    }

    private let memory: LessonInteractiveMemory
    private var spec: InteractiveSpec?
    private var keys: [Key]?
    private var cached: LessonInteractivePlacement?

    init() {
        memory = .shared
    }

    /// Tests: a memory of their own.
    init(memory: LessonInteractiveMemory) {
        self.memory = memory
    }

    /// The card lesson `lessonID` shows (the registry's), placed.
    func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                   sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard let spec = InteractiveRegistry.spec(forLesson: lessonID) else { return nil }
        return placement(spec: spec, messages: messages, crisisReplies: crisisReplies, sections: sections)
    }

    /// `spec`'s card, placed.
    func placement(spec: InteractiveSpec, messages: [ChatMessage], crisisReplies: Set<UUID>,
                   sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        let keys = messages.map { Key(id: $0.id, length: $0.content.utf8.count, status: $0.status) }
        if keys == self.keys, spec == self.spec { return cached }
        self.keys = keys
        self.spec = spec
        cached = resolve(spec: spec, messages: messages, crisisReplies: crisisReplies, sections: sections)
        return cached
    }

    private func resolve(spec: InteractiveSpec, messages: [ChatMessage], crisisReplies: Set<UUID>,
                         sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard crisisReplies.isEmpty, let thread = messages.first?.id else { return nil }
        if let kept = memory[thread], kept.card == spec.id, messages.contains(where: { $0.id == kept.messageID }) {
            return kept
        }
        let found = LessonInteractiveAnchor.placement(spec: spec, messages: messages,
                                                      crisisReplies: crisisReplies, sections: sections)
        if let found { memory[thread] = found }
        return found
    }
}

// MARK: - The iPhone: where the card cuts a reply

/// The iPhone draws a lesson reply as `BlockParser`'s blocks in one bubble,
/// with each part's "---" inside a prose block (MarkdownUI draws it as a
/// rule). The card needs the room of the whole row, so the bubble that holds
/// it is drawn in two: the blocks before the card, then the card, then the
/// rest. `halves` finds that cut from a `LessonInteractivePosition`, walking
/// the blocks exactly as `LessonParts.sections` does.
///
/// At the end of a part the cut falls on the part's break line. The card
/// stands where that rule was, so the rule itself isn't drawn: the second
/// half starts with what follows it. Nothing else changes: every other
/// block, and every character of the reply, is drawn as before, and the
/// reply's text (what Copy, Report and VoiceOver read) is untouched.
enum LessonInteractiveSplit {
    struct Halves: Equatable {
        /// Drawn before the card.
        var head: [MessageBlock]
        /// Drawn after it (empty when the card closes the reply).
        var tail: [MessageBlock]
    }

    /// One block of a part, and where it came from: block `flat` of
    /// `BlockParser.parse`, and for prose, piece `piece` of its text cut at
    /// its breaks.
    private struct Source {
        let flat: Int
        let piece: Int?
    }

    /// The reply `text` cut where the card goes, or nil if `position` isn't
    /// in it.
    static func halves(of text: String, at position: LessonInteractivePosition) -> Halves? {
        let blocks = BlockParser.parse(text)
        var groups: [[Source]] = [[]]
        for (flat, block) in blocks.enumerated() {
            guard case .prose(let prose) = block else {
                groups[groups.count - 1].append(Source(flat: flat, piece: nil))
                continue
            }
            for (index, piece) in LessonParts.splitAtBreaks(prose).enumerated() {
                if index > 0 { groups.append([]) }
                if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    groups[groups.count - 1].append(Source(flat: flat, piece: index))
                }
            }
        }
        let parts = groups.filter { !$0.isEmpty }
        guard parts.indices.contains(position.section),
              parts[position.section].indices.contains(position.afterBlock) else { return nil }
        let at = parts[position.section][position.afterBlock]
        let after = Array(blocks[(at.flat + 1)...])
        guard let piece = at.piece, case .prose(let prose) = blocks[at.flat],
              let cut = cutProse(prose, afterPiece: piece) else {
            return Halves(head: Array(blocks[...at.flat]), tail: after)
        }
        var tail: [MessageBlock] = []
        if !cut.rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tail.append(.prose(cut.rest)) }
        return Halves(head: Array(blocks[..<at.flat]) + [.prose(cut.before)], tail: tail + after)
    }

    /// `prose` cut at the break that ends its piece `piece`: the text before
    /// that break line, and the text after it (the line itself dropped). Nil
    /// when no break follows that piece (it ends the prose).
    static func cutProse(_ prose: String, afterPiece piece: Int) -> (before: String, rest: String)? {
        let lines = prose.split(separator: "\n", omittingEmptySubsequences: false)
        var inFence = false
        var breaks = 0
        for (index, line) in lines.enumerated() {
            if LessonParts.isFence(line) { inFence.toggle() }
            guard !inFence, LessonParts.isThematicBreak(line) else { continue }
            if breaks == piece {
                return (lines[..<index].joined(separator: "\n"), lines[(index + 1)...].joined(separator: "\n"))
            }
            breaks += 1
        }
        return nil
    }
}
