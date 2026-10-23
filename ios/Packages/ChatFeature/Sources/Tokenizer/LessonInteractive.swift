import Foundation

// Where Lesson 1.1's interactive sits in the lesson's thread, on the Mac and
// the iPhone alike: the rule (`LessonInteractiveAnchor`), its once-per-thread
// memory (`LessonInteractiveIndex`), and, for the iPhone's bubble, where the
// card cuts a reply's blocks (`LessonInteractiveSplit`). Pure and tested
// (TokenizerInteractiveTests). Nothing here changes what is sent or stored.

/// The interactive's place in a lesson reply: after block `afterBlock` of
/// part `section` (0-based, `LessonParts.sections` order).
struct LessonInteractivePosition: Equatable, Hashable, Sendable {
    let section: Int
    let afterBlock: Int
}

struct LessonInteractivePlacement: Equatable, Sendable {
    let messageID: UUID
    let position: LessonInteractivePosition
}

/// Where the card goes in Lesson 1.1's thread, once per thread:
///
/// - In the first of Merc's replies with an [EX] example, at the end of the
///   part the example is in, and before any check that follows in that
///   part (so the check never comes first). The card waits until that part
///   has finished arriving: a later part has begun, a check has begun, or
///   the reply is complete. It then sits where text has stopped arriving.
/// - If the first complete reply has no example, at the end of that reply,
///   before its check.
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
/// - Only in Lesson 1.1, and only in lessons (the list asks only for them).
///
/// The rule reads the thread and nothing else. `LessonInteractiveIndex`
/// keeps its first answer for the thread, so the card never moves while
/// the lesson is open or when it is reopened in the same run of the app.
enum LessonInteractiveAnchor {
    static func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                          sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard TokenizerInteractive.belongs(toLesson: lessonID), crisisReplies.isEmpty else { return nil }
        let last = messages.last?.id
        for message in messages where message.role == .assistant {
            let parts = sections(message)
            let complete = message.status == .idle && message.id == last
            if let example = firstExample(in: parts) {
                if let position = afterExamplePart(parts, example: example, replyComplete: complete) {
                    return LessonInteractivePlacement(messageID: message.id, position: position)
                }
                // The example's part is still arriving, or was cut off.
                if message.status == .streaming { return nil }
                continue
            }
            switch message.status {
            case .streaming:
                return nil
            case .idle:
                if let position = fallback(parts, replyComplete: complete) {
                    return LessonInteractivePlacement(messageID: message.id, position: position)
                }
            case .failed, .interrupted:
                break
            }
        }
        return nil
    }

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
/// has a place it stays there while its reply is in the thread (a Retry
/// replaces the reply, and the rule decides again), including when the
/// lesson is reopened in the same run of the app (`LessonInteractiveMemory`).
/// A crisis line still removes it.
@MainActor
final class LessonInteractiveIndex {
    private struct Key: Equatable {
        let id: UUID
        let length: Int
        let status: ChatMessage.Status
    }

    private let memory: LessonInteractiveMemory
    private var lessonID: String?
    private var keys: [Key]?
    private var cached: LessonInteractivePlacement?

    init() {
        memory = .shared
    }

    /// Tests: a memory of their own.
    init(memory: LessonInteractiveMemory) {
        self.memory = memory
    }

    func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                   sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard TokenizerInteractive.belongs(toLesson: lessonID) else { return nil }
        let keys = messages.map { Key(id: $0.id, length: $0.content.utf8.count, status: $0.status) }
        if keys == self.keys, lessonID == self.lessonID { return cached }
        self.keys = keys
        self.lessonID = lessonID
        cached = resolve(lessonID: lessonID, messages: messages, crisisReplies: crisisReplies, sections: sections)
        return cached
    }

    private func resolve(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                         sections: (ChatMessage) -> [LessonPart]) -> LessonInteractivePlacement? {
        guard crisisReplies.isEmpty, let thread = messages.first?.id else { return nil }
        if let kept = memory[thread], messages.contains(where: { $0.id == kept.messageID }) {
            return kept
        }
        let found = LessonInteractiveAnchor.placement(lessonID: lessonID, messages: messages,
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
            return Halves(head: Array(blocks[...at.flat]), tail: droppingOpeningBreak(after))
        }
        var tail: [MessageBlock] = []
        if !cut.rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tail.append(.prose(cut.rest)) }
        return Halves(head: Array(blocks[..<at.flat]) + [.prose(cut.before)], tail: tail + after)
    }

    /// The blocks after a card that follows a card block ([EX], [KEY]): when
    /// the prose after it opens with a break, before any text, that break
    /// ends the card's part, so the card stands where its rule was and the
    /// line isn't drawn (as when the part ends in prose). A break with text
    /// before it isn't the part's end and stays.
    private static func droppingOpeningBreak(_ blocks: [MessageBlock]) -> [MessageBlock] {
        guard case .prose(let prose) = blocks.first, let cut = cutProse(prose, afterPiece: 0),
              cut.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return blocks }
        let rest = blocks.dropFirst()
        return cut.rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Array(rest) : [.prose(cut.rest)] + rest
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
