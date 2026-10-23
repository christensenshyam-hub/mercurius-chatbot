import Foundation
import Testing
@testable import LessonInteractives

/// The shared blocks' pure logic. The fixtures are the slate's own
/// authored data (SLATE.md, The Doubt Dial), so the block is shown to
/// reproduce a card's table before any card uses it; each card's own test
/// holds its content.
private struct Post: Sendable {
    let surprise: Double
    let real: Bool
}

/// SLATE.md, The Doubt Dial: five real posts (surprise 1–5) and five fakes
/// (2, 3, 4, 5, 5).
private let posts: [Post] = [1, 2, 3, 4, 5].map { Post(surprise: $0, real: true) }
    + [2, 3, 4, 5, 5].map { Post(surprise: $0, real: false) }

private let dial = ThresholdCounters(
    items: posts,
    score: { $0.surprise },
    rule: .atMost,
    stops: [.init("Believe everything", limit: 5), .init("Believe most", limit: 4), .init("Unsure", limit: 3),
            .init("Doubt most", limit: 1), .init("Doubt everything", limit: 0)],
    meters: [.init("Fakes you'd share") { post, shared in !post.real && shared },
             .init("Real stories you'd wave away") { post, shared in post.real && !shared }]
)

@Suite("Interactives: threshold counters")
struct ThresholdCountersTests {

    @Test("Every stop's counts equal the slate's authored table")
    func doubtDialTable() {
        #expect(dial.table == [[5, 0], [3, 1], [2, 2], [0, 4], [0, 5]])
        #expect(dial.smallestTotal == 4, "every stop makes at least 4 mistakes out of 10")
        #expect(dial.itemsIn(atStop: 0).count == 10)
        #expect(dial.itemsIn(atStop: 4).isEmpty)
    }

    @Test("The rule's direction, and stops clamped into range")
    func ruleAndClamp() {
        let line = ThresholdCounters(items: [1.0, 4.0, 7.0], score: { $0 }, rule: .atLeast,
                                     stops: [.init("Low", limit: 2), .init("High", limit: 6)],
                                     meters: [.init("Flagged") { _, flagged in flagged }])
        #expect(line.counts(atStop: 0) == [2])
        #expect(line.counts(atStop: 1) == [1])
        #expect(line.isIn(4.0, atStop: 0))
        #expect(!line.isIn(4.0, atStop: 1))
        #expect(line.clamped(-3) == 0)
        #expect(line.clamped(9) == 1)
    }

    @Test("Meters compare within a tolerance, said in words as well as a symbol")
    func comparison() {
        let close = MeterComparison(45, 47, tolerance: 2)
        #expect(close.isEqual && close.symbol == "=" && close.spoken == "about equal")
        let apart = MeterComparison(45, 23, tolerance: 2)
        #expect(!apart.isEqual && apart.symbol == "\u{2260}" && apart.spoken == "not equal")
        #expect(MeterComparison(0.5, 0.5, tolerance: 0).isEqual)
    }

    @Test("Rates: whole percents, half away from zero, 0 for an empty group")
    func rates() {
        #expect(InteractiveRates.percent(22, of: 181) == 12)
        #expect(InteractiveRates.percent(1, of: 8) == 13)
        #expect(InteractiveRates.percent(1, of: 200) == 1, "0.5 rounds away from zero")
        #expect(InteractiveRates.percent(3, of: 0) == 0)
    }

    @Test("The counters' sentence says every number they show")
    func summary() {
        let counts = dial.counts(atStop: 1)
        let tiles = zip(dial.meters, counts).map { CounterTile($0.name, value: $1) }
        let line = CounterTiles.summary(tiles)
        #expect(line == "Fakes you'd share: 3. Real stories you'd wave away: 1.")
        #expect(InteractiveAccessibility.numbersMissing(counts, from: line).isEmpty)
        #expect(InteractiveAccessibility.numbersMissing([3, 7], from: line) == [7])
        let compared = CounterTiles.summary(tiles, comparison: MeterComparison(3, 1, tolerance: 0))
        #expect(compared.hasSuffix("Not equal."))
    }
}

@Suite("Interactives: step-through")
struct StepThroughTests {

    @Test("Bounds: Back and Next stop at the ends")
    func bounds() {
        var steps = StepThrough(count: 3)
        #expect(steps.isFirst && !steps.canGoBack && steps.canGoNext)
        let r1 = steps.back()
        #expect(!r1)
        let r2 = steps.next()
        let r3 = steps.next()
        #expect(r2 && r3)
        #expect(steps.isLast && !steps.canGoNext)
        let r4 = steps.next()
        #expect(!r4)
        #expect(steps.index == 2 && steps.number == 3)
        let r5 = steps.back()
        #expect(r5)
        #expect(steps.index == 1)
        #expect(steps.furthest == 2, "Back doesn't undo what was shown")
        #expect(steps.hasShown(2) && !StepThrough(count: 3).hasShown(1))
        #expect(StepThrough(count: 3, start: 9).index == 2)
    }

    @Test("A gated step holds Next until the card opens it (the prediction)")
    func gate() {
        var steps = StepThrough(count: 6, gate: 2)
        steps.next()
        steps.next()
        #expect(steps.index == 2)
        #expect(!steps.canGoNext)
        let r6 = steps.next()
        #expect(!r6)
        steps.openGate()
        let r7 = steps.next()
        #expect(r7)
        #expect(steps.index == 3)
    }

    @Test("What VoiceOver says at each step")
    func announcements() {
        var steps = StepThrough(count: 6)
        #expect(steps.position == "Step 1 of 6")
        steps.next(); steps.next(); steps.next()
        #expect(steps.announcement("Plan. New line: add the link to the email.")
                == "Step 4 of 6: Plan. New line: add the link to the email.")
    }
}
