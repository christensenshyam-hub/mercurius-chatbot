import Testing
@testable import CurriculumFeature

// NOTE: no `import Foundation` (its `Unit` collides with CurriculumFeature.Unit).

// AUD-22: what the unit test's answer rows, submit button and announcements
// say — the part of the screen VoiceOver and the faded review got wrong.

@MainActor
private func makeModel(
    gradeDefense: @escaping (String) async throws -> UnitTestViewModel.DefenseResult
        = { _ in .init(grade: "A", pass: true, feedback: "ok") }
) -> UnitTestViewModel {
    let unit = Unit(id: "unit_x", number: "0X", title: "Test Unit", summary: "s", lessons: [])
    let test = UnitTest(
        unitId: "unit_x",
        questions: (1...5).map { n in
            UnitTestQuestion(id: "q\(n)", q: "\(n)?", options: ["w", "x", "y", "z"], answer: "A", explanation: "e")
        },
        defensePrompt: "Defend your reasoning."
    )
    return UnitTestViewModel(unit: unit, test: test, shuffleSeed: 7, gradeDefense: gradeDefense)
}

/// The letter of `question`'s right answer, and one that's wrong.
private func letters(_ question: UnitTestQuestion) -> (right: String, wrong: String) {
    (question.answer, question.answer == "A" ? "B" : "A")
}

@Suite("Unit test readability")
@MainActor
struct UnitTestReadabilityTests {

    @Test("Before submitting, a row reads 'Option B: …' and says nothing of the grade")
    func openRow() {
        let m = makeModel()
        let q = m.questions[0]
        m.select("B", for: q.id)
        let picked = m.optionState(for: q, index: 1)
        #expect(picked.letter == "B")
        #expect(picked.text == q.options[1])
        #expect(picked.isSelected)
        #expect(picked.grade == .open)
        #expect(picked.accessibilityLabel == "Option B: \(q.options[1])")
        #expect(picked.accessibilityValue == nil)
        #expect(!m.optionState(for: q, index: 0).isSelected)
    }

    @Test("After submitting: the right pick, the missed answer, the wrong pick and the rest")
    func gradedRows() {
        let m = makeModel()
        let q0 = m.questions[0], q1 = m.questions[1]
        for (i, q) in m.questions.enumerated() {
            m.select(i == 1 ? letters(q).wrong : letters(q).right, for: q.id)
        }
        m.submitQuiz()

        let rightIndex0 = Int(q0.answer.unicodeScalars.first!.value) - 65
        let rightPick = m.optionState(for: q0, index: rightIndex0)
        #expect(rightPick.grade == .correctPick)
        #expect(rightPick.accessibilityValue == "Correct answer, your answer")

        let rightIndex1 = Int(q1.answer.unicodeScalars.first!.value) - 65
        let wrongIndex1 = Int(letters(q1).wrong.unicodeScalars.first!.value) - 65
        #expect(m.optionState(for: q1, index: rightIndex1).grade == .correctAnswer)
        #expect(m.optionState(for: q1, index: rightIndex1).accessibilityValue == "Correct answer")
        #expect(m.optionState(for: q1, index: wrongIndex1).grade == .wrongPick)
        #expect(m.optionState(for: q1, index: wrongIndex1).accessibilityValue == "Your answer, incorrect")

        let other = (0..<4).first { $0 != rightIndex1 && $0 != wrongIndex1 }!
        #expect(m.optionState(for: q1, index: other).grade == .other)
        #expect(m.optionState(for: q1, index: other).accessibilityValue == nil)
    }

    @Test("The submit button says what's missing until every question has a pick")
    func submitTitle() {
        let m = makeModel()
        #expect(m.submitTitle == "Answer all 5 · 0/5")
        for q in m.questions.prefix(3) { m.select("A", for: q.id) }
        #expect(m.answeredCount == 3)
        #expect(m.submitTitle == "Answer all 5 · 3/5")
        for q in m.questions { m.select("A", for: q.id) }
        #expect(m.submitTitle == "Submit answers")
    }

    @Test("The score is announced once submitted: pass and fail")
    func scoreAnnouncement() {
        let pass = makeModel()
        #expect(pass.scoreAnnouncement == nil)
        for q in pass.questions { pass.select(q.answer, for: q.id) }
        pass.submitQuiz()
        #expect(pass.scoreAnnouncement == "You got 5 of 5 correct. On to the written question.")

        let fail = makeModel()
        for q in fail.questions { fail.select(letters(q).wrong, for: q.id) }
        fail.submitQuiz()
        #expect(fail.scoreAnnouncement == "You got 0 of 5 correct. Not enough to pass this time.")
    }

    @Test("The result is announced: mastered, a graded miss, and a quiz-only miss")
    func resultAnnouncement() async {
        let mastered = makeModel()
        for q in mastered.questions { mastered.select(q.answer, for: q.id) }
        mastered.submitQuiz()
        mastered.continueAfterQuiz()
        #expect(mastered.resultAnnouncement == nil)   // still on the written question
        mastered.defenseAnswer = "Because tokens are…"
        await mastered.submitDefense()
        #expect(mastered.resultAnnouncement == "Unit mastered.")

        let graded = makeModel(gradeDefense: { _ in .init(grade: "C", pass: false, feedback: "thin") })
        for q in graded.questions { graded.select(q.answer, for: q.id) }
        graded.submitQuiz()
        graded.continueAfterQuiz()
        graded.defenseAnswer = "Short."
        await graded.submitDefense()
        #expect(graded.resultAnnouncement == "Almost there. Quiz 5 of 5. Written defense, grade C.")

        let quizOnly = makeModel()
        for q in quizOnly.questions { quizOnly.select(letters(q).wrong, for: q.id) }
        quizOnly.submitQuiz()
        quizOnly.continueAfterQuiz()
        #expect(quizOnly.resultAnnouncement == "Almost there. Quiz 0 of 5.")
    }

    @Test("A crisis answer announces no result")
    func noResultOnSupport() async {
        let m = makeModel(gradeDefense: { _ in .crisisSupport })
        for q in m.questions { m.select(q.answer, for: q.id) }
        m.submitQuiz()
        m.continueAfterQuiz()
        m.defenseAnswer = "…"
        await m.submitDefense()
        #expect(m.phase == .support)
        #expect(m.resultAnnouncement == nil)
    }
}
