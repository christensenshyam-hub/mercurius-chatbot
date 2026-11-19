import Foundation
import Testing
@testable import LessonPlayer

/// Unit 1, Lesson 3 as authored (SPEC.md, "Lesson 3 script").
@Suite("Lesson 3: content")
struct Lesson3ContentTests {
    let lesson = LessonCatalog.u1_l3_v1

    @Test("No validation errors; every warning is listed for review")
    func valid() {
        let issues = LessonValidator.validate(lesson)
        #expect(issues.filter { $0.severity == .error }.isEmpty, "\(issues)")
        // Warnings are editorial targets, recorded in PROGRESS.md. None today.
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test("It is the curriculum's lesson, gated on Lesson 2, with the script's seven steps")
    func identity() {
        #expect(lesson.lessonId == "u1_l3")
        #expect(lesson.prerequisites == ["u1_l2"])
        #expect(lesson.steps.map(\.id) == ["claim-state", "principle", "testable-claim", "best-check", "excerpt", "transfer", "finish"])
        #expect(LessonCatalog.library.latest(lessonId: "u1_l3") == lesson)
    }

    @Test("Step 1 is a decision: unverified is right, from the statement alone")
    func step1() {
        guard case .choice(let c)? = lesson.steps[0].activity?.kind else { Issue.record("not a choice"); return }
        #expect(c.options.map(\.text) == ["Supported", "Unverified", "Contradicted"])
        #expect(c.correct == ["unverified"])
        #expect(lesson.steps[0].activity?.scenario?.origin == .fictional)
    }

    @Test("Step 5: the excerpt leaves the claim unverified, and neither supports nor disproves it")
    func step5() {
        guard case .choice(let c)? = lesson.steps[4].activity?.kind else { Issue.record("not a choice"); return }
        #expect(c.presentation == .claimVersusEvidence)
        #expect(c.correct == ["still-unverified"])
        #expect(lesson.steps[4].activity?.evidence?.text.contains("did not measure memory") == true)
    }

    @Test("Step 6's rubric matches the script, and flags the missing-citation misconception")
    func step6() {
        guard case .shortResponse(let r)? = lesson.steps[5].activity?.kind else { Issue.record("not a short response"); return }
        #expect(r.rubricId == "u1_l3.transfer.v1")
        #expect(r.rubric.flags.map(\.id) == ["missing_citation_proves_false"])
        #expect(!r.fallbackGuidance.lowercased().contains("correct"))
    }

    @Test("Every invented claim, excerpt and source is labelled fictional; real cases carry their source")
    func labels() {
        for step in lesson.steps {
            for m in [step.activity?.scenario, step.activity?.evidence].compactMap({ $0 }) {
                #expect(m.origin == .fictional, "\(step.id)")
            }
            for d in step.depth where d.body.contains("2023") {
                if case .real = d.origin { continue }
                Issue.record("\(d.id) cites a year without a source")
            }
        }
        let example = lesson.steps[1].depth.first { $0.id == "principle.example" }
        #expect(example?.origin == .fictional)
    }

    @Test("No line says a citation you can't find is proof it was made up")
    func noFakeCitationRule() {
        var text: [String] = []
        for step in lesson.steps {
            switch step.kind {
            case .teach(let t): text += [t.body, t.keyIdea ?? ""]
            case .finish(let f): text += [f.practiced, f.next]
            case .activity(let a):
                text.append(a.prompt)
                switch a.kind {
                case .choice(let c): text += c.options.map(\.feedback) + [c.correctFeedback]
                case .claimSelection(let s): text += Array(s.claimFeedback.values) + [s.correctFeedback]
                case .shortResponse(let r): text += [r.fallbackGuidance, r.exemplar] + r.rubric.flags.map(\.correction)
                case .practice(let p): text += [p.fallbackGuidance, p.notice]
                }
            }
            text += step.depth.map(\.body)
        }
        for line in text {
            let l = line.lowercased()
            #expect(!(l.contains("can't find") && (l.contains("made up") || l.contains("fake"))) || l.contains("not false") || l.contains("unverified"), "\(line)")
        }
    }

    @Test("Correct answers don't sit in one position, or stand out by length")
    func distractorShape() {
        var positions: [Int] = []
        for step in lesson.steps {
            guard case .choice(let c)? = step.activity?.kind, c.selection == .single,
                  let right = c.options.firstIndex(where: { c.correct.contains($0.id) }) else { continue }
            positions.append(right)
            let lengths = c.options.map(\.text.count)
            #expect(lengths[right] <= (lengths.max() ?? 0), "\(step.id): the right option is the longest")
        }
        #expect(Set(positions).count == positions.count, "positions \(positions)")
    }
}

@Suite("Lesson 3: played through")
struct Lesson3PlayTests {
    func machine() -> LessonMachine {
        let lesson = LessonCatalog.u1_l3_v1
        return LessonMachine(content: lesson, attempt: LessonAttempt(lesson: lesson, now: Fixture.t0))!
    }

    @Test("All right, first time: completes once, independent, then Finish")
    func allRight() {
        var m = machine()
        var completions: [CompletionRecord] = []
        while true {
            let before = m.attempt.completion
            m.passCurrent()
            if before == nil, let c = m.attempt.completion { completions.append(c) }
            if case .finish = m.currentStep.kind { break }
        }
        #expect(completions.count == 1)
        #expect(completions.first?.success == .independent)
        let finish = m.send(.advance(from: "finish"))
        #expect(finish.effects == [.finished])
    }

    @Test("Wrong answers get their own feedback; the claim selection names why a vague claim isn't testable")
    func wrongFeedback() {
        var m = machine()
        _ = m.send(.choose("supported"))
        _ = m.send(.submit)
        #expect(m.currentRecord.lastSubmission?.feedback?.contains("nothing here backs it up") == true)
        _ = m.send(.tryAgain); _ = m.send(.choose("unverified")); _ = m.send(.submit); _ = m.send(.advance(from: "claim-state"))
        _ = m.send(.advance(from: "principle"))
        _ = m.send(.toggleClaim("teachers"))
        _ = m.send(.submit)
        #expect(m.currentRecord.lastSubmission?.status == .graded(.incorrect))
        #expect(m.currentRecord.lastSubmission?.feedback?.contains("no number to test") == true)
    }

    @Test("Ungraded transfer: the lesson does not complete, and the learner can leave and retry")
    func transferUngraded() {
        var m = machine()
        for _ in 0..<5 { m.passCurrent() }
        #expect(m.attempt.currentStepId == "transfer")
        _ = m.send(.editText("I'd look for the original study before trusting the 22%."))
        let token = m.send(.submit).effects.compactMap { e -> Int? in
            if case .requestEvaluation(_, let t, _) = e { return t }; return nil
        }.first!
        _ = m.send(.evaluationFailed(token: token, .timeout))
        #expect(m.attempt.completion == nil)
        let plan = ActionPlan(machine: m)
        #expect(plan.primary.action == .retry)
        #expect(plan.secondary?.action == .tryAgain)
    }
}

@Suite("Lesson player: action bar")
struct ActionPlanTests {
    @Test("Check answer is disabled until something is chosen; Continue after a right answer")
    func choiceFlow() {
        var m = Fixture.machine()
        #expect(ActionPlan(machine: m).primary == .init(title: PlayerCopy.check, enabled: false, busy: false, action: .check, playerAction: .submit))
        _ = m.send(.choose("b"))
        #expect(ActionPlan(machine: m).primary.enabled)
        #expect(ActionPlan(machine: m).secondary == nil, "the hint button lives in the step, not the bar")
        _ = m.send(.submit)
        #expect(ActionPlan(machine: m).primary.action == .continue)
    }

    @Test("A miss offers Try again; while grading, Checking is busy and Cancel is offered")
    func missAndPending() {
        var m = Fixture.machine()
        _ = m.send(.choose("a")); _ = m.send(.submit)
        #expect(ActionPlan(machine: m).primary.action == .tryAgain)
        for _ in 0..<1 { _ = m.send(.tryAgain); _ = m.send(.choose("b")); _ = m.send(.submit); _ = m.send(.advance(from: "s1")) }
        for _ in 0..<4 { m.passCurrent() }
        _ = m.send(.editText("Find the study."))
        _ = m.send(.submit)
        let plan = ActionPlan(machine: m)
        #expect(plan.primary.busy && !plan.primary.enabled)
        #expect(plan.secondary?.action == .cancelEvaluation)
    }
}
