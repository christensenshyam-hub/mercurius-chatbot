import Foundation
import Testing
@testable import LessonInteractives

/// The RoutePlanner block (built for Patch the Reward): exact, counts ties,
/// respects the clock and the end of a run, and splits a route into a
/// lead-in and a loop for the picture.
@Suite("Blocks: RoutePlanner")
struct RoutePlannerTests {
    /// 0 → 1 → 2 → 0 (a triangle), plus 0 → 2 directly.
    static let triangle = RouteGraph(nodeCount: 3, edges: [
        .init(from: 0, to: 1, metres: 5, ticks: 1),
        .init(from: 1, to: 2, metres: 5, ticks: 1),
        .init(from: 2, to: 0, metres: 5, ticks: 1),
        .init(from: 0, to: 2, metres: 5, ticks: 2),
    ])

    @Test("The best route is found exactly, and it is the only best one")
    func unique() {
        // Pay 1 for each arrival at 2: in 4 ticks, 0→1→2→0 then 0→… can
        // reach 2 at most twice? 0→2 (t2), 2→0 (t3), 0→1 (t4): one. 0→1→2 (t2),
        // 2→0 (t3), 0→1 (t4): one. Both score 1 at 4 ticks: a tie.
        let tie = RoutePlanner.plan(Self.triangle, from: 0, horizon: 4, initial: 0, isOver: { _ in false }) { s, e in
            (s, e.to == 2 ? 1 : 0)
        }
        #expect(tie.total == 1)
        #expect(tie.optimalRoutes > 1)
        #expect(!tie.isUnique)
        // In 2 ticks there are exactly two ways to reach 2 (0→1→2 and 0→2):
        // pay the direct one more and it is the only best route.
        let direct = RoutePlanner.plan(Self.triangle, from: 0, horizon: 2, initial: 0, isOver: { _ in false }) { s, e in
            (s, e.from == 0 && e.to == 2 ? 3 : (e.to == 2 ? 1 : 0))
        }
        #expect(direct.total == 3)
        #expect(direct.isUnique)
        #expect(direct.nodes == [0, 2])
    }

    @Test("A move that wouldn't end by the clock isn't made")
    func clock() {
        // From 0 only the 2-tick edge reaches 2; with 1 tick left it can't.
        let plan = RoutePlanner.plan(Self.triangle, from: 0, horizon: 1, initial: 0, isOver: { _ in false }) { s, e in
            (s, e.to == 2 ? 10 : 1)
        }
        #expect(plan.nodes == [0, 1])
        #expect(plan.total == 1)
        #expect(plan.endTick == 1)
    }

    @Test("A run ends when its state says so")
    func over() {
        // The state counts moves; the run is over after two.
        let plan = RoutePlanner.plan(Self.triangle, from: 0, horizon: 50, initial: 0, isOver: { $0 >= 2 }) { s, _ in
            (s + 1, 1)
        }
        #expect(plan.steps.count == 2)
        #expect(plan.total == 2)
    }

    @Test("A route reads as a lead-in and the loop it repeats")
    func legs() {
        // 5, 6, then 1-2-3 round and round, ending part-way.
        let legs = RouteLegs.of([5, 6, 1, 2, 3, 1, 2, 3, 1, 2])
        #expect(legs.lead == [5, 6, 1])
        #expect(legs.loop == [1, 2, 3, 1])
        #expect(legs.loopPasses == 2)
        #expect(legs.drawn.count == 2)
        // A shuttle is a loop of two.
        let shuttle = RouteLegs.of([0, 9, 0, 9, 0])
        #expect(shuttle.lead.isEmpty && shuttle.loop == [0, 9, 0] && shuttle.loopPasses == 2)
        // A route that never repeats is all lead.
        let line = RouteLegs.of([1, 2, 3, 4])
        #expect(line.lead == [1, 2, 3, 4] && line.loop.isEmpty && line.drawn == [[1, 2, 3, 4]])
    }

    @Test("Nothing it returns can be encoded")
    func notCodable() {
        #expect(!((Self.triangle as Any) is any Encodable))
        #expect(!((RouteLegs.of([1, 2, 1, 2]) as Any) is any Encodable))
    }
}
