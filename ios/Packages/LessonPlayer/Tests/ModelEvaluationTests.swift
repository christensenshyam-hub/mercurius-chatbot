import Foundation
import Testing
@testable import LessonPlayer

/// The player model's short-response path against a controllable host: every
/// failure is an honest "not graded yet" with the answer kept, a result is
/// validated before it's shown, and nothing completes on an ungraded answer.
@Suite("Lesson player: evaluation failures through the model")
@MainActor
struct ModelEvaluationTests {
    final class Recorder {
        var saved: [LessonAttempt] = []
        var completions: [CompletionRecord] = []
        var events: [String] = []
        var requests: [EvaluationRequest] = []
    }

    /// A model on Lesson 3's transfer step, answering with `outcome` after
    /// `delay`.
    func model(_ outcome: EvaluationOutcome, delay: Duration = .zero, timeout: Duration = .seconds(5))
        -> (LessonPlayerModel, Recorder) {
        let rec = Recorder()
        var machine = LessonMachine(content: LessonCatalog.u1_l3_v1,
                                    attempt: LessonAttempt(lesson: LessonCatalog.u1_l3_v1, now: Fixture.t0))!
        for _ in 0..<5 { machine.passCurrent() }
        let host = LessonPlayerHost(
            saveAttempt: { rec.saved.append($0) },
            evaluate: { request in
                await MainActor.run { rec.requests.append(request) }
                if delay > .zero { try? await Task.sleep(for: delay) }
                return outcome
            },
            lessonCompleted: { _, c in rec.completions.append(c) },
            exit: { _ in },
            record: { rec.events.append($0.name + ($0.fields["error"].map { ":" + $0 } ?? "")) }
        )
        return (LessonPlayerModel(machine: machine, host: host, resumed: false, evaluationTimeout: timeout), rec)
    }

    func submit(_ m: LessonPlayerModel, _ text: String = "I'd hold off and look for the study.") {
        m.send(.editText(text))
        m.send(.submit)
    }

    func settle(_ m: LessonPlayerModel) async {
        _ = await waitUntil { m.record.phase != .awaitingGrade }
    }

    @Test("Meets: graded correct, the lesson completes once, and the request carried ids and text only")
    func meets() async {
        let (m, rec) = model(.evaluated(ResponseEvaluation(status: .meets, feedback: "That’s the move.")))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .graded(.correct))
        m.send(.advance(from: "transfer"))
        #expect(rec.completions.count == 1)
        #expect(rec.requests.first == EvaluationRequest(lessonId: "u1_l3", contentVersion: 1, stepId: "transfer",
                                                      rubricId: "u1_l3.transfer.v1", text: "I'd hold off and look for the study."))
    }

    @Test("Invalid output (markup in feedback) is not shown as a grade")
    func invalidOutput() async {
        let (m, rec) = model(.evaluated(ResponseEvaluation(status: .meets, feedback: "<b>Great</b>")))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .ungraded(.invalidResult))
        #expect(m.record.lastSubmission?.response == .text("I'd hold off and look for the study."))
        #expect(rec.completions.isEmpty)
        #expect(rec.events.contains("lesson_error:invalidResult"))
    }

    @Test("A flag the rubric doesn't have is dropped before it's shown")
    func unknownFlag() async {
        let (m, _) = model(.evaluated(ResponseEvaluation(status: .notYet, feedback: "Close.", hint: "Where would you look?",
                                                         flags: ["missing_citation_proves_false", "injected"])))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.flags == ["missing_citation_proves_false"])
    }

    @Test("A slow evaluation times out: ungraded (timeout), and Retry is offered")
    func timeout() async {
        let (m, rec) = model(.evaluated(ResponseEvaluation(status: .meets, feedback: "late")),
                             delay: .seconds(3), timeout: .milliseconds(100))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .ungraded(.timeout))
        #expect(ActionPlan(machine: m.machine).primary.action == .retry)
        #expect(rec.completions.isEmpty)
        #expect(rec.events.contains("lesson_error:timeout"))
    }

    @Test("Offline: ungraded, and the answer is still saved to disk")
    func offline() async {
        let (m, rec) = model(.failed(.offline))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .ungraded(.offline))
        #expect(rec.saved.last?.record("transfer").lastSubmission?.response == .text("I'd hold off and look for the study."))
    }

    @Test("Leaving while it's checking cancels; a result that arrives afterwards is ignored")
    func leaveWhileChecking() async {
        let (m, rec) = model(.evaluated(ResponseEvaluation(status: .meets, feedback: "late")), delay: .milliseconds(300))
        submit(m)
        #expect(m.record.phase == .awaitingGrade)
        m.leave()
        #expect(m.record.lastSubmission?.status == .ungraded(.interrupted))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(m.record.lastSubmission?.status == .ungraded(.interrupted))
        #expect(rec.completions.isEmpty)
    }

    @Test("A crisis reply shows support and is never graded")
    func crisis() async {
        let (m, rec) = model(.failed(.support))
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .ungraded(.support))
        #expect(m.showsCrisisSupport)
        #expect(rec.completions.isEmpty)
        #expect(!rec.events.contains { $0.hasPrefix("lesson_error") })
    }

    @Test("Retry after a failure can succeed, and only then does the lesson complete")
    func retryThenMeets() async {
        var calls = 0
        let rec = Recorder()
        var machine = LessonMachine(content: LessonCatalog.u1_l3_v1,
                                    attempt: LessonAttempt(lesson: LessonCatalog.u1_l3_v1, now: Fixture.t0))!
        for _ in 0..<5 { machine.passCurrent() }
        let host = LessonPlayerHost(
            saveAttempt: { _ in },
            evaluate: { _ in
                let n = await MainActor.run { calls += 1; return calls }
                return n == 1 ? .failed(.unavailable) : .evaluated(ResponseEvaluation(status: .meets, feedback: "Yes."))
            },
            lessonCompleted: { _, c in rec.completions.append(c) },
            exit: { _ in }
        )
        let m = LessonPlayerModel(machine: machine, host: host, resumed: false)
        submit(m)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .ungraded(.unavailable))
        m.send(.retryEvaluation)
        await settle(m)
        #expect(m.record.lastSubmission?.status == .graded(.correct))
        #expect(m.record.submissions.count == 1, "a retry re-checks the same answer")
        m.send(.advance(from: "transfer"))
        #expect(rec.completions.count == 1)
    }
}

/// Polls until `condition` holds or about 3 s pass.
@MainActor
func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite("Lesson player: active time")
@MainActor
struct ActiveTimeTests {
    final class Clock { var now = Fixture.t0 }

    @Test("A lesson done in one sitting carries real active time on every event")
    func oneSitting() {
        let clock = Clock()
        var events: [LessonPlayerEvent] = []
        let lesson = LessonCatalog.u1_l3_v1
        let host = LessonPlayerHost(saveAttempt: { _ in }, evaluate: { _ in .failed(.offline) },
                                    lessonCompleted: { _, _ in }, exit: { _ in }, record: { events.append($0) })
        let m = LessonPlayerModel(machine: LessonMachine(content: lesson, attempt: LessonAttempt(lesson: lesson, now: clock.now))!,
                                  host: host, resumed: false, clock: { clock.now })
        m.sceneBecameActive()
        clock.now += 40
        m.send(.choose("unverified"))
        clock.now += 50
        m.send(.submit)
        let submitted = events.first { $0.name == "answer_submitted" }
        #expect(submitted?.context.activeSeconds == 90)
        // A long idle gap counts for at most the cap.
        clock.now += 3600
        m.send(.advance(from: "claim-state"))
        #expect(m.machine.attempt.activeSeconds == 90 + LessonMachine.maxActiveGap)
    }
}
