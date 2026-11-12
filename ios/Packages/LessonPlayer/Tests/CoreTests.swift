import Foundation
import Testing
@testable import LessonPlayer

@Suite("Lesson player: deterministic grading")
struct GraderTests {
    let choice = Activity(prompt: "p", kind: .choice(Fixture.choice))
    let multi = Activity(prompt: "p", kind: .choice(Fixture.multi))
    let claims = Activity(prompt: "p", kind: .claimSelection(Fixture.claims))

    @Test("A right single choice is correct, with the right-answer feedback")
    func singleCorrect() throws {
        let grade = try Grader.grade(choice, response: .options(["b"])).get()
        #expect(grade.verdict == .correct)
        #expect(grade.feedback == Fixture.choice.correctFeedback)
    }

    @Test("A wrong single choice gets that option's misconception feedback")
    func singleWrong() throws {
        let grade = try Grader.grade(choice, response: .options(["c"])).get()
        #expect(grade.verdict == .incorrect)
        #expect(grade.feedback == Fixture.choice.options[2].feedback)
    }

    @Test("Multi-select: all right is correct, some right is partial, any wrong is incorrect")
    func multiSelect() throws {
        #expect(try Grader.grade(multi, response: .options(["x", "y"])).get().verdict == .correct)
        let partial = try Grader.grade(multi, response: .options(["x"])).get()
        #expect(partial.verdict == .partial)
        #expect(partial.feedback == Fixture.multi.partialFeedback)
        let wrong = try Grader.grade(multi, response: .options(["x", "y", "z"])).get()
        #expect(wrong.verdict == .incorrect)
        #expect(wrong.feedback == Fixture.multi.options[2].feedback)
    }

    @Test("Claim selection grades by stable claim id")
    func claimSelection() throws {
        #expect(try Grader.grade(claims, response: .claims(["stat"])).get().verdict == .correct)
        let wrong = try Grader.grade(claims, response: .claims(["schools"])).get()
        #expect(wrong.verdict == .incorrect)
        #expect(wrong.feedback == Fixture.claims.claimFeedback["schools"])
    }

    @Test("Bad responses are errors, never a grade")
    func errors() {
        #expect(Grader.grade(choice, response: .options([])) == .failure(.empty))
        #expect(Grader.grade(choice, response: .options(["nope"])) == .failure(.unknownId("nope")))
        #expect(Grader.grade(choice, response: .options(["a", "b"])) == .failure(.tooManySelected))
        #expect(Grader.grade(choice, response: .claims(["stat"])) == .failure(.responseMismatch))
        let short = Activity(prompt: "p", kind: .shortResponse(Fixture.short))
        #expect(Grader.grade(short, response: .text("anything")) == .failure(.notDeterministic))
    }
}

@Suite("Lesson player: step state machine")
struct MachineTests {
    @Test("Choose, submit, see feedback, continue")
    func happyStep() {
        var m = Fixture.machine()
        #expect(!m.canSubmit)
        let r1 = m.send(.choose("b"))
        #expect(r1.wasApplied)
        #expect(m.canSubmit)
        let submit = m.send(.submit)
        #expect(submit.effects.contains(.feedbackShown(stepId: "s1", status: .graded(.correct))))
        #expect(m.currentRecord.phase == .feedback)
        let next = m.send(.advance(from: m.attempt.currentStepId))
        #expect(next.effects.contains(.stepViewed(stepId: "s2")))
        #expect(m.attempt.currentStepId == "s2")
    }

    @Test("A double submit or a double advance changes nothing the second time")
    func doubleTaps() {
        var m = Fixture.machine()
        _ = m.send(.choose("b"))
        let r2 = m.send(.submit)
        #expect(r2.wasApplied)
        let r3 = m.send(.submit)
        #expect(!r3.wasApplied)
        #expect(m.currentRecord.submissions.count == 1)
        let r4 = m.send(.advance(from: "s1"))
        #expect(r4.wasApplied)
        #expect(m.attempt.currentStepId == "s2")
        // The second Continue tap was made on s1: it must not skip s2.
        let r5 = m.send(.advance(from: "s1"))
        #expect(!r5.wasApplied)
        #expect(m.attempt.currentStepId == "s2")
        let r6 = m.send(.advance(from: "s2"))
        #expect(r6.wasApplied)
        let r7 = m.send(.advance(from: "s2"))
        #expect(!r7.wasApplied)
        #expect(m.attempt.currentStepId == "s3")
    }

    @Test("Continue is ignored until the activity is resolved")
    func noAdvanceBeforeResolved() {
        var m = Fixture.machine()
        let r8 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r8.wasApplied)
        _ = m.send(.choose("c"))
        _ = m.send(.submit)
        #expect(m.currentRecord.lastSubmission?.status == .graded(.incorrect))
        let r9 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r9.wasApplied)
        #expect(m.attempt.currentStepId == "s1")
    }

    @Test("A miss shows a hint on retry; two misses show the answer and allow continuing")
    func missesThenReveal() {
        var m = Fixture.machine()
        _ = m.send(.choose("a")); _ = m.send(.submit)
        let r10 = m.send(.tryAgain)
        #expect(r10.wasApplied)
        #expect(m.currentRecord.hintsShown == 1)
        #expect(m.currentRecord.draft == nil)
        _ = m.send(.choose("c")); _ = m.send(.submit)
        #expect(m.currentRecord.revealed)
        let r11 = m.send(.tryAgain)
        #expect(!r11.wasApplied, "the answer is shown; no more guessing")
        let r12 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(r12.wasApplied)
    }

    @Test("Selection is ignored after submitting, and unknown ids are ignored")
    func selectionGuards() {
        var m = Fixture.machine()
        let r13 = m.send(.choose("nope"))
        #expect(!r13.wasApplied)
        let r14 = m.send(.toggleClaim("stat"))
        #expect(!r14.wasApplied, "wrong activity kind")
        _ = m.send(.choose("b")); _ = m.send(.submit)
        let r15 = m.send(.choose("a"))
        #expect(!r15.wasApplied)
        #expect(m.currentRecord.lastSubmission?.response == .options(["b"]))
    }

    @Test("Opening optional depth is recorded once and never blocks")
    func depth() {
        var m = Fixture.machine()
        m.passCurrent()
        let r16 = m.send(.openDepth("why"))
        #expect(r16.effects == [.depthOpened(stepId: "s2", depthId: "why")])
        let r17 = m.send(.openDepth("why"))
        #expect(r17.effects.isEmpty)
        let r18 = m.send(.openDepth("missing"))
        #expect(!r18.wasApplied)
        let r19 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(r19.wasApplied)
    }

    @Test("Completion fires once, when the rule is met, and the finish step fires finished")
    func completionOnce() {
        var m = Fixture.machine()
        var completions = 0
        for _ in 0..<6 {
            let before = m.attempt.completion
            m.passCurrent()
            if before == nil, m.attempt.completion != nil { completions += 1 }
        }
        #expect(completions == 1)
        #expect(m.attempt.currentStepId == "s7")
        #expect(m.attempt.completion?.success == .independent)
        let r20 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(r20.effects == [.finished])
        let r21 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r21.wasApplied)
    }

    @Test("Hints, retries or a reveal make success assisted, not independent")
    func assisted() {
        var m = Fixture.machine()
        _ = m.send(.choose("a")); _ = m.send(.submit); _ = m.send(.tryAgain)
        _ = m.send(.choose("b")); _ = m.send(.submit); _ = m.send(.advance(from: m.attempt.currentStepId))
        for _ in 0..<5 { m.passCurrent() }
        #expect(m.attempt.completion?.success == .assisted)
    }

    @Test("An answer-only step completes on a wrong pick, but success is not demonstrated")
    func answerOnly() {
        var m = Fixture.machine(Fixture.lesson(mustBeAnswered: ["s1"]))
        _ = m.send(.choose("a")); _ = m.send(.submit)
        let r22 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(r22.wasApplied)
        for _ in 0..<5 { m.passCurrent() }
        #expect(m.attempt.completion?.success == .notDemonstrated)
    }
}

@Suite("Lesson player: short response evaluation states")
struct ShortResponseTests {
    /// A machine sitting on the short-response step.
    func atShort() -> LessonMachine {
        var m = Fixture.machine()
        for _ in 0..<5 { m.passCurrent() }
        return m
    }

    func token(_ r: ActionResult) -> Int? {
        r.effects.compactMap { if case .requestEvaluation(_, let t, _) = $0 { return t }; return nil }.first
    }

    @Test("Submitting asks the server, keeps the text, and is pending until a result")
    func pending() {
        var m = atShort()
        #expect(m.attempt.currentStepId == "s6")
        _ = m.send(.editText("I'd look for the study first."))
        let t = token(m.send(.submit))
        #expect(t != nil)
        #expect(m.currentRecord.phase == .awaitingGrade)
        #expect(m.currentRecord.lastSubmission?.status == .pending)
        let r23 = m.send(.submit)
        #expect(!r23.wasApplied)
        let r24 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r24.wasApplied)
        let r25 = m.send(.editText("changed"))
        #expect(!r25.wasApplied)
    }

    @Test("A result for an old request is ignored; the current one applies")
    func staleResult() {
        var m = atShort()
        _ = m.send(.editText("Look for the study."))
        let first = token(m.send(.submit))!
        _ = m.send(.evaluationFailed(token: first, .timeout))
        let second = token(m.send(.retryEvaluation))!
        #expect(second != first)
        let late = m.send(.evaluationArrived(token: first, ResponseEvaluation(status: .meets, feedback: "late")))
        #expect(!late.wasApplied)
        #expect(m.currentRecord.lastSubmission?.status == .pending)
        let r26 = m.send(.evaluationArrived(token: second, ResponseEvaluation(status: .meets, feedback: "ok")))
        #expect(r26.wasApplied)
        #expect(m.currentRecord.lastSubmission?.status == .graded(.correct))
        let r27 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(r27.wasApplied)
    }

    @Test("Ungraded or cancelled is never correct and never lets the lesson complete")
    func ungradedBlocks() {
        var m = atShort()
        _ = m.send(.editText("Look for the study."))
        let t = token(m.send(.submit))!
        _ = m.send(.evaluationFailed(token: t, .offline))
        #expect(m.currentRecord.lastSubmission?.status == .ungraded(.offline))
        let r28 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r28.wasApplied)
        #expect(m.attempt.completion == nil)
        // A result after the failure is late: ignored.
        let r29 = m.send(.evaluationArrived(token: t, ResponseEvaluation(status: .meets, feedback: "x")))
        #expect(!r29.wasApplied)
        // Cancel while pending, too.
        let t2 = token(m.send(.retryEvaluation))!
        let r30 = m.send(.cancelEvaluation)
        #expect(r30.wasApplied)
        #expect(m.currentRecord.lastSubmission?.status == .ungraded(.interrupted))
        let r31 = m.send(.evaluationArrived(token: t2, ResponseEvaluation(status: .meets, feedback: "x")))
        #expect(!r31.wasApplied)
        #expect(m.attempt.completion == nil)
    }

    @Test("Not yet: revise and resubmit; the exemplar shows after two, and only meets resolves")
    func notYet() {
        var m = atShort()
        _ = m.send(.editText("It's fake."))
        let t1 = token(m.send(.submit))!
        _ = m.send(.evaluationArrived(token: t1, ResponseEvaluation(status: .notYet, feedback: "f", hint: "h", flags: ["missing_citation_proves_false", "made_up_flag"])))
        #expect(m.currentRecord.lastSubmission?.flags == ["missing_citation_proves_false"], "unknown flags dropped")
        let r32 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r32.wasApplied)
        let r33 = m.send(.tryAgain)
        #expect(r33.wasApplied)
        #expect(m.currentRecord.draft == .text("It's fake."), "the text is kept to revise")
        let t2 = token(m.send(.submit))!
        _ = m.send(.evaluationArrived(token: t2, ResponseEvaluation(status: .notYet, feedback: "f")))
        #expect(m.currentRecord.revealed)
        let r34 = m.send(.advance(from: m.attempt.currentStepId))
        #expect(!r34.wasApplied, "the exemplar doesn't resolve a short response")
        _ = m.send(.tryAgain)
        _ = m.send(.editText("I'd hold off and find the study."))
        let t3 = token(m.send(.submit))!
        _ = m.send(.evaluationArrived(token: t3, ResponseEvaluation(status: .meets, feedback: "yes")))
        let done = m.send(.advance(from: m.attempt.currentStepId))
        #expect(done.effects.contains { if case .lessonCompleted(let c) = $0 { return c.success == .assisted }; return false })
    }

    @Test("Text longer than the limit is cut to the limit")
    func maxLength() {
        var m = atShort()
        _ = m.send(.editText(String(repeating: "a", count: 500)))
        #expect(m.currentRecord.draft == .text(String(repeating: "a", count: 200)))
    }
}

@Suite("Lesson player: attempt records")
struct AttemptTests {
    @Test("An attempt round-trips through its codec unchanged")
    func roundTrip() throws {
        var m = Fixture.machine()
        _ = m.send(.choose("a"), now: Fixture.t0); _ = m.send(.submit, now: Fixture.t0)
        m.recordActive(seconds: 12)
        let data = try LessonAttemptCodec.encode(m.attempt)
        #expect(LessonAttemptCodec.decode(data) == m.attempt)
    }

    @Test("A record from a newer app version is not read (and so never overwritten with a guess)")
    func newerRecord() throws {
        var attempt = Fixture.machine().attempt
        attempt.recordVersion = LessonAttempt.currentRecordVersion + 1
        #expect(LessonAttemptCodec.decode(try LessonAttemptCodec.encode(attempt)) == nil)
        #expect(LessonAttemptCodec.decode(Data("not json".utf8)) == nil)
    }

    @Test("After a relaunch, a response that was being graded is ungraded (interrupted), its text kept")
    func relaunch() {
        var m = Fixture.machine()
        for _ in 0..<5 { m.passCurrent() }
        _ = m.send(.editText("Find the study."))
        _ = m.send(.submit)
        let restored = LessonAttemptCodec.normalizedAfterRelaunch(m.attempt)
        let record = restored.record("s6")
        #expect(record.phase == .feedback)
        #expect(record.lastSubmission?.status == .ungraded(.interrupted))
        #expect(record.lastSubmission?.response == .text("Find the study."))
        var resumed = LessonMachine(content: Fixture.lesson(), attempt: restored)!
        let r35 = resumed.send(.retryEvaluation)
        #expect(r35.wasApplied)
    }

    @Test("An attempt only runs on the content version it started on")
    func versionPinning() {
        let attempt = Fixture.machine().attempt
        #expect(LessonMachine(content: Fixture.lesson(version: 2), attempt: attempt) == nil)
        #expect(LessonMachine(content: Fixture.lesson(version: 1), attempt: attempt) != nil)
    }

    @Test("Active time is capped per tick")
    func activeTime() {
        var m = Fixture.machine()
        m.recordActive(seconds: 5)
        m.recordActive(seconds: 3600)
        m.recordActive(seconds: -4)
        #expect(m.attempt.activeSeconds == 65)
    }
}

@Suite("Lesson player: experience assignment and rewards")
struct ExperienceTests {
    let library = LessonLibrary([Fixture.lesson(version: 1), Fixture.lesson(version: 2)])

    func inputs(flag: Bool, attempt: LessonAttempt? = nil, legacy: Bool = false, completed: Bool = false) -> ExperienceInputs {
        ExperienceInputs(playerEnabled: flag, playerAttempt: attempt, hasLegacyConversation: legacy, lessonCompleted: completed)
    }

    @Test("Flag off: legacy, as today")
    func flagOff() {
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: false), library: library) == .legacy)
    }

    @Test("Flag on: a new attempt starts on the newest version")
    func flagOn() {
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true), library: library) == .startPlayer(contentVersion: 2))
        #expect(ExperienceResolver.decide(lessonId: "u1_l1", inputs: inputs(flag: true), library: library) == .legacy, "no player content")
    }

    @Test("An unfinished attempt resumes on its own version, even after the flag goes off")
    func pinned() {
        let v1 = Fixture.machine(Fixture.lesson(version: 1)).attempt
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: false, attempt: v1), library: library) == .resumePlayer(v1))
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true, attempt: v1), library: library) == .resumePlayer(v1))
    }

    @Test("A legacy thread keeps the lesson legacy, even with the flag on")
    func legacyStays() {
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true, legacy: true), library: library) == .legacy)
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true, legacy: true, completed: true), library: library) == .legacy)
    }

    @Test("A finished player attempt replays as a new attempt; a dropped version doesn't resume")
    func replayAndDroppedVersion() {
        var done = Fixture.machine()
        for _ in 0..<6 { done.passCurrent() }
        #expect(done.attempt.isComplete)
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true, attempt: done.attempt, completed: true), library: library) == .startPlayer(contentVersion: 2))
        let only2 = LessonLibrary([Fixture.lesson(version: 2)])
        let v1 = Fixture.machine(Fixture.lesson(version: 1)).attempt
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: false, attempt: v1), library: only2) == .legacy)
    }

    @Test("Invalid content never runs")
    func invalidContent() {
        let broken = LessonContent(lessonId: "u9_l9", contentVersion: 3, title: "", objective: "", prerequisites: [], steps: [], completion: CompletionRule(mustBeCorrect: []))
        let lib = LessonLibrary([broken])
        #expect(ExperienceResolver.decide(lessonId: "u9_l9", inputs: inputs(flag: true), library: lib) == .legacy)
    }

    @Test("A one-time reward is granted once, however often the lesson is replayed")
    func rewards() throws {
        var ledger = RewardLedger()
        let key = RewardLedger.completionKey(lessonId: "u9_l9")
        let r36 = ledger.grant(key)
        #expect(r36)
        let r37 = ledger.grant(key)
        #expect(!r37)
        let restored = try JSONDecoder().decode(RewardLedger.self, from: JSONEncoder().encode(ledger))
        var again = restored
        let r38 = again.grant(key)
        #expect(!r38)
    }
}

@Suite("Lesson player: lesson data validation")
struct ValidatorTests {
    func errors(_ lesson: LessonContent) -> [String] {
        LessonValidator.validate(lesson).filter { $0.severity == .error }.map(\.message)
    }

    @Test("The fixture lesson has no errors")
    func fixtureValid() {
        #expect(errors(Fixture.lesson()).isEmpty)
    }

    @Test("Broken lessons are caught")
    func broken() {
        let base = Fixture.lesson()
        var steps = base.steps
        steps[2] = LessonStep(id: "s1", kind: steps[2].kind)          // duplicate id
        let dup = LessonContent(lessonId: "u9_l9", contentVersion: 1, title: "t", objective: "o", prerequisites: [], steps: steps, completion: base.completion)
        #expect(errors(dup).contains("duplicate step id"))

        let badKey = LessonContent(lessonId: "u9_l9", contentVersion: 1, title: "t", objective: "o", prerequisites: [],
            steps: [LessonStep(id: "q", kind: .activity(Activity(prompt: "Pick", kind: .choice(ChoiceActivity(
                options: [ChoiceOption(id: "a", text: "A"), ChoiceOption(id: "b", text: "B", feedback: "no")],
                correct: ["zz"], correctFeedback: "yes"))))), base.steps.last!],
            completion: CompletionRule(mustBeCorrect: ["q"]))
        #expect(errors(badKey).contains("answer key names a missing option"))

        let notInRule = LessonContent(lessonId: "u9_l9", contentVersion: 1, title: "t", objective: "o", prerequisites: [],
            steps: base.steps, completion: CompletionRule(mustBeCorrect: ["s1"]))
        #expect(errors(notInRule).contains("a required activity must be in the completion rule"))

        let shortAnswerOnly = Fixture.lesson(mustBeAnswered: ["s6"])
        #expect(errors(shortAnswerOnly).contains("a short response must be graded, not just answered"))

        let badId = LessonContent(lessonId: "lesson-3", contentVersion: 0, title: "t", objective: "o", prerequisites: [], steps: base.steps, completion: base.completion)
        #expect(errors(badId).count >= 2)
    }

    @Test("Editorial targets are warnings, not errors")
    func warnings() {
        let issues = LessonValidator.validate(Fixture.lesson())
        #expect(issues.allSatisfy { $0.severity == .warning })
    }
}

@Suite("Lesson player: evaluation result validation")
struct EvaluationParserTests {
    let flags: Set<String> = ["missing_citation_proves_false"]

    @Test("A valid result parses; unknown flags are dropped")
    func valid() {
        let json = #"{"status":"not_yet","feedback":"Close: say where you'd look.","hint":"Name a place to check.","flags":["missing_citation_proves_false","x"]}"#
        let e = EvaluationParser.parse(Data(json.utf8), allowedFlags: flags)
        #expect(e == ResponseEvaluation(status: .notYet, feedback: "Close: say where you'd look.", hint: "Name a place to check.", flags: ["missing_citation_proves_false"]))
    }

    @Test("Invalid results are rejected, not repaired")
    func invalid() {
        let bad = [
            #"{"status":"correct","feedback":"x"}"#,
            #"{"status":"meets","feedback":""}"#,
            #"{"status":"meets"}"#,
            #"{"status":"meets","feedback":"<b>Great</b>"}"#,
            #"{"status":"meets","feedback":"ok","hint":"<script>x</script>"}"#,
            #"not json"#,
            "{\"status\":\"meets\",\"feedback\":\"\(String(repeating: "a", count: 401))\"}",
        ]
        for json in bad {
            #expect(EvaluationParser.parse(Data(json.utf8), allowedFlags: flags) == nil, "\(json.prefix(40))")
        }
    }
}
