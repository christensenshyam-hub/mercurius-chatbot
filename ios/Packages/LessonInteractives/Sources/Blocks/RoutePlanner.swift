import Foundation

/// A toy map for `RoutePlanner`: waypoints (by index) joined by one-way
/// edges, each with a length in metres and the clock ticks it takes. A
/// two-way stretch is two edges.
public struct RouteGraph: Equatable, Sendable {
    public struct Edge: Equatable, Hashable, Sendable, CustomStringConvertible {
        public let from: Int
        public let to: Int
        /// Its length, in whole metres.
        public let metres: Int
        /// How many clock ticks it takes (1 or more).
        public let ticks: Int

        public init(from: Int, to: Int, metres: Int, ticks: Int) {
            precondition(ticks >= 1, "an edge takes at least one tick")
            self.from = from
            self.to = to
            self.metres = metres
            self.ticks = ticks
        }

        public var description: String { "\(from)→\(to) (\(metres) m, \(ticks) t)" }
    }

    public let nodeCount: Int
    /// Every edge, in the order they were authored. A waypoint's edges are
    /// tried in this order (`edges(from:)`), which only matters for a tie,
    /// and a card's test asserts it has none (`RoutePlan.isUnique`).
    public let edges: [Edge]
    private let outgoing: [[Edge]]

    public init(nodeCount: Int, edges: [Edge]) {
        precondition(edges.allSatisfy { (0..<nodeCount).contains($0.from) && (0..<nodeCount).contains($0.to) },
                     "an edge joins two waypoints of the graph")
        self.nodeCount = nodeCount
        self.edges = edges
        var outgoing = Array(repeating: [Edge](), count: nodeCount)
        for edge in edges { outgoing[edge.from].append(edge) }
        self.outgoing = outgoing
    }

    /// The edges that leave `node`.
    public func edges(from node: Int) -> [Edge] {
        outgoing.indices.contains(node) ? outgoing[node] : []
    }
}

/// The best-scoring route through a `RouteGraph`, worked out exactly, and
/// how many routes tie with it.
public struct RoutePlan<State: Hashable & Sendable>: Equatable, Sendable {
    /// One move of the route.
    public struct Step: Equatable, Sendable {
        public let edge: RouteGraph.Edge
        /// The tick the move starts on (it arrives at `startTick + edge.ticks`).
        public let startTick: Int
        /// What the rule paid for it.
        public let reward: Int
        /// The run's state once it arrived.
        public let state: State

        public var endTick: Int { startTick + edge.ticks }
    }

    public let start: Int
    public let initial: State
    public let steps: [Step]
    /// What the whole route scores: the best any route can.
    public let total: Int
    /// How many different routes score `total` (capped at
    /// `RoutePlanner.countCap`). One means the route is the only best one.
    public let optimalRoutes: Int

    /// Whether no other route scores as much.
    public var isUnique: Bool { optimalRoutes == 1 }

    /// The waypoints in order, the start first.
    public var nodes: [Int] { [start] + steps.map(\.edge.to) }

    /// The tick the last move ends on (the clock, unless no move fit).
    public var endTick: Int { steps.last?.endTick ?? 0 }
}

/// A route seen as at most two legs, for a picture with numbered arrows:
/// a lead-in, then a loop it goes round again and again ("into the lagoon,
/// then round and round the stars"). The loop's last waypoint is its first.
public struct RouteLegs: Equatable, Sendable {
    /// The waypoints before the loop starts (empty, or two or more).
    public let lead: [Int]
    /// One pass of the loop (empty when the route never repeats).
    public let loop: [Int]
    /// How many whole passes of the loop the route makes.
    public let loopPasses: Int

    public init(lead: [Int], loop: [Int], loopPasses: Int) {
        self.lead = lead
        self.loop = loop
        self.loopPasses = loopPasses
    }

    /// The legs that are drawn, numbered from 1 in this order.
    public var drawn: [[Int]] { [lead, loop].filter { $0.count >= 2 } }

    /// `nodes` as a lead-in and the shortest loop it then repeats (at least
    /// twice): the earliest start, then the shortest loop.
    public static func of(_ nodes: [Int]) -> RouteLegs {
        let count = nodes.count
        guard count >= 3 else { return RouteLegs(lead: nodes, loop: [], loopPasses: 0) }
        for lead in 0..<(count - 1) {
            let rest = count - 1 - lead
            guard rest >= 2 else { break }
            for length in 1...(rest / 2) where isPeriodic(nodes, from: lead, period: length) {
                let loop = Array(nodes[lead...(lead + length)])
                guard loop.first == loop.last else { continue }
                return RouteLegs(lead: lead > 0 ? Array(nodes[0...lead]) : [], loop: loop, loopPasses: rest / length)
            }
        }
        return RouteLegs(lead: nodes, loop: [], loopPasses: 0)
    }

    private static func isPeriodic(_ nodes: [Int], from start: Int, period: Int) -> Bool {
        var index = start
        while index + period < nodes.count {
            if nodes[index] != nodes[index + period] { return false }
            index += 1
        }
        return true
    }
}

/// The exact route planner (BUILD_PLAN.md §1.6's RoutePlanner block, built
/// for Patch the Reward): dynamic programming over (waypoint, tick, the
/// rule's state), so the route it gives is the best-scoring one there is,
/// not a guess, and it also counts how many routes tie for best. A card's
/// test asserts its routes are the only best ones.
///
/// The boat always moves: at each waypoint it takes one of the edges that
/// leave it. A move that wouldn't end by the clock (`horizon`) isn't made,
/// and the run ends when no move fits or `isOver` says so (the race is
/// finished). It runs offline: nothing is learned, sampled or fetched.
public enum RoutePlanner {
    /// The tie count stops here (it only has to tell 1 from more).
    public static let countCap = 1_000_000

    private struct Key<State: Hashable>: Hashable {
        let node: Int
        let tick: Int
        let state: State
    }

    private struct Entry {
        let value: Int
        let count: Int
        let best: RouteGraph.Edge?
    }

    /// The best-scoring route from `start` within `horizon` ticks.
    ///
    /// - Parameters:
    ///   - initial: the rule's state at the start (laps, gates, timers…).
    ///   - isOver: whether a state ends the run early (a finished race).
    ///   - step: a move's new state and what the rule pays for it.
    public static func plan<State: Hashable & Sendable>(
        _ graph: RouteGraph, from start: Int, horizon: Int, initial: State,
        isOver: (State) -> Bool,
        step: (State, RouteGraph.Edge) -> (state: State, reward: Int)
    ) -> RoutePlan<State> {
        var memo: [Key<State>: Entry] = [:]

        func solve(_ node: Int, _ tick: Int, _ state: State) -> Entry {
            let key = Key(node: node, tick: tick, state: state)
            if let known = memo[key] { return known }
            var best: Entry?
            if !isOver(state) {
                for edge in graph.edges(from: node) where tick + edge.ticks <= horizon {
                    let move = step(state, edge)
                    let next = solve(edge.to, tick + edge.ticks, move.state)
                    let value = next.value + move.reward
                    if let current = best {
                        if value > current.value {
                            best = Entry(value: value, count: next.count, best: edge)
                        } else if value == current.value {
                            best = Entry(value: value, count: min(current.count + next.count, countCap),
                                         best: current.best)
                        }
                    } else {
                        best = Entry(value: value, count: next.count, best: edge)
                    }
                }
            }
            let entry = best ?? Entry(value: 0, count: 1, best: nil)
            memo[key] = entry
            return entry
        }

        let root = solve(start, 0, initial)
        var steps: [RoutePlan<State>.Step] = []
        var node = start
        var tick = 0
        var state = initial
        while let edge = solve(node, tick, state).best {
            let move = step(state, edge)
            steps.append(.init(edge: edge, startTick: tick, reward: move.reward, state: move.state))
            node = edge.to
            tick += edge.ticks
            state = move.state
        }
        return RoutePlan(start: start, initial: initial, steps: steps, total: root.value, optimalRoutes: root.count)
    }
}
