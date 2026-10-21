#if os(macOS)
import Foundation
import CoreGraphics
import Observation

// Lesson 1.1's interactive on the Mac, "How a model reads “bank”": the
// meaning sky (Night Studio's signature) with Field Notes' steps and the
// judges' fixes (SYNTHESIS.md graft 6, roadmap B2). Everything here is pure
// and tested (NightTokenizerTests): the content, where the card sits in the
// lesson, the map's geometry and what VoiceOver says. The words and claims
// are in docs/mac-night-studio/tokenizer/CONTENT.md, with their sources.
//
// Nothing here is sent anywhere: the card is drawn on the Mac and changes
// nothing on the wire, in the prompt or in what is stored.

// MARK: - The content

enum NightTokenizer {
    /// The lesson the card belongs to: Unit 1, Lesson 1, "What happens when
    /// you type a prompt".
    static let lessonID = "u1_l1"

    static func belongs(toLesson lessonID: String?) -> Bool {
        lessonID == Self.lessonID
    }

    /// A token as the card draws it. `leadingSpace`: the space before the
    /// word travels with it (drawn as a dot, "·went"). `id` is illustrative.
    struct Token: Equatable, Sendable {
        let text: String
        let leadingSpace: Bool
        let id: Int

        /// "·went".
        var shown: String { leadingSpace ? "·" + text : text }
        /// What the token is, characters and all: " went".
        var raw: String { leadingSpace ? " " + text : text }
        /// For VoiceOver: "space went".
        var spoken: String { leadingSpace ? "space \(text)" : text }
    }

    /// The one sentence the card shows. It is fixed on purpose: there is no
    /// faithful tokenizer for the model Mercurius uses on the device, so the
    /// student's own text is never cut up here.
    static let sentence = "I went to the bank"

    /// The sentence's tokens, as a subword tokenizer of the GPT kind cuts
    /// it: each space goes with the word after it. The IDs come from the
    /// Field Notes concept and are shown as illustrative only.
    static let tokens: [Token] = [
        Token(text: "I", leadingSpace: false, id: 40),
        Token(text: "went", leadingSpace: true, id: 4024),
        Token(text: "to", leadingSpace: true, id: 311),
        Token(text: "the", leadingSpace: true, id: 279),
        Token(text: "bank", leadingSpace: true, id: 6201),
    ]

    /// The token the map follows.
    static var bank: Token { tokens[tokens.count - 1] }

    /// The first numbers of "·bank"'s list (illustrative: a real list has
    /// thousands, learned in training). The same whichever opening is picked:
    /// the token's own numbers don't depend on the words around it.
    static let bankNumbers: [Double] = [0.12, -0.08, 0.31, -0.27, 0.05, 0.19, -0.14, 0.22]

    /// "0.12", "−0.08" (a real minus sign).
    static func formatted(_ number: Double) -> String {
        let text = String(format: "%.2f", abs(number))
        return number < 0 ? "\u{2212}" + text : text
    }
}

/// The two ways the student can start the sentence. They are the control:
/// the context, never the meaning. The context comes BEFORE "bank" on
/// purpose: a model like the one Mercurius runs on reads left to right, so
/// what it makes of "bank" can only be shaped by the words before it.
/// (Words after "bank" change what it makes of the sentence at those later
/// words, not at "bank": an ending wouldn't honestly move "bank".)
enum NightTokenizerContext: String, CaseIterable, Sendable {
    case money
    case river

    /// The words the student puts first.
    var opening: String {
        switch self {
        case .money: return "I got my paycheck, so"
        case .river: return "I wanted to go fishing, so"
        }
    }

    /// The chip: "I got my paycheck, so…".
    var chipTitle: String { opening + "\u{2026}" }

    /// The whole sentence, context first.
    var sentence: String { "\(opening) \(NightTokenizer.sentence)." }

    /// The words "bank" lands near on the map.
    var neighbours: [String] {
        NightMeaningMap.words.filter { $0.group == self }.map(\.text)
    }
}

// MARK: - The map's geometry

/// The map of meaning: four words in two neighbourhoods, "bank"'s starting
/// point between them, and where "bank" ends up for each opening. Points are
/// fractions of the panel; label frames are in points, from approximate
/// text widths, so a test can check nothing overlaps at the widths the card
/// is drawn at. The view places its labels at these frames' centres.
enum NightMeaningMap {
    enum Side: Equatable, Sendable { case below, above, leading, trailing }

    struct Word: Equatable, Sendable {
        let text: String
        let point: CGPoint
        let group: NightTokenizerContext
        let side: Side
    }

    static let words: [Word] = [
        Word(text: "loan", point: CGPoint(x: 0.13, y: 0.36), group: .money, side: .below),
        Word(text: "deposit", point: CGPoint(x: 0.33, y: 0.17), group: .money, side: .trailing),
        Word(text: "shore", point: CGPoint(x: 0.64, y: 0.82), group: .river, side: .leading),
        Word(text: "water", point: CGPoint(x: 0.87, y: 0.58), group: .river, side: .above),
    ]

    /// Where "bank"'s first numbers put it: between the two neighbourhoods.
    /// The same every time.
    static let start = CGPoint(x: 0.50, y: 0.46)

    /// Where "bank" sits once the model has read the opening (nil: no
    /// context yet, so the starting point).
    static func bank(_ context: NightTokenizerContext?) -> CGPoint {
        switch context {
        case nil: return start
        case .money: return CGPoint(x: 0.25, y: 0.46)
        case .river: return CGPoint(x: 0.76, y: 0.62)
        }
    }

    /// The panel's height for a card this wide.
    static func height(forWidth width: CGFloat) -> CGFloat {
        width < 460 ? 200 : 240
    }

    static func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    /// The words nearest `point`, nearest first, measured in points (the
    /// panel isn't square).
    static func nearest(to point: CGPoint, in size: CGSize, count: Int = 2) -> [String] {
        let p = scaled(point, in: size)
        return words
            .map { word -> (String, CGFloat) in
                let q = scaled(word.point, in: size)
                return (word.text, hypot(q.x - p.x, q.y - p.y))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map(\.0)
    }

    // Approximate type metrics (SF Mono 13 medium; SF Mono 14 in the pill;
    // Lexend 12 for the start's caption).
    static let wordCharWidth: CGFloat = 7.9
    static let wordHeight: CGFloat = 16
    static let labelGap: CGFloat = 9
    static let dotGap: CGFloat = 22
    static let pillSize = CGSize(width: 58, height: 24)
    static let startCaption = "where \u{201C}bank\u{201D} starts"
    static let startCaptionSize = CGSize(width: 128, height: 16)
    static let startRingRadius: CGFloat = 14

    /// A word's label, beside its dot on `side`.
    static func labelFrame(_ word: Word, in size: CGSize) -> CGRect {
        let p = scaled(word.point, in: size)
        let w = CGFloat(word.text.count) * wordCharWidth
        let h = wordHeight
        switch word.side {
        case .below: return CGRect(x: p.x - w / 2, y: p.y + labelGap, width: w, height: h)
        case .above: return CGRect(x: p.x - w / 2, y: p.y - labelGap - h, width: w, height: h)
        case .leading: return CGRect(x: p.x - labelGap - w, y: p.y - h / 2, width: w, height: h)
        case .trailing: return CGRect(x: p.x + labelGap, y: p.y - h / 2, width: w, height: h)
        }
    }

    /// "bank"'s pill, centred under its dot.
    static func pillFrame(_ context: NightTokenizerContext?, in size: CGSize) -> CGRect {
        let p = scaled(bank(context), in: size)
        return CGRect(x: p.x - pillSize.width / 2, y: p.y + dotGap - pillSize.height / 2,
                      width: pillSize.width, height: pillSize.height)
    }

    /// The start ring's caption, above the ring, clear of "bank"'s trail
    /// (which leaves the ring sideways or downward). Shown once "bank" has
    /// moved off it.
    static func startCaptionFrame(in size: CGSize) -> CGRect {
        let p = scaled(start, in: size)
        let s = startCaptionSize
        return CGRect(x: p.x - s.width / 2, y: p.y - startRingRadius - 6 - s.height, width: s.width, height: s.height)
    }

    /// Every label on the panel in this state: the words, the pill and, once
    /// "bank" has moved, the start's caption.
    static func labelFrames(_ context: NightTokenizerContext?, in size: CGSize) -> [(String, CGRect)] {
        var frames = words.map { ($0.text, labelFrame($0, in: size)) }
        frames.append(("bank pill", pillFrame(context, in: size)))
        if context != nil { frames.append(("start caption", startCaptionFrame(in: size))) }
        return frames
    }
}

// MARK: - Where the card sits in the lesson

/// The interactive's place in a lesson reply: after block `afterBlock` of
/// part `section` (0-based, `NightParts.sections` order).
struct NightInteractivePosition: Equatable, Hashable, Sendable {
    let section: Int
    let afterBlock: Int
}

struct NightInteractivePlacement: Equatable, Sendable {
    let messageID: UUID
    let position: NightInteractivePosition
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
/// - Never in a thread that has carried a crisis line (988 or 741741):
///   not in, after or before that reply.
/// - Only in Lesson 1.1, and only in lessons (the list asks only for them).
///
/// The rule reads the thread and nothing else, so a reopened thread puts
/// the card where it was.
enum NightInteractiveAnchor {
    static func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                          sections: (ChatMessage) -> [NightSection]) -> NightInteractivePlacement? {
        guard NightTokenizer.belongs(toLesson: lessonID), crisisReplies.isEmpty else { return nil }
        for message in messages where message.role == .assistant {
            let parts = sections(message)
            let complete = message.status == .idle
            if let example = firstExample(in: parts) {
                if let position = afterExamplePart(parts, example: example, replyComplete: complete) {
                    return NightInteractivePlacement(messageID: message.id, position: position)
                }
                // The example's part is still arriving, or was cut off.
                if message.status == .streaming { return nil }
                continue
            }
            switch message.status {
            case .streaming:
                return nil
            case .idle:
                if let position = fallback(parts) {
                    return NightInteractivePlacement(messageID: message.id, position: position)
                }
            case .failed, .interrupted:
                break
            }
        }
        return nil
    }

    /// The first [EX] block: (part, block).
    static func firstExample(in parts: [NightSection]) -> (section: Int, block: Int)? {
        for (s, part) in parts.enumerated() {
            for (b, block) in part.blocks.enumerated() {
                if case .example = block { return (s, b) }
            }
        }
        return nil
    }

    /// The end of the example's part, before a check in it; nil while that
    /// part may still grow.
    static func afterExamplePart(_ parts: [NightSection], example: (section: Int, block: Int),
                                 replyComplete: Bool) -> NightInteractivePosition? {
        let blocks = parts[example.section].blocks
        if let quiz = blocks.indices.first(where: { $0 > example.block && isQuiz(blocks[$0]) }) {
            // A check has begun after the example: everything before it is in.
            return NightInteractivePosition(section: example.section, afterBlock: quiz - 1)
        }
        let finished = replyComplete || example.section < parts.count - 1
        guard finished else { return nil }
        return NightInteractivePosition(section: example.section, afterBlock: blocks.count - 1)
    }

    /// A complete reply without an example: its end, before its first check.
    static func fallback(_ parts: [NightSection]) -> NightInteractivePosition? {
        guard let last = parts.indices.last, !parts[last].blocks.isEmpty else { return nil }
        for (s, part) in parts.enumerated() {
            if let q = part.blocks.firstIndex(where: isQuiz) {
                if q > 0 { return NightInteractivePosition(section: s, afterBlock: q - 1) }
                if s > 0 { return NightInteractivePosition(section: s - 1, afterBlock: parts[s - 1].blocks.count - 1) }
                break
            }
        }
        return NightInteractivePosition(section: last, afterBlock: parts[last].blocks.count - 1)
    }

    private static func isQuiz(_ block: MessageBlock) -> Bool {
        if case .quiz = block { return true }
        return false
    }
}

/// `NightInteractiveAnchor.placement`, worked out once per change of the
/// thread (the list asks on every streamed delta).
@MainActor
final class NightInteractiveIndex {
    private struct Key: Equatable {
        let id: UUID
        let length: Int
        let status: ChatMessage.Status
    }

    private var lessonID: String?
    private var keys: [Key]?
    private var cached: NightInteractivePlacement?

    func placement(lessonID: String?, messages: [ChatMessage], crisisReplies: Set<UUID>,
                   sections: (ChatMessage) -> [NightSection]) -> NightInteractivePlacement? {
        guard NightTokenizer.belongs(toLesson: lessonID) else { return nil }
        let keys = messages.map { Key(id: $0.id, length: $0.content.utf8.count, status: $0.status) }
        if keys == self.keys, lessonID == self.lessonID { return cached }
        self.keys = keys
        self.lessonID = lessonID
        cached = NightInteractiveAnchor.placement(lessonID: lessonID, messages: messages,
                                                  crisisReplies: crisisReplies, sections: sections)
        return cached
    }
}

// MARK: - The card's state

/// What the student has done with the card in this lesson: the opening
/// picked, and whether the narrow card was opened. Kept by the lesson's
/// list (not the card), so a reply's re-render never resets it. Never
/// stored or sent.
@Observable
@MainActor
final class NightTokenizerState {
    var context: NightTokenizerContext?
    /// The compact "Try it" card was opened.
    var expanded = false

    init(context: NightTokenizerContext? = nil) {
        self.context = context
        #if DEBUG
        // `-NightTokenizer money|river` (shots only): an opening already
        // picked.
        if context == nil, let raw = UserDefaults.standard.string(forKey: "NightTokenizer") {
            self.context = NightTokenizerContext(rawValue: raw)
        }
        #endif
    }
}

/// When the card starts compact: a "Try it" card that opens in place.
enum NightTokenizerLayout {
    /// The card is narrower than this (a 700 pt window with the sidebar
    /// open leaves a 390 pt reading measure): it starts compact.
    static let compactBelowWidth: CGFloat = 440

    /// `-NightTokenizerCompact YES` (shots only): compact at any width.
    static let debugForcesCompact: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "NightTokenizerCompact")
        #else
        return false
        #endif
    }()

    /// `width` 0 is "not measured yet": the full card.
    static func isCompact(width: CGFloat, expanded: Bool, forced: Bool = false) -> Bool {
        guard !expanded else { return false }
        return forced || (width > 0 && width < compactBelowWidth)
    }
}

// MARK: - The words

/// Every line of the card. Held to the honest-copy register and to the
/// accuracy rules by `NightTokenizerTests`; CONTENT.md has each claim's
/// source.
enum NightTokenizerCopy {
    static let eyebrow = "Interactive"
    static let title = "How a model reads \u{201C}bank\u{201D}"

    static let step1 = "You type"
    static let step2 = "It\u{2019}s cut into tokens"
    static let step3 = "Each token becomes a list of numbers"
    static let step4 = "The numbers land in a map of meaning"
    static let steps = [step1, step2, step3, step4]

    static let spaceNote = "A dot marks a space: it travels with the word after it."
    static let idNote = "The numbers under the tokens are illustrative IDs. Real IDs depend on the model\u{2019}s tokenizer."

    static let listLabel = "a list of numbers"
    static let listMore = "+ thousands more"
    static let listNote = "Illustrative values. In a real model, each token\u{2019}s list has thousands of numbers, learned in training."

    static let startPrompt = "Start the sentence:"
    static let sketch = "A 2-D sketch: the real space has thousands of dimensions."
    /// The accuracy rule, in two short sentences: the token's own numbers
    /// are fixed; the later layers, reading the words before it, shift the
    /// meaning. ("Before", not "around": the model reads left to right.)
    static let howItMoves = "The token \u{201C}bank\u{201D} always starts with the same list of numbers. Then the model\u{2019}s later layers read the words before it, which shifts what \u{201C}bank\u{201D} means."

    // The compact card
    static let compactLine = "See \u{201C}I went to the bank\u{201D} become tokens, then numbers, then a place on a map of meaning."
    static let tryIt = "Try it"
    static let tryItHint = "Opens the interactive here, in the lesson"

    // Help (hover)
    static func chipHelp(_ context: NightTokenizerContext) -> String {
        "Start the sentence with \u{201C}\(context.opening)\u{201D} (Space or Return)"
    }

    // VoiceOver
    static let cardAccessibility = "Interactive: How a model reads bank"
    static func stepAccessibility(_ number: Int, _ title: String) -> String { "Step \(number): \(title)" }
    static let typedAccessibility = "You type: \(NightTokenizer.sentence)"

    static var tokensAccessibility: String {
        let tokens = NightTokenizer.tokens
        let list = tokens.map(\.spoken).joined(separator: ", ")
        let ids = tokens.map { String($0.id) }.joined(separator: ", ")
        return "\(NightTokenizer.sentence), cut into \(tokens.count) tokens: \(list). "
            + "Their IDs, illustrative: \(ids)."
    }

    static var numbersAccessibility: String {
        let values = NightTokenizer.bankNumbers.map(spokenNumber).joined(separator: ", ")
        return "The token \(NightTokenizer.bank.spoken) becomes a list of numbers. "
            + "Illustrative values: \(values), and thousands more."
    }

    static func spokenNumber(_ number: Double) -> String {
        let text = String(format: "%.2f", abs(number))
        return number < 0 ? "minus \(text)" : text
    }

    /// The map in words, for VoiceOver: what the picture shows.
    static func mapSummary(_ context: NightTokenizerContext?) -> String {
        switch context {
        case nil:
            return "Map of meaning, a 2-D sketch. bank starts between two groups of words: "
                + "loan and deposit, and shore and water."
        case .some(let context):
            let near = context.neighbours.joined(separator: " and ")
            return "Map of meaning, a 2-D sketch. With \u{201C}\(context.opening)\u{201D} before it, "
                + "bank is near \(near)."
        }
    }

    /// Said when an opening is picked.
    static func pickedAnnouncement(_ context: NightTokenizerContext) -> String {
        "\(context.sentence) \(mapSummary(context))"
    }

    static func chipAccessibility(_ context: NightTokenizerContext) -> String {
        "Start the sentence: \(context.opening)"
    }

    static let chipHint = "Moves bank on the map of meaning"

    /// Every line, for the register tests.
    static var everyLine: [String] {
        var lines = [eyebrow, title, spaceNote, idNote, listLabel, listMore, listNote, startPrompt, sketch,
                     howItMoves, compactLine, tryIt, tryItHint, cardAccessibility, typedAccessibility,
                     tokensAccessibility, numbersAccessibility, chipHint, mapSummary(nil),
                     NightMeaningMap.startCaption] + steps
        for (index, step) in steps.enumerated() { lines.append(stepAccessibility(index + 1, step)) }
        for context in NightTokenizerContext.allCases {
            lines += [context.chipTitle, context.sentence, chipHelp(context), mapSummary(context),
                      pickedAnnouncement(context), chipAccessibility(context)]
        }
        return lines
    }
}
#endif
