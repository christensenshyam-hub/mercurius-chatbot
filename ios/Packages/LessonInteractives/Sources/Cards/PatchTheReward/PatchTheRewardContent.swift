import Foundation

// Patch the Reward (U5L1, "The alignment problem"; SLATE.md §5): a toy boat
// race where the student writes the rule that pays the boat, and the boat
// takes the best-scoring route for that rule. Everything here is authored
// toy data and exact arithmetic over it (`RoutePlanner`), worked out on the
// device, the same every time: nothing is learned, sampled or fetched.
// docs/interactives/patch-the-reward/CONTENT.md lists every setting and
// every number this file produces; `PatchTheRewardTests` re-derives them.

// MARK: - The track

/// One waypoint of the toy track, in metres (x to the right, y down: the
/// track seen from above, as drawn).
public struct PatchWaypoint: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Either side of the finish line (the start is just past it).
        case line
        /// The loop the race is run on.
        case course
        /// Where the lagoon opens off the loop's far bend.
        case mouth
        /// A star target, among the lagoon's tight turns.
        case star
        /// The lagoon's open water.
        case openWater
    }

    public let name: String
    public let kind: Kind
    public let x: Double
    public let y: Double

    init(_ name: String, _ kind: Kind, _ x: Double, _ y: Double) {
        self.name = name
        self.kind = kind
        self.x = x
        self.y = y
    }
}

/// The toy track: a loop with a finish line and three numbered gates, and a
/// side lagoon with three star targets (they come back a few ticks after
/// they are hit) and open water around them. One-way everywhere but the
/// finish line, which the boat can cross both ways.
///
/// Each edge takes 1 or 2 ticks of the race clock, so its length in metres
/// over its ticks is the boat's speed there: about 13 m a tick on the loop,
/// 18 to 21 on the lagoon's open water (the toy's fastest water, part of
/// the card's label), 6 turning among the stars and 4 rocking over the
/// line. A lap of the loop is 20 ticks; the race is 3 laps in a 60-tick
/// clock, so finishing leaves no time for anything else.
public enum PatchTrack {
    /// The race: 3 laps.
    public static let laps = 3
    /// The clock: 60 ticks.
    public static let clockTicks = 60
    /// A star comes back this many ticks after it is hit.
    public static let starReturnTicks = 4
    /// The boat starts on the line, just past it.
    public static let start = 0

    public static let waypoints: [PatchWaypoint] = [
        .init("start", .line, 14.3, 32.0),            // 0: just past the finish line
        .init("course 1", .course, 19.9, 20.2),
        .init("course 2", .course, 30.9, 13.1),
        .init("gate 1", .course, 44.1, 12.0),         // 3
        .init("course 4", .course, 57.4, 12.0),
        .init("course 5", .course, 70.6, 12.0),
        .init("gate 2", .course, 83.9, 12.0),         // 6
        .init("course 7", .course, 96.8, 14.6),
        .init("lagoon turn-off", .course, 106.4, 23.4), // 8
        .init("course 9", .course, 110.0, 36.0),
        .init("course 10", .course, 106.4, 48.6),
        .init("course 11", .course, 96.8, 57.4),
        .init("course 12", .course, 83.9, 60.0),
        .init("course 13", .course, 70.6, 60.0),
        .init("gate 3", .course, 57.4, 60.0),         // 14
        .init("course 15", .course, 44.1, 60.0),
        .init("course 16", .course, 30.9, 58.9),
        .init("course 17", .course, 19.9, 51.8),
        .init("before the line", .line, 14.3, 40.0),  // 18
        .init("lagoon mouth", .mouth, 118.0, 36.0),   // 19
        .init("star 1", .star, 133.0, 29.0),          // 20
        .init("star 2", .star, 139.1, 39.5),
        .init("star 3", .star, 126.9, 39.5),
        .init("open water 1", .openWater, 124.4, 16.2), // 23
        .init("open water 2", .openWater, 140.0, 8.0),
        .init("open water 3", .openWater, 155.6, 16.2),
        .init("open water 4", .openWater, 162.0, 36.0),
        .init("open water 5", .openWater, 155.6, 55.8),
        .init("open water 6", .openWater, 140.0, 64.0),
        .init("open water 7", .openWater, 124.4, 55.8), // 29
    ]

    /// Gate number by waypoint: 1, 2 and 3, in race order.
    public static let gates: [Int: Int] = [3: 1, 6: 2, 14: 3]
    /// The star targets, in the order the lagoon's ring runs.
    public static let stars: [Int] = [20, 21, 22]
    /// Crossing the finish line forwards (the way the race runs)…
    public static let lineForward = (from: 18, to: 0)
    /// …and backwards.
    public static let lineBackward = (from: 0, to: 18)
    public static let mouth = 19
    public static let lagoonTurnOff = 8

    /// The authored links: (from, to, ticks). Lengths in metres are the
    /// straight-line distances between the waypoints, rounded
    /// (`metres(_:_:)`), so the picture is to scale.
    static let links: [(from: Int, to: Int, ticks: Int)] = {
        var links: [(from: Int, to: Int, ticks: Int)] = []
        // The loop, one way: start → gates 1, 2 → far bend → gate 3 → the line.
        for index in 0..<18 { links.append((index, index + 1, 1)) }
        // The finish line, both ways (slow: the boat turns round each time).
        links.append((18, 0, 2))
        links.append((0, 18, 2))
        // The lagoon: in from the far bend, back out to the loop just after.
        links.append((8, 19, 1))
        links.append((19, 9, 1))
        // The stars' ring, one way: tight turns, so 2 ticks a stretch.
        links.append((19, 20, 1))
        links.append((20, 21, 2))
        links.append((21, 22, 2))
        links.append((22, 20, 2))
        links.append((22, 19, 2))
        // The open water, one way round the stars.
        let openLoop = [19, 23, 24, 25, 26, 27, 28, 29]
        for (index, from) in openLoop.enumerated() {
            links.append((from, openLoop[(index + 1) % openLoop.count], 1))
        }
        return links
    }()

    /// The straight-line distance between two waypoints, in whole metres.
    public static func metres(_ from: Int, _ to: Int) -> Int {
        let a = waypoints[from], b = waypoints[to]
        return Int((((a.x - b.x) * (a.x - b.x)) + ((a.y - b.y) * (a.y - b.y))).squareRoot().rounded())
    }

    /// The track as the planner sees it.
    public static let graph = RouteGraph(
        nodeCount: waypoints.count,
        edges: links.map { RouteGraph.Edge(from: $0.from, to: $0.to, metres: metres($0.from, $0.to), ticks: $0.ticks) }
    )

    /// The edge from `from` to `to`, if there is one.
    public static func edge(_ from: Int, _ to: Int) -> RouteGraph.Edge? {
        graph.edges(from: from).first { $0.to == to }
    }

    // MARK: The picture's shapes (drawing only; the planner uses the graph)

    /// The area the picture shows, in metres.
    public static let bounds = (minX: 4.0, minY: 0.0, maxX: 170.0, maxY: 72.0)
    /// The loop's centre line: two straights between two half-circles
    /// (the course waypoints sit on it).
    public static let loopWestCentre = (x: 38.0, y: 36.0)
    public static let loopEastCentre = (x: 86.0, y: 36.0)
    public static let loopRadius = 24.0
    /// The channel's width.
    public static let channelWidth = 10.0
    /// The lagoon's water: an ellipse.
    public static let lagoonCentre = (x: 140.0, y: 36.0)
    public static let lagoonRadii = (x: 27.0, y: 33.0)
    /// The finish line, across the channel on the loop's near bend.
    public static let finishLine = (x: 14.0, y: 36.0)
}

// MARK: - The race state and its events

/// What the race keeps track of as the boat moves, whatever the rule pays
/// for: the next gate it needs, its laps, and when each star comes back.
public struct PatchRaceState: Hashable, Sendable {
    /// The gate the boat needs next (1, 2 or 3), or 4 once it has passed
    /// all three in order and needs the finish line.
    public var nextGate: Int
    public var laps: Int
    /// Ticks until each star is back (0: it's there).
    public var starTimers: [Int]

    public static let start = PatchRaceState(nextGate: 1, laps: 0,
                                             starTimers: Array(repeating: 0, count: PatchTrack.stars.count))

    /// The race is over: 3 laps done.
    public var isFinished: Bool { laps >= PatchTrack.laps }
}

/// What one move did.
public struct PatchEvent: Equatable, Sendable {
    public var hitStar = false
    public var crossedLine = false
    public var finishedLap = false
    public var metres = 0
}

extension PatchRaceState {
    /// The state after moving along `edge`, and what the move did. A lap
    /// counts when the boat crosses the line forwards after gates 1, 2 and
    /// 3 in order. A star is hit when the boat arrives while it's there.
    public func moving(along edge: RouteGraph.Edge) -> (state: PatchRaceState, event: PatchEvent) {
        var next = self
        var event = PatchEvent(metres: edge.metres)
        next.starTimers = starTimers.map { max($0 - edge.ticks, 0) }
        if let star = PatchTrack.stars.firstIndex(of: edge.to), next.starTimers[star] == 0 {
            event.hitStar = true
            next.starTimers[star] = PatchTrack.starReturnTicks
        }
        if let gate = PatchTrack.gates[edge.to], gate == nextGate {
            next.nextGate += 1
        }
        let forward = edge.from == PatchTrack.lineForward.from && edge.to == PatchTrack.lineForward.to
        let backward = edge.from == PatchTrack.lineBackward.from && edge.to == PatchTrack.lineBackward.to
        event.crossedLine = forward || backward
        if forward && nextGate == PatchTrack.gates.count + 1 {
            event.finishedLap = true
            next.laps += 1
            next.nextGate = 1
        }
        return (next, event)
    }
}

// MARK: - The rules

/// The rules the boat can be paid by: the 2016-style rule the card replays,
/// and the student's three patches.
public enum PatchRule: String, CaseIterable, Sendable, Hashable {
    /// Like the 2016 game: +10 per target hit.
    case targets
    /// A: +100 every time it crosses the finish line.
    case finishLine
    /// B: +1 for every metre it moves.
    case metres
    /// C: +100 for each full lap through gates 1, 2, 3 in order.
    case orderedLaps

    /// The three patches, in the order the chips show them.
    public static let patches: [PatchRule] = [.finishLine, .metres, .orderedLaps]

    /// "A", "B", "C"; nil for the 2016 rule.
    public var letter: String? {
        switch self {
        case .targets: return nil
        case .finishLine: return "A"
        case .metres: return "B"
        case .orderedLaps: return "C"
        }
    }

    /// What one unit is worth.
    public var pointsEach: Int {
        switch self {
        case .targets: return 10
        case .finishLine: return 100
        case .metres: return 1
        case .orderedLaps: return 100
        }
    }

    /// What this rule pays for a move.
    public func points(for event: PatchEvent) -> Int {
        switch self {
        case .targets: return event.hitStar ? pointsEach : 0
        case .finishLine: return event.crossedLine ? pointsEach : 0
        case .metres: return event.metres * pointsEach
        case .orderedLaps: return event.finishedLap ? pointsEach : 0
        }
    }
}

// MARK: - A rule's run

/// What the boat does under one rule: the best-scoring route there is (the
/// planner's), and what it adds up to.
public struct PatchRun: Equatable, Sendable {
    public let rule: PatchRule
    public let plan: RoutePlan<PatchRaceState>
    /// What each move did, in order.
    public let events: [PatchEvent]

    init(rule: PatchRule) {
        self.rule = rule
        plan = RoutePlanner.plan(PatchTrack.graph, from: PatchTrack.start, horizon: PatchTrack.clockTicks,
                                 initial: .start, isOver: \.isFinished) { state, edge in
            let move = state.moving(along: edge)
            return (move.state, rule.points(for: move.event))
        }
        var state = PatchRaceState.start
        var events: [PatchEvent] = []
        for step in plan.steps {
            let move = state.moving(along: step.edge)
            events.append(move.event)
            state = move.state
        }
        self.events = events
    }

    /// The rule's points: the best score any route gets.
    public var points: Int { plan.total }
    public var targetsHit: Int { events.filter(\.hitStar).count }
    public var lineCrossings: Int { events.filter(\.crossedLine).count }
    public var metres: Int { events.map(\.metres).reduce(0, +) }
    public var laps: Int { events.filter(\.finishedLap).count }
    /// It finished the race (3 laps).
    public var finished: Bool { laps >= PatchTrack.laps }
    /// The route as a lead-in and a loop, for the picture's numbered arrows.
    public var legs: RouteLegs { RouteLegs.of(plan.nodes) }

    /// The count the rule pays for (targets, crossings, metres or laps).
    public var paidCount: Int {
        switch rule {
        case .targets: return targetsHit
        case .finishLine: return lineCrossings
        case .metres: return metres
        case .orderedLaps: return laps
        }
    }

    /// The race at `tick` (0…60, fractional while it plays): where the boat
    /// is and which way it points, the points and laps so far, which stars
    /// are there, and the last stretch of its wake.
    public func frame(at tick: Double) -> PatchFrame {
        let tick = min(max(tick, 0), Double(PatchTrack.clockTicks))
        var points = 0
        var laps = 0
        var position = PatchTrack.waypoints[plan.start]
        var heading = Self.heading(plan.steps.first?.edge)
        var progress = 1.0
        var current: RoutePlan<PatchRaceState>.Step?
        for (index, step) in plan.steps.enumerated() {
            if Double(step.endTick) <= tick {
                points += step.reward
                if events[index].finishedLap { laps += 1 }
                position = PatchTrack.waypoints[step.edge.to]
                heading = Self.heading(step.edge)
            } else if Double(step.startTick) <= tick {
                current = step
                progress = (tick - Double(step.startTick)) / Double(step.edge.ticks)
                heading = Self.heading(step.edge)
                break
            } else {
                break
            }
        }
        var x = position.x, y = position.y
        if let current {
            let a = PatchTrack.waypoints[current.edge.from], b = PatchTrack.waypoints[current.edge.to]
            x = a.x + (b.x - a.x) * progress
            y = a.y + (b.y - a.y) * progress
        }
        var starsUp = Array(repeating: true, count: PatchTrack.stars.count)
        for (index, step) in plan.steps.enumerated() where events[index].hitStar {
            guard let star = PatchTrack.stars.firstIndex(of: step.edge.to) else { continue }
            let hit = Double(step.endTick)
            if hit <= tick && tick < hit + Double(PatchTrack.starReturnTicks) { starsUp[star] = false }
        }
        return PatchFrame(tick: tick, x: x, y: y, heading: heading, points: points, laps: laps, starsUp: starsUp,
                          wake: wake(endingAt: tick, x: x, y: y))
    }

    /// The boat's last few ticks of track, oldest first, ending where it is.
    private func wake(endingAt tick: Double, x: Double, y: Double) -> [PatchPoint] {
        let from = tick - PatchFrame.wakeTicks
        var points: [PatchPoint] = []
        for step in plan.steps where Double(step.endTick) > from && Double(step.startTick) < tick {
            let a = PatchTrack.waypoints[step.edge.from], b = PatchTrack.waypoints[step.edge.to]
            if points.isEmpty {
                let t = max(0, (from - Double(step.startTick)) / Double(step.edge.ticks))
                points.append(PatchPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            if Double(step.endTick) <= tick { points.append(PatchPoint(x: b.x, y: b.y)) }
        }
        points.append(PatchPoint(x: x, y: y))
        return points
    }

    private static func heading(_ edge: RouteGraph.Edge?) -> Double {
        guard let edge else { return -Double.pi / 2 }
        let a = PatchTrack.waypoints[edge.from], b = PatchTrack.waypoints[edge.to]
        return atan2(b.y - a.y, b.x - a.x)
    }
}

/// A point on the track, in metres.
public struct PatchPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

/// The race at one moment, for the picture and the counters.
public struct PatchFrame: Equatable, Sendable {
    /// How much of the boat's track its wake shows.
    public static let wakeTicks = 8.0

    public let tick: Double
    public let x: Double
    public let y: Double
    /// Radians, 0 pointing right, growing clockwise on screen.
    public let heading: Double
    public let points: Int
    public let laps: Int
    /// Whether each star is there (it's gone for a few ticks after a hit).
    public let starsUp: [Bool]
    public let wake: [PatchPoint]
}

// MARK: - The card's content

public enum PatchTheRewardContent {
    /// Every rule's run, planned once.
    public static let runs: [PatchRule: PatchRun] = {
        var runs: [PatchRule: PatchRun] = [:]
        for rule in PatchRule.allCases { runs[rule] = PatchRun(rule: rule) }
        return runs
    }()

    public static func run(_ rule: PatchRule) -> PatchRun {
        runs[rule] ?? PatchRun(rule: rule)
    }

    /// How long a run plays, start to finish (skippable; under Reduce
    /// Motion it doesn't play, its result shows at once).
    public static let playDuration: TimeInterval = 6

    /// The run's clock tick `elapsed` after it started playing.
    public static func tick(afterPlaying elapsed: TimeInterval) -> Double {
        min(max(elapsed / playDuration, 0), 1) * Double(PatchTrack.clockTicks)
    }

    /// The patches that get the boat to finish the race.
    public static var finishingPatches: [PatchRule] {
        PatchRule.patches.filter { run($0).finished }
    }

    /// The boat's speed on `edge`, in metres a tick.
    public static func speed(_ edge: RouteGraph.Edge) -> Double {
        Double(edge.metres) / Double(edge.ticks)
    }
}
