import Foundation
import Testing
@testable import LessonPlayer

@Suite("Answer feedback choreography")
struct FeedbackChoreographyTests {

    private func times(_ outcome: FeedbackChoreography.Outcome) -> [FeedbackChoreography.Beat: TimeInterval] {
        Dictionary(uniqueKeysWithValues: FeedbackChoreography.beats(for: outcome).map { ($0.beat, $0.at) })
    }

    @Test("Correct: result at once, panel at 0.15 s, no revealed answer")
    func correctBeats() {
        let t = times(.correct)
        #expect(t[.result] == 0)
        #expect(t[.panel] == 0.15)
        #expect(t[.revealAnswer] == nil)
        #expect(t[.settled] == 0.6)
    }

    @Test("Wrong on a revealing step: the right answer turns green 0.25 s after the mistake")
    func wrongRevealing() {
        let t = times(.wrong(revealsAnswer: true))
        #expect(t[.result] == 0)
        #expect(t[.panel] == 0.15)
        #expect(t[.revealAnswer] == 0.25)
        #expect(t[.settled]! > t[.revealAnswer]!)
    }

    @Test("Wrong on a Try again step: the right answer is never revealed")
    func wrongTryAgain() {
        #expect(times(.wrong(revealsAnswer: false))[.revealAnswer] == nil)
    }

    @Test("Beats are in time order and the sequence settles after the shake")
    func ordered() {
        for outcome in [FeedbackChoreography.Outcome.correct, .wrong(revealsAnswer: true), .wrong(revealsAnswer: false)] {
            let at = FeedbackChoreography.beats(for: outcome).map(\.at)
            #expect(at == at.sorted())
            #expect(FeedbackChoreography.beats(for: outcome).last?.beat == .settled)
            #expect(at.last! >= FeedbackChoreography.shakeDuration)
        }
    }

    @Test("Outcome follows the verdict; partial counts as wrong")
    func outcome() {
        #expect(FeedbackChoreography.Outcome(verdict: .correct, revealed: true) == .correct)
        #expect(FeedbackChoreography.Outcome(verdict: .incorrect, revealed: true) == .wrong(revealsAnswer: true))
        #expect(FeedbackChoreography.Outcome(verdict: .partial, revealed: false) == .wrong(revealsAnswer: false))
    }

    @Test("Applying the beats builds up to fully shown")
    func applyBeats() {
        var r = FeedbackReveal()
        r.apply(.result)
        #expect(r == FeedbackReveal(result: true, panel: false, answer: false))
        r.apply(.panel)
        r.apply(.revealAnswer)
        #expect(r == FeedbackReveal(result: true, panel: true, answer: true))
        var s = FeedbackReveal()
        s.apply(.settled)
        #expect(s == .settled)
    }

    // MARK: What a step shows

    private func record(phase: StepPhase, lastIndex: Int?) -> StepRecord {
        var r = StepRecord()
        r.phase = phase
        if let lastIndex {
            r.submissions = [Submission(index: lastIndex, response: .options(["a"]), status: .graded(.incorrect),
                                        feedback: "No.", hint: nil, flags: [], submittedAt: Date(timeIntervalSince1970: 0),
                                        hintsSeen: 0, evaluationToken: 0)]
        }
        return r
    }

    @Test("A new result shows nothing of itself until its sequence starts (no one-frame flash)")
    func newResultMasked() {
        let r = record(phase: .feedback, lastIndex: 1)
        #expect(FeedbackReveal.display(record: r, settledIndex: 0, playing: nil) == FeedbackReveal())
    }

    @Test("A playing result shows its beats so far")
    func playingShowsBeats() {
        let r = record(phase: .feedback, lastIndex: 1)
        let partway = FeedbackReveal(result: true, panel: false, answer: false)
        #expect(FeedbackReveal.display(record: r, settledIndex: 0, playing: (1, partway)) == partway)
        // A stale playback (an older submission) doesn't apply.
        #expect(FeedbackReveal.display(record: r, settledIndex: 0, playing: (0, .settled)) == FeedbackReveal())
    }

    @Test("A settled result, a resumed one, and a step being answered show as the record says")
    func settledShowsAll() {
        #expect(FeedbackReveal.display(record: record(phase: .feedback, lastIndex: 1), settledIndex: 1, playing: nil) == .settled)
        #expect(FeedbackReveal.display(record: record(phase: .viewing, lastIndex: 1), settledIndex: 0, playing: nil) == .settled)
        #expect(FeedbackReveal.display(record: record(phase: .viewing, lastIndex: nil), settledIndex: nil, playing: nil) == .settled)
    }

    @Test("Before the result beat a submitted pick still looks selected, and the revealed answer waits for its beat")
    func rowMasking() {
        let before = OptionMotion(reveal: FeedbackReveal())
        #expect(before.rowState(id: "a", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: true) == .selected)
        #expect(before.rowState(id: "b", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: true) == .idle)

        let result = OptionMotion(reveal: FeedbackReveal(result: true, panel: true, answer: false))
        #expect(result.rowState(id: "a", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: true) == .yourWrongAnswer)
        #expect(result.rowState(id: "b", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: true) == .idle)

        let answered = OptionMotion(reveal: .settled)
        #expect(answered.rowState(id: "b", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: true) == .correctAnswer)
        // Not revealed (a Try again step): the right answer stays unmarked.
        #expect(answered.rowState(id: "b", draft: [], submitted: ["a"], correct: ["b"], phase: .feedback, revealed: false) == .idle)
    }
}
