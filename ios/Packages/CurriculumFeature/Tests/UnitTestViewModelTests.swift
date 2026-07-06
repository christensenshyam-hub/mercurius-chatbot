import Testing
@testable import CurriculumFeature

// NOTE: deliberately no `import Foundation` — it exports a `Unit` type that
// collides with CurriculumFeature.Unit.

private func makeUnit() -> Unit {
    Unit(id: "unit_x", number: "0X", title: "Test Unit", summary: "s", lessons: [])
}

private func makeTest() -> UnitTest {
    UnitTest(
        unitId: "unit_x",
        questions: [
            UnitTestQuestion(id: "q1", q: "1?", options: ["a", "b", "c", "d"], answer: "A", explanation: "e"),
            UnitTestQuestion(id: "q2", q: "2?", options: ["a", "b", "c", "d"], answer: "B", explanation: "e"),
            UnitTestQuestion(id: "q3", q: "3?", options: ["a", "b", "c", "d"], answer: "C", explanation: "e"),
            UnitTestQuestion(id: "q4", q: "4?", options: ["a", "b", "c", "d"], answer: "D", explanation: "e"),
            UnitTestQuestion(id: "q5", q: "5?", options: ["a", "b", "c", "d"], answer: "A", explanation: "e"),
        ],
        defensePrompt: "Defend your reasoning."
    )
}

private struct StubError: Error {}

@Suite("UnitTestViewModel")
@MainActor
struct UnitTestViewModelTests {

    private func model(
        gradeDefense: @escaping (String) async throws -> UnitTestViewModel.DefenseResult
            = { _ in .init(grade: "A", pass: true, feedback: "ok") }
    ) -> UnitTestViewModel {
        UnitTestViewModel(unit: makeUnit(), test: makeTest(), gradeDefense: gradeDefense)
    }

    /// Answer the first `correct` questions correctly and the rest wrong.
    private func answerAll(_ m: UnitTestViewModel, correct: Int) {
        for (i, q) in m.questions.enumerated() {
            let letter = i < correct ? q.answer : (q.answer == "A" ? "B" : "A")
            m.select(letter, for: q.id)
        }
    }

    @Test("Starts on the quiz phase with nothing answered")
    func initialState() {
        let m = model()
        #expect(m.phase == .quiz)
        #expect(!m.allAnswered)
        #expect(!m.quizSubmitted)
        #expect(m.mcqTotal == 5)
        #expect(m.mcqCorrectNeeded == 4)   // ceil(0.8 * 5)
    }

    @Test("Submitting locks selections and scores correctly")
    func submitScores() {
        let m = model()
        answerAll(m, correct: 5)
        #expect(m.allAnswered)
        m.submitQuiz()
        #expect(m.quizSubmitted)
        #expect(m.mcqScore == 5)
        #expect(m.mcqPassed)
        // Selecting after submit is a no-op (the quiz is locked).
        m.select("B", for: "q1")
        #expect(m.selectedLetter(for: "q1") == "A")
    }

    @Test("4 of 5 passes the MCQ half; 3 of 5 fails")
    func mcqThreshold() {
        let pass = model(); answerAll(pass, correct: 4); pass.submitQuiz()
        #expect(pass.mcqScore == 4)
        #expect(pass.mcqPassed)

        let fail = model(); answerAll(fail, correct: 3); fail.submitQuiz()
        #expect(fail.mcqScore == 3)
        #expect(!fail.mcqPassed)
    }

    @Test("Passing the MCQ routes to the defense; failing skips straight to the result")
    func continueRouting() {
        let pass = model(); answerAll(pass, correct: 5); pass.submitQuiz(); pass.continueAfterQuiz()
        #expect(pass.phase == .defense)

        let fail = model(); answerAll(fail, correct: 2); fail.submitQuiz(); fail.continueAfterQuiz()
        #expect(fail.phase == .result)
        #expect(!fail.overallPassed)
    }

    @Test("A passing defense produces an overall pass")
    func defensePassOverall() async {
        let m = model { _ in .init(grade: "A", pass: true, feedback: "Strong.") }
        answerAll(m, correct: 5); m.submitQuiz(); m.continueAfterQuiz()
        m.defenseAnswer = "My reasoned answer."
        await m.submitDefense()
        #expect(m.phase == .result)
        #expect(m.defenseResult?.grade == "A")
        #expect(m.overallPassed)
    }

    @Test("A failing defense fails overall even with a perfect quiz")
    func defenseFailOverall() async {
        let m = model { _ in .init(grade: "C", pass: false, feedback: "Too shallow.") }
        answerAll(m, correct: 5); m.submitQuiz(); m.continueAfterQuiz()
        m.defenseAnswer = "Weak answer."
        await m.submitDefense()
        #expect(m.phase == .result)
        #expect(!m.overallPassed)
    }

    @Test("A grading error keeps the student on the defense with a retryable error")
    func defenseError() async {
        let m = model { _ in throw StubError() }
        answerAll(m, correct: 5); m.submitQuiz(); m.continueAfterQuiz()
        m.defenseAnswer = "An answer."
        await m.submitDefense()
        #expect(m.phase == .defense)
        #expect(m.defenseError != nil)
        #expect(m.defenseResult == nil)
    }

    @Test("Grading-unavailable is reported honestly, not as a connection error")
    func defenseGradingUnavailable() async {
        let m = model { _ in throw DefenseGradingError.unavailable }
        answerAll(m, correct: 5); m.submitQuiz(); m.continueAfterQuiz()
        m.defenseAnswer = "An answer."
        await m.submitDefense()
        #expect(m.phase == .defense)
        #expect(m.defenseResult == nil)
        // The endpoint doesn't exist on this server — blaming the student's
        // connection would send them into a retry loop that can never succeed.
        #expect(m.defenseError?.contains("connection and try again") == false)
        #expect(m.defenseError?.contains("isn't available yet") == true)
    }

    @Test("Empty/whitespace defense answers are not submittable")
    func emptyDefenseBlocked() {
        let m = model()
        m.defenseAnswer = "   \n  "
        #expect(!m.canSubmitDefense)
    }

    @Test("Retake clears everything back to the quiz")
    func retakeResets() async {
        let m = model()
        answerAll(m, correct: 5); m.submitQuiz(); m.continueAfterQuiz()
        m.defenseAnswer = "x"
        await m.submitDefense()
        m.retake()
        #expect(m.phase == .quiz)
        #expect(!m.quizSubmitted)
        #expect(m.selections.isEmpty)
        #expect(m.defenseAnswer.isEmpty)
        #expect(m.defenseResult == nil)
    }

    @Test("optionLetter maps indexes to A–D")
    func optionLetters() {
        #expect(UnitTestViewModel.optionLetter(0) == "A")
        #expect(UnitTestViewModel.optionLetter(3) == "D")
    }

    @Test("Scoring is case-insensitive against the authored answer letter")
    func caseInsensitiveScoring() {
        // Authored answer is lowercase "b"; the user taps option "B".
        let test = UnitTest(
            unitId: "u",
            questions: [UnitTestQuestion(id: "q", q: "?", options: ["a", "b", "c", "d"], answer: "b", explanation: "e")],
            defensePrompt: "d"
        )
        let m = UnitTestViewModel(unit: makeUnit(), test: test,
                                  gradeDefense: { _ in .init(grade: "A", pass: true, feedback: "") })
        m.select("B", for: "q")
        m.submitQuiz()
        #expect(m.mcqScore == 1)
        #expect(m.isCorrect(test.questions[0]) == true)
    }
}
