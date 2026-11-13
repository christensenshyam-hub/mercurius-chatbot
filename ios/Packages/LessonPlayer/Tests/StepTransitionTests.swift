import Testing
@testable import LessonPlayer

/// The state behind the two-phase step change (`StepTransition`): the step
/// on screen fades out completely before the next one is inserted.
@Suite("Step transition")
struct StepTransitionTests {

    @Test("A step change leaves first, then shows the new step")
    func twoPhases() {
        var t = StepTransition(stepId: "a")
        #expect(t.phase == .shown)

        #expect(t.stepChanged(to: "b") == .startLeaving(generation: 1))
        // Still showing the outgoing step while it fades.
        #expect(t.displayedStepId == "a")
        #expect(t.targetStepId == "b")
        #expect(t.phase == .leaving)

        #expect(t.leaveFinished(generation: 1) == "b")
        #expect(t.displayedStepId == "b")
        #expect(t.phase == .shown)
    }

    @Test("Only one step is ever displayed: the new one appears only after the leave")
    func neverTwoSteps() {
        var t = StepTransition(stepId: "a")
        _ = t.stepChanged(to: "b")
        // Between the change and the end of the leave, the displayed step is
        // the outgoing one, and it is the only one.
        #expect(t.displayedStepId == "a")
        _ = t.leaveFinished(generation: t.generation)
        #expect(t.displayedStepId == "b")
    }

    @Test("The same step again changes nothing")
    func sameStep() {
        var t = StepTransition(stepId: "a")
        #expect(t.stepChanged(to: "a") == .none)
        #expect(t.phase == .shown)
        #expect(t.generation == 0)
    }

    @Test("Rapid changes mid-leave end on the latest step, with one leave")
    func rapidChangesDuringLeave() {
        var t = StepTransition(stepId: "a")
        #expect(t.stepChanged(to: "b") == .startLeaving(generation: 1))
        #expect(t.stepChanged(to: "c") == .none)
        #expect(t.stepChanged(to: "d") == .none)
        #expect(t.leaveFinished(generation: 1) == "d")
        #expect(t.displayedStepId == "d")
        #expect(t.phase == .shown)
    }

    @Test("A change while the new step is still arriving starts a fresh leave")
    func changeDuringEnter() {
        var t = StepTransition(stepId: "a")
        _ = t.stepChanged(to: "b")
        _ = t.leaveFinished(generation: 1)
        // "b" is animating in; the model moves on again.
        #expect(t.stepChanged(to: "c") == .startLeaving(generation: 2))
        #expect(t.displayedStepId == "b")
        #expect(t.leaveFinished(generation: 2) == "c")
        #expect(t.phase == .shown)
    }

    @Test("A stale leave finishing is ignored, and the current one still lands")
    func staleLeaveIgnored() {
        var t = StepTransition(stepId: "a")
        _ = t.stepChanged(to: "b")
        _ = t.leaveFinished(generation: 1)
        _ = t.stepChanged(to: "c")
        // The first leave's timer firing late must not swap anything.
        #expect(t.leaveFinished(generation: 1) == nil)
        #expect(t.phase == .leaving)
        #expect(t.leaveFinished(generation: 2) == "c")
    }

    @Test("Returning to the displayed step mid-leave fades it back in, never stuck hidden")
    func returnToDisplayed() {
        var t = StepTransition(stepId: "a")
        _ = t.stepChanged(to: "b")
        #expect(t.stepChanged(to: "a") == .returnToShown)
        #expect(t.phase == .shown)
        #expect(t.displayedStepId == "a")
        // The cancelled leave's timer can't hide or swap anything.
        #expect(t.leaveFinished(generation: 1) == nil)
        #expect(t.phase == .shown)
        #expect(t.displayedStepId == "a")
    }

    @Test("Every sequence of changes and finishes ends shown on the latest step")
    func alwaysSettles() {
        let ids = ["a", "b", "c", "d"]
        // Deterministic walk over many interleavings of changes and late,
        // early or missing leave completions.
        for seed in 0..<500 {
            var rng = SplitMix(seed: UInt64(seed))
            var t = StepTransition(stepId: "a")
            var latest = "a"
            var issued: [Int] = []
            for _ in 0..<12 {
                if rng.next() % 3 == 0, let g = issued.randomElement(using: &rng) {
                    _ = t.leaveFinished(generation: g)
                } else {
                    latest = ids[Int(rng.next() % UInt64(ids.count))]
                    if case .startLeaving(let g) = t.stepChanged(to: latest) { issued.append(g) }
                }
            }
            // The view always finishes the newest leave it started.
            if t.phase == .leaving { _ = t.leaveFinished(generation: t.generation) }
            #expect(t.phase == .shown, "seed \(seed)")
            #expect(t.displayedStepId == latest, "seed \(seed)")
        }
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
