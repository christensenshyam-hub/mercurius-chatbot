import Foundation

// The Citation That Wasn't (U1L3, "Why AI sounds confident but can be
// wrong"; SLATE.md ★3, docs/interactives/citation-that-wasnt/CONTENT.md).
//
// The student watches a model write a reference for a study that doesn't
// exist: five slots, each with its three likeliest next pieces and their
// illustrative chances. They guess each piece, see the one the model drew,
// then guess the step where the model "decided" to make it up. The reveal:
// no step did. "Write it again" draws a second authored path to a
// different, equally tidy fake (its first draw is the only one shown with
// the same chances: a real model's later chances depend on the pieces
// before them, CONTENT.md §3).
//
// Everything here is authored: no model runs, nothing is sent or stored.
// Every name is invented and was searched before ship (CONTENT.md §4).

/// The reference's five slots, in the order the model writes them.
public enum CitationSlot: Int, CaseIterable, Sendable, Hashable {
    case firstAuthor, year, title, journal, volumeAndPages
}

/// One candidate next piece and its illustrative chance.
public struct CitationCandidate: Equatable, Hashable, Sendable {
    /// As written in the reference ("14(3), 211–229").
    public let text: String
    /// The chance, in whole percent. Illustrative: authored for the lesson,
    /// not read from a real model.
    public let percent: Int
    /// What VoiceOver says, when the written form reads badly aloud.
    public let spoken: String

    public init(_ text: String, _ percent: Int, spoken: String? = nil) {
        self.text = text
        self.percent = percent
        self.spoken = spoken ?? text
    }
}

/// The step the student guesses the model "decided" to make it up at (the
/// prediction; the reveal refutes every one but the last).
public enum CitationStepGuess: String, CaseIterable, Sendable, Hashable {
    case author, journal, pageNumbers, noStep
}

/// The card's authored data and its pure logic. Every number the card
/// shows is in `candidates`; everything else (ranks, the references, the
/// counts) is derived here, and `CitationThatWasntTests` re-derives it.
public enum CitationContent {
    /// The three likeliest next pieces per slot, as the slate gives them
    /// (slate.json `data.slots`), with two changes recorded in CONTENT.md:
    /// "Thistlewood, M." is now "Fernwhistle, M." (Thistlewood is a real
    /// surname with real researchers), and the slate's "(third title)" is
    /// authored. The chances are illustrative.
    public static let candidates: [[CitationCandidate]] = [
        [
            CitationCandidate("Quillfeather, T.", 12),
            CitationCandidate("Ambervale, R.", 11),
            CitationCandidate("Fernwhistle, M.", 9),
        ],
        [
            CitationCandidate("2019", 24),
            CitationCandidate("2018", 21),
            CitationCandidate("2020", 19),
        ],
        [
            CitationCandidate("Houseplants and attention in secondary-school classrooms", 62),
            CitationCandidate("Indoor plants and student focus: a classroom study", 14),
            CitationCandidate("Classroom greenery and adolescent attention: a pilot study", 8),
        ],
        [
            CitationCandidate("Journal of Classroom Ecology", 41),
            CitationCandidate("Indoor Learning Review", 22),
            CitationCandidate("Bulletin of School Botany", 10),
        ],
        [
            CitationCandidate("14(3), 211\u{2013}229", 8, spoken: "volume 14, issue 3, pages 211 to 229"),
            CitationCandidate("9(2), 45\u{2013}61", 7, spoken: "volume 9, issue 2, pages 45 to 61"),
            CitationCandidate("22(1), 102\u{2013}118", 7, spoken: "volume 22, issue 1, pages 102 to 118"),
        ],
    ]

    /// The two authored paths: the candidate the model draws at each slot.
    /// Path 0 is the walk; path 1 is "Write it again" (slate.json
    /// `data.paths`).
    public static let paths: [[Int]] = [
        [0, 1, 0, 0, 0],
        [1, 0, 1, 1, 1],
    ]

    /// The path "Write it again" draws.
    public static let rewritePath = 1

    public static var slotCount: Int { CitationSlot.allCases.count }

    public static func candidates(_ slot: CitationSlot) -> [CitationCandidate] {
        candidates[slot.rawValue]
    }

    /// The candidate the model draws at `slot` on `path`.
    public static func pick(path: Int, slot: CitationSlot) -> Int {
        paths[path][slot.rawValue]
    }

    public static func picked(path: Int, slot: CitationSlot) -> CitationCandidate {
        candidates(slot)[pick(path: path, slot: slot)]
    }

    /// A candidate's bar from the top (1 = the top bar). Ties keep the order
    /// shown, so 9(2) at 7% is the second bar and 22(1) at 7% the third.
    public static func rank(of index: Int, in slot: CitationSlot) -> Int {
        let list = candidates(slot)
        let mine = list[index].percent
        let above = list.indices.filter { other in
            list[other].percent > mine || (list[other].percent == mine && other < index)
        }
        return above.count + 1
    }

    /// Whether the model's pick at `slot` on `path` is the top bar.
    public static func isTopBar(path: Int, slot: CitationSlot) -> Bool {
        rank(of: pick(path: path, slot: slot), in: slot) == 1
    }

    /// The Mac's arrows inside a slot's group: the candidate an arrow moves
    /// the keyboard to (it stops at the ends; it never picks).
    public static func neighbour(of index: Int, moving arrow: InteractiveArrow, in slot: CitationSlot) -> Int {
        let last = candidates(slot).count - 1
        return min(max(index + (arrow == .next ? 1 : -1), 0), last)
    }

    /// The slots on `path` where the model drew a bar that isn't the top
    /// one (the walk: only the year).
    public static func notTopSlots(path: Int) -> [CitationSlot] {
        CitationSlot.allCases.filter { !isTopBar(path: path, slot: $0) }
    }

    /// The drawn piece on `path` with the lowest chance (the walk: the
    /// pages, 8%). Ties keep the reference's order.
    public static func leastLikely(path: Int) -> CitationSlot {
        CitationSlot.allCases.min { picked(path: path, slot: $0).percent < picked(path: path, slot: $1).percent }
            ?? .firstAuthor
    }

    /// The drawn piece on `path` with the highest chance (the walk: the
    /// title, 62%). Ties keep the reference's order.
    public static func mostLikely(path: Int) -> CitationSlot {
        CitationSlot.allCases.max { picked(path: path, slot: $0).percent <= picked(path: path, slot: $1).percent }
            ?? .firstAuthor
    }

    /// The written pieces for `picks` (nil: not written yet).
    public static func pieces(_ picks: [Int?]) -> [String?] {
        CitationSlot.allCases.map { slot in
            picks.indices.contains(slot.rawValue) ? picks[slot.rawValue].map { candidates(slot)[$0].text } : nil
        }
    }

    /// The finished reference on `path`, as the card writes it.
    public static func reference(path: Int) -> String {
        reference(CitationSlot.allCases.map { picked(path: path, slot: $0).text })
    }

    /// Five pieces in the reference's layout: "Author (Year). Title.
    /// Journal, Volume(Issue), Pages."
    public static func reference(_ pieces: [String]) -> String {
        precondition(pieces.count == slotCount, "a reference has five pieces")
        return "\(pieces[0]) (\(pieces[1])). \(pieces[2]). \(pieces[3]), \(pieces[4])."
    }

    /// The finished reference on `path`, as VoiceOver says it.
    public static func spokenReference(path: Int) -> String {
        let spoken = CitationSlot.allCases.map { picked(path: path, slot: $0).spoken }
        return "\(spoken[0]), \(spoken[1]). \(spoken[2]). \(spoken[3]), \(spoken[4])."
    }

    /// Every number the card prints, in the order it prints them: each
    /// candidate's chance. (The steps' "1 of 3" and "Step 2 of 5" count
    /// `candidates` and `CitationSlot`.)
    public static var displayedPercents: [Int] {
        candidates.flatMap { $0.map(\.percent) }
    }

    /// Mata v. Avianca, as the lesson guide gives it (CURRICULUM_PROMPT,
    /// U1L3 Key examples, fact-check row 13; PR #44's server.js). The
    /// card's takeaway quotes its year and amount and nothing else.
    public static let guideMata = "Mata v. Avianca (2023): lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000."
    public static let mataYear = 2023
    public static let mataFine = 5_000
}

/// The walk through the five slots: at each one the student taps the
/// piece they think gets written, the model's pick is drawn (whatever they
/// guessed), and the piece drops into the reference. Pure, so the tests
/// can walk it. One slot is on screen at a time; the next appears when the
/// student asks for it, never by itself.
public struct CitationWalk: Equatable, Sendable {
    /// The authored path the model draws from.
    public let path: Int
    /// The slot on screen.
    public private(set) var slot: CitationSlot = .firstAuthor
    /// The student's guess at each slot (nil: not guessed yet).
    public private(set) var guesses: [Int?]
    /// The student has seen the fifth piece drop in and moved on.
    public private(set) var finished = false

    public init(path: Int = 0) {
        self.path = path
        guesses = Array(repeating: nil, count: CitationContent.slotCount)
    }

    /// Whether `slot`'s piece has been drawn (the student guessed it).
    public func isDrawn(_ slot: CitationSlot) -> Bool { guesses[slot.rawValue] != nil }

    public var drawnCount: Int { guesses.compactMap { $0 }.count }

    /// Whether every slot is drawn: the reference is complete.
    public var isComplete: Bool { drawnCount == CitationContent.slotCount }

    /// Whether the slot on screen still takes a guess.
    public var canGuess: Bool { !finished && !isDrawn(slot) }

    /// Guesses `index` at the slot on screen; the model's pick is drawn at
    /// once. False (and no change) once drawn, or for an index that isn't a
    /// candidate.
    @discardableResult
    public mutating func guess(_ index: Int) -> Bool {
        guard canGuess, CitationContent.candidates(slot).indices.contains(index) else { return false }
        guesses[slot.rawValue] = index
        return true
    }

    /// Whether "Next piece" (or, at the last slot, "See the finished
    /// reference") works.
    public var canAdvance: Bool { !finished && isDrawn(slot) }

    /// The next slot, or (after the last) the finished reference.
    @discardableResult
    public mutating func advance() -> Bool {
        guard canAdvance else { return false }
        if let next = CitationSlot(rawValue: slot.rawValue + 1) {
            slot = next
        } else {
            finished = true
        }
        return true
    }

    /// The model's pick at `slot` (drawn or not).
    public func pick(_ slot: CitationSlot) -> Int { CitationContent.pick(path: path, slot: slot) }

    /// The guess at `slot`, if any.
    public func guess(at slot: CitationSlot) -> Int? { guesses[slot.rawValue] }

    /// Whether the guess at `slot` matched the model's pick (nil: not
    /// guessed yet).
    public func guessMatched(_ slot: CitationSlot) -> Bool? {
        guess(at: slot).map { $0 == pick(slot) }
    }

    /// The picks drawn so far (nil: not drawn yet).
    public var picks: [Int?] {
        CitationSlot.allCases.map { isDrawn($0) ? pick($0) : nil }
    }

    /// "Step 2 of 5" and its VoiceOver line (the shared step-through block;
    /// the walk itself only goes forward).
    public var steps: StepThrough {
        StepThrough(count: CitationContent.slotCount, start: slot.rawValue)
    }

    /// A walk already through `last` (drawn), the student having guessed
    /// the top bar each time; `finished` when the student has moved past
    /// the fifth piece. For DEBUG states and the tests.
    public static func walked(through last: CitationSlot, finished: Bool = false, path: Int = 0) -> CitationWalk {
        var walk = CitationWalk(path: path)
        for slot in CitationSlot.allCases where slot.rawValue <= last.rawValue {
            let top = CitationContent.candidates(slot).indices.min {
                CitationContent.rank(of: $0, in: slot) < CitationContent.rank(of: $1, in: slot)
            } ?? 0
            walk.guess(top)
            if slot != last || finished { walk.advance() }
        }
        return walk
    }
}
