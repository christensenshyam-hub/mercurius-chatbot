import Foundation

// The Doubt Dial (U6L4, "Misinformation and the liar's dividend"; SLATE.md
// card 1, sketches/doubt-dial.svg). Ten one-line posts about a made-up
// town, 5 real and 5 fake, each with a "how surprising" score. A five-stop
// dial shares or waves away each post by that score alone, and two
// counters count the two kinds of mistake. No stop gets below 4 mistakes
// out of 10. A separate "Check first" step shows what checking found:
// no fake shared, no real story waved away, 2 posts "not sure yet".
//
// Everything here is authored toy data and the arithmetic over it: every
// number the card shows is counted from `posts` and `stops` below
// (`DoubtDialTests` re-derives each one, and tools/check_slate_numbers.py
// in the slate is the cross-check). The card shows no statistics.

/// What the student guesses before turning the dial: which setting will
/// fool them least.
public enum DoubtDialGuess: String, CaseIterable, Hashable, Sendable {
    case believeEverything
    case middle
    case doubtEverything
}

/// One post in the made-up feed.
public struct DoubtDialPost: Equatable, Hashable, Sendable, Identifiable {
    /// What checking found (SIFT's "find better coverage" and "trace it to
    /// the original"), authored like the post.
    public enum Finding: Equatable, Hashable, Sendable {
        /// Checking found it real: share it.
        case real
        /// Checking found it fake: don't share it.
        case fake
        /// Checking couldn't settle it yet: don't share it yet.
        case notSureYet
    }

    public let id: Int
    /// The post, as one line.
    public let title: String
    /// We wrote it, so we know: true for the 5 real posts.
    public let isReal: Bool
    /// How surprising it looks, 1 to 5 (the dots).
    public let surprise: Int
    /// What checking found, as one line.
    public let checkLine: String
    public let finding: Finding

    public init(id: Int, title: String, isReal: Bool, surprise: Int, checkLine: String, finding: Finding) {
        self.id = id
        self.title = title
        self.isReal = isReal
        self.surprise = surprise
        self.checkLine = checkLine
        self.finding = finding
    }
}

/// What a post shows: what the dial did with it, or what checking found.
public enum DoubtDialVerdict: Equatable, Hashable, Sendable {
    /// The dial (or checking) shares it.
    case shared
    /// The dial waves it away.
    case wavedAway
    /// Checking found it fake, so it isn't shared.
    case notShared
    /// Checking couldn't settle it: not shared yet.
    case notSureYet

    /// Whether the post ends up shared.
    public var isShared: Bool { self == .shared }
}

/// The card's two kinds of mistake at one setting, and the third count
/// "Check first" adds.
public struct DoubtDialTally: Equatable, Sendable {
    /// Fakes you'd share.
    public let fakesShared: Int
    /// Real stories you'd wave away.
    public let realWavedAway: Int
    /// Posts left "not sure yet" (checking only; 0 on the dial).
    public let notSureYet: Int

    public init(fakesShared: Int, realWavedAway: Int, notSureYet: Int = 0) {
        self.fakesShared = fakesShared
        self.realWavedAway = realWavedAway
        self.notSureYet = notSureYet
    }

    /// Both kinds of mistake together.
    public var mistakes: Int { fakesShared + realWavedAway }
}

/// The authored feed, the dial's stops and every count the card shows.
public enum DoubtDialContent {
    /// The made-up town (searched in GeoNames and USGS GNIS: no place of
    /// this name; CONTENT.md §5).
    public static let town = "Port Avery"

    /// The feed, least surprising first, so the dial's cut moves down the
    /// list. Every surprise level from 2 to 5 holds a real post and a fake
    /// one: surprising is not the same as fake.
    public static let posts: [DoubtDialPost] = [
        DoubtDialPost(id: 1, title: "Library lends fishing rods", isReal: true, surprise: 1,
                      checkLine: "The library\u{2019}s own page lists the rods, and the Port Avery Gazette ran it too.",
                      finding: .real),
        DoubtDialPost(id: 2, title: "Ferry fares drop to $1 for the summer", isReal: true, surprise: 2,
                      checkLine: "The ferry company and the Port Avery Gazette both report it.",
                      finding: .real),
        DoubtDialPost(id: 3, title: "School board adds Saturday classes", isReal: false, surprise: 2,
                      checkLine: "The school board\u{2019}s meeting notes show no such vote, and the Gazette hasn\u{2019}t reported it.",
                      finding: .fake),
        DoubtDialPost(id: 4, title: "May snow closes schools for a day", isReal: true, surprise: 3,
                      checkLine: "The school district\u{2019}s notice and the town\u{2019}s weather report both say so.",
                      finding: .real),
        DoubtDialPost(id: 5, title: "Water tower to be torn down Friday", isReal: false, surprise: 3,
                      checkLine: "One post, and no town notice yet.",
                      finding: .notSureYet),
        DoubtDialPost(id: 6, title: "A seal naps on the ferry dock, and the ferry waits", isReal: true, surprise: 4,
                      checkLine: "One video, posted an hour ago. No one else has it yet.",
                      finding: .notSureYet),
        DoubtDialPost(id: 7, title: "Photo: a shark in the town pool", isReal: false, surprise: 4,
                      checkLine: "Reverse search: this photo first appeared years ago, somewhere else. A real photo, a false story.",
                      finding: .fake),
        DoubtDialPost(id: 8, title: "Council votes to paint the old bridge purple", isReal: true, surprise: 5,
                      checkLine: "The council\u{2019}s meeting notes record the vote, and the Gazette covered it.",
                      finding: .real),
        DoubtDialPost(id: 9, title: "Leaked audio: the mayor cancels summer break", isReal: false, surprise: 5,
                      checkLine: "The words come from an old speech, cut up and put back in a new order. The full speech is on the town\u{2019}s site.",
                      finding: .fake),
        DoubtDialPost(id: 10, title: "Video: lightning knocks out the lighthouse", isReal: false, surprise: 5,
                      checkLine: "The harbor\u{2019}s live camera shows the lighthouse lit tonight.",
                      finding: .fake),
    ]

    /// The surprise scale's top: the dots go 1 to this.
    public static let maxSurprise = 5

    /// The dial's five stops: a post is shared when its surprise is at most
    /// the stop's limit (SLATE.md: 5, 4, 3, 1, 0).
    public static let stopLimits: [Int] = [5, 4, 3, 1, 0]

    /// The dial as the shared block: stops over scored posts, and the two
    /// counters ("Fakes you'd share", "Real stories you'd wave away").
    public static let dial = ThresholdCounters(
        items: posts,
        score: { Double($0.surprise) },
        rule: .atMost,
        stops: zip(DoubtDialCopy.stops, stopLimits).map { ThresholdCounters<DoubtDialPost>.Stop($0, limit: Double($1)) },
        meters: [
            .init(DoubtDialCopy.fakesSharedLabel) { post, shared in !post.isReal && shared },
            .init(DoubtDialCopy.realWavedAwayLabel) { post, shared in post.isReal && !shared },
        ]
    )

    // MARK: Counts

    public static var postCount: Int { posts.count }
    public static var realCount: Int { posts.filter(\.isReal).count }
    public static var fakeCount: Int { posts.filter { !$0.isReal }.count }

    /// The stop the dial starts at once a guess is locked: believe
    /// everything, so turning it up adds doubt.
    public static let startStop = 0

    /// The stops a guess names: one end, or the three in the middle.
    public static func stops(for guess: DoubtDialGuess) -> [Int] {
        let last = stopLimits.count - 1
        switch guess {
        case .believeEverything: return [0]
        case .middle: return Array(1..<last)
        case .doubtEverything: return [last]
        }
    }

    /// The stop a guess is shown at (DEBUG shots): its end, or the middle.
    public static func representativeStop(for guess: DoubtDialGuess) -> Int {
        let named = stops(for: guess)
        return named[named.count / 2]
    }

    /// A stop's index, clamped into range.
    public static func clamped(_ stop: Int) -> Int { dial.clamped(stop) }

    /// What the dial does with `post` at `stop`.
    public static func verdict(_ post: DoubtDialPost, atStop stop: Int) -> DoubtDialVerdict {
        dial.isIn(post, atStop: clamped(stop)) ? .shared : .wavedAway
    }

    /// What checking does with `post`.
    public static func checkVerdict(_ post: DoubtDialPost) -> DoubtDialVerdict {
        switch post.finding {
        case .real: return .shared
        case .fake: return .notShared
        case .notSureYet: return .notSureYet
        }
    }

    /// Whether `verdict` on `post` is one of the two mistakes the counters
    /// count: a fake shared, or a real story waved away (or not shared).
    /// "Not sure yet" is neither: it is an honest answer, not a mistake.
    public static func isMistake(_ post: DoubtDialPost, _ verdict: DoubtDialVerdict) -> Bool {
        switch verdict {
        case .shared: return !post.isReal
        case .wavedAway, .notShared: return post.isReal
        case .notSureYet: return false
        }
    }

    /// The posts the feed marks "Mistake" at `stop` (or, `checking`, after
    /// checking): the counters' posts, one by one.
    public static func mistakes(atStop stop: Int, checking: Bool) -> [DoubtDialPost] {
        posts.filter { isMistake($0, checking ? checkVerdict($0) : verdict($0, atStop: stop)) }
    }

    /// The two counters at `stop`, counted by the block.
    public static func tally(atStop stop: Int) -> DoubtDialTally {
        let counts = dial.counts(atStop: clamped(stop))
        return DoubtDialTally(fakesShared: counts[0], realWavedAway: counts[1])
    }

    /// Every stop's counters: [fakes shared, real waved away] per stop.
    public static var table: [[Int]] { dial.table }

    /// Mistakes out of `postCount` at each stop.
    public static var mistakesByStop: [Int] { table.map { $0.reduce(0, +) } }

    /// The fewest mistakes any stop makes ("every stop makes at least 4").
    public static var fewestMistakes: Int { dial.smallestTotal }

    /// The mistakes every middle stop makes, if they all make the same
    /// number ("every setting in the middle still makes 4"); nil otherwise.
    public static var middleMistakes: Int? {
        let middle = Set(stops(for: .middle).map { mistakesByStop[$0] })
        return middle.count == 1 ? middle.first : nil
    }

    /// What checking leaves: fakes shared, real stories waved away, and
    /// posts not sure yet.
    public static var checkTally: DoubtDialTally {
        let verdicts = posts.map { ($0, checkVerdict($0)) }
        return DoubtDialTally(
            fakesShared: verdicts.filter { !$0.0.isReal && $0.1.isShared }.count,
            realWavedAway: verdicts.filter { $0.0.isReal && ($0.1 == .wavedAway || $0.1 == .notShared) }.count,
            notSureYet: verdicts.filter { $0.1 == .notSureYet }.count
        )
    }

    /// The posts shared at `stop` (or, `checking`, after checking).
    public static func sharedCount(atStop stop: Int, checking: Bool) -> Int {
        posts.filter { (checking ? checkVerdict($0) : verdict($0, atStop: stop)).isShared }.count
    }
}
