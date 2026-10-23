import Foundation

/// A stop control over items that each have a score, and two or three
/// counters that count, at each stop, the items that are in or out
/// (BUILD_PLAN.md §1.6). Built for The Doubt Dial (a post is shared when
/// its surprise is at most the stop's limit; the meters count fakes shared
/// and real stories waved away) and reused by Two Tests, One Line (a risk
/// line; meters per group, compared within a tolerance).
///
/// Pure: every count is worked out from the items, so a card's test can
/// hold every stop against the table its slate entry authors, and the
/// view never shows a number it didn't count.
public struct ThresholdCounters<Item: Sendable>: Sendable {
    /// Which side of a stop's limit an item must be on to be "in".
    public enum Rule: Sendable {
        /// In when `score <= limit` (the Doubt Dial: shared when no more
        /// surprising than the stop allows).
        case atMost
        /// In when `score >= limit` (a risk line: flagged at or above it).
        case atLeast
    }

    /// One stop of the control.
    public struct Stop: Equatable, Sendable {
        public let label: String
        public let limit: Double

        public init(_ label: String, limit: Double) {
            self.label = label
            self.limit = limit
        }
    }

    /// One counter: its name and which (item, in?) pairs it counts.
    public struct Meter: Sendable {
        public let name: String
        public let counts: @Sendable (Item, Bool) -> Bool

        public init(_ name: String, counts: @escaping @Sendable (Item, Bool) -> Bool) {
            self.name = name
            self.counts = counts
        }
    }

    public let items: [Item]
    public let score: @Sendable (Item) -> Double
    public let rule: Rule
    public let stops: [Stop]
    public let meters: [Meter]

    public init(items: [Item], score: @escaping @Sendable (Item) -> Double, rule: Rule,
                stops: [Stop], meters: [Meter]) {
        self.items = items
        self.score = score
        self.rule = rule
        self.stops = stops
        self.meters = meters
    }

    /// Whether `item` is in at stop `stop`.
    public func isIn(_ item: Item, atStop stop: Int) -> Bool {
        let limit = stops[stop].limit
        switch rule {
        case .atMost: return score(item) <= limit
        case .atLeast: return score(item) >= limit
        }
    }

    /// Each meter's count at stop `stop`, in `meters` order.
    public func counts(atStop stop: Int) -> [Int] {
        meters.map { meter in items.filter { meter.counts($0, isIn($0, atStop: stop)) }.count }
    }

    /// Every stop's counts, in `stops` order.
    public var table: [[Int]] { stops.indices.map(counts(atStop:)) }

    /// The items that are in at stop `stop`.
    public func itemsIn(atStop stop: Int) -> [Item] { items.filter { isIn($0, atStop: stop) } }

    /// The fewest the meters add up to, over every stop ("every stop makes
    /// at least 4 mistakes out of 10").
    public var smallestTotal: Int { table.map { $0.reduce(0, +) }.min() ?? 0 }

    /// The stop's index, clamped into range.
    public func clamped(_ stop: Int) -> Int { min(max(stop, 0), max(stops.count - 1, 0)) }
}

/// Two meters compared: "=" when within `tolerance`, else "≠". The
/// symbol is never the only sign: `spoken` says it in words.
public struct MeterComparison: Equatable, Sendable {
    public let a: Double
    public let b: Double
    public let tolerance: Double

    public init(_ a: Double, _ b: Double, tolerance: Double) {
        self.a = a
        self.b = b
        self.tolerance = tolerance
    }

    public var isEqual: Bool { abs(a - b) <= tolerance + 1e-9 }

    public var symbol: String { isEqual ? InteractiveShellCopy.equalSymbol : InteractiveShellCopy.notEqualSymbol }
    public var spoken: String { isEqual ? InteractiveShellCopy.equalSpoken : InteractiveShellCopy.notEqualSpoken }
}

/// A count as a share of its group, rounded the way a card prints it
/// ("12%"): our arithmetic, so a card labels it.
public enum InteractiveRates {
    /// `count` of `total` as a whole percent (half away from zero); 0 for
    /// an empty group.
    public static func percent(_ count: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(count) * 100 / Double(total)).rounded(.toNearestOrAwayFromZero))
    }
}
