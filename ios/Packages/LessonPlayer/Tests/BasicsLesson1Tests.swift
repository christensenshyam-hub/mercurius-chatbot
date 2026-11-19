import Foundation
import Testing
@testable import LessonPlayer

/// Basics 1.1, "What is an AI chatbot?" (draft copy): its objective is a real
/// first message, and a wrong pick still completes (Basics' rule).
@Suite("Basics Lesson 1: content and play")
struct BasicsLesson1Tests {
    let lesson = LessonCatalog.b1_l1_v1

    @Test("No validation errors or warnings")
    func valid() {
        let issues = LessonValidator.validate(lesson)
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test("It is the first Basics lesson, with no prerequisites, and a decision first")
    func identity() {
        #expect(lesson.lessonId == "b1_l1")
        #expect(lesson.prerequisites.isEmpty)
        #expect(lesson.steps.first?.activity != nil)
        #expect(lesson.steps.count == 7)
    }

    @Test("No statistics or percentages (the Basics guide's rule)")
    func noStatistics() {
        let all = lesson.steps.flatMap { step -> [String] in
            switch step.kind {
            case .teach(let t): return [t.body, t.keyIdea ?? ""]
            case .finish(let f): return [f.practiced, f.next]
            case .activity(let a): return [a.prompt]
            }
        }
        for line in all { #expect(!line.contains("%"), "\(line)") }
    }

    func machine() -> LessonMachine {
        LessonMachine(content: lesson, attempt: LessonAttempt(lesson: lesson, now: Fixture.t0))!
    }

    func token(_ r: ActionResult) -> Int? {
        r.effects.compactMap { if case .requestPractice(_, let t, _) = $0 { return t }; return nil }.first
    }

    @Test("The practice message goes to the live tutor; only Merc's reply resolves it")
    func practice() {
        var m = machine()
        _ = m.send(.choose("program")); _ = m.send(.submit); _ = m.send(.advance(from: "who-wrote-it"))
        _ = m.send(.advance(from: "what-it-is"))
        #expect(m.attempt.currentStepId == "first-message")
        _ = m.send(.editText("Are you a real person?"))
        let t = token(m.send(.submit))
        #expect(t != nil)
        let early = m.send(.advance(from: "first-message"))
        #expect(!early.wasApplied)
        _ = m.send(.evaluationFailed(token: t!, .offline))
        let offline = m.send(.advance(from: "first-message"))
        #expect(!offline.wasApplied, "an unanswered practice message doesn't count")
        let t2 = m.send(.retryEvaluation).effects.compactMap { e -> Int? in
            if case .requestPractice(_, let t, _) = e { return t }; return nil
        }.first!
        _ = m.send(.practiceReplied(token: t2, reply: "No, I’m Merc, an AI. A computer program writes my answers."))
        #expect(m.currentRecord.lastSubmission?.status == .notGraded)
        #expect(m.currentRecord.lastSubmission?.status.verdict == nil, "not graded, never correct")
        let tryAgain = m.send(.tryAgain)
        #expect(!tryAgain.wasApplied)
        let next = m.send(.advance(from: "first-message"))
        #expect(next.wasApplied)
    }

    @Test("A wrong pick on the check shows the answer kindly and still completes, as not demonstrated")
    func wrongPickCompletes() {
        var m = machine()
        _ = m.send(.choose("person")); _ = m.send(.submit)
        #expect(m.currentRecord.revealed, "the right answer is shown straight away")
        _ = m.send(.advance(from: "who-wrote-it"))
        _ = m.send(.advance(from: "what-it-is"))
        _ = m.send(.editText("Hi"))
        let t = token(m.send(.submit))!
        _ = m.send(.practiceReplied(token: t, reply: "Hello! I’m Merc, an AI."))
        _ = m.send(.advance(from: "first-message"))
        _ = m.send(.advance(from: "how-it-writes"))
        _ = m.send(.choose("soup")); _ = m.send(.submit); _ = m.send(.advance(from: "postcard"))
        _ = m.send(.choose("library")); _ = m.send(.submit)
        let done = m.send(.advance(from: "check"))
        let completion = done.effects.compactMap { e -> CompletionRecord? in
            if case .lessonCompleted(let c) = e { return c }; return nil
        }.first
        #expect(completion?.success == .notDemonstrated)
    }

    @Test("All right first time: independent (the practice message doesn't count either way)")
    func allRight() {
        var m = machine()
        _ = m.send(.choose("program")); _ = m.send(.submit); _ = m.send(.advance(from: "who-wrote-it"))
        _ = m.send(.advance(from: "what-it-is"))
        _ = m.send(.editText("Are you a real person?"))
        let t = token(m.send(.submit))!
        _ = m.send(.practiceReplied(token: t, reply: "No. I’m Merc, an AI."))
        _ = m.send(.advance(from: "first-message"))
        _ = m.send(.advance(from: "how-it-writes"))
        _ = m.send(.choose("soup")); _ = m.send(.submit); _ = m.send(.advance(from: "postcard"))
        _ = m.send(.choose("program")); _ = m.send(.submit)
        _ = m.send(.advance(from: "check"))
        #expect(m.attempt.completion?.success == .independent)
    }

    @Test("A practice step can't be in the must-be-correct rule")
    func practiceNeverGraded() {
        let bad = LessonContent(lessonId: "b1_l1", contentVersion: 9, title: lesson.title, objective: lesson.objective,
                                prerequisites: [], steps: lesson.steps,
                                completion: CompletionRule(mustBeCorrect: ["first-message"],
                                                           mustBeAnswered: ["who-wrote-it", "postcard", "check"]))
        let errors = LessonValidator.validate(bad).filter { $0.severity == .error }.map(\.message)
        #expect(errors.contains("a practice message isn't graded, so it can only be answered"))
    }
}
