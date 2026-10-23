#if os(macOS)
import Foundation
import Testing
import DesignSystem
@testable import CurriculumFeature

/// The Mac's unit check in Night Studio (SPEC.md §5.5): the shared answer
/// row's marks for each graded state, and its words.
@Suite("Night unit check")
@MainActor
struct NightUnitTestTests {
    private func state(selected: Bool, submitted: Bool, answer: Bool) -> UnitTestOptionState {
        UnitTestOptionState(letter: "B", text: "Tokens", isSelected: selected, isSubmitted: submitted, isAnswer: answer)
    }

    @Test("Each row state maps to the row the lesson's check draws")
    func marks() {
        #expect(NightUnitTestContent.mark(for: state(selected: false, submitted: false, answer: true)) == .rest)
        #expect(NightUnitTestContent.mark(for: state(selected: true, submitted: false, answer: false)) == .picked)
        #expect(NightUnitTestContent.mark(for: state(selected: true, submitted: true, answer: true)) == .correct(picked: true))
        #expect(NightUnitTestContent.mark(for: state(selected: false, submitted: true, answer: true)) == .correct(picked: false))
        #expect(NightUnitTestContent.mark(for: state(selected: true, submitted: true, answer: false)) == .wrong)
        #expect(NightUnitTestContent.mark(for: state(selected: false, submitted: true, answer: false)) == .other)
    }

    @Test("The words: \"Written answer\", the unit in a sentence, the existing rules")
    func copy() throws {
        #expect(NightUnitTestCopy.eyebrow(unitNumber: "01") == "Unit 1 check")
        #expect(NightUnitTestCopy.writtenAnswer == "Written answer")
        #expect(NightUnitTestCopy.score(4, of: 5) == "You got 4 of 5 correct.")
        #expect(NightUnitTestCopy.instructions(total: 5, needed: 4)
                == "Answer all 5 questions, then submit. You need 4 of 5 correct to move on.")
        let lines = [NightUnitTestCopy.eyebrow(unitNumber: "01"), NightUnitTestCopy.question(1),
                     NightUnitTestCopy.instructionsKeyboard, NightUnitTestCopy.instructions(total: 5, needed: 4),
                     NightUnitTestCopy.continueToWritten, NightUnitTestCopy.seeResults, NightUnitTestCopy.writtenAnswer,
                     NightUnitTestCopy.writtenLead(score: 5, total: 5), NightUnitTestCopy.writtenPlaceholder,
                     NightUnitTestCopy.grading, NightUnitTestCopy.submitWritten, NightUnitTestCopy.mastered,
                     NightUnitTestCopy.almost, NightUnitTestCopy.notReached, NightUnitTestCopy.grade("A"),
                     NightUnitTestCopy.masteredLine(unitTitle: "How AI Actually Works"),
                     NightUnitTestCopy.notPassedLine(quizPassed: true), NightUnitTestCopy.notPassedLine(quizPassed: false),
                     NightUnitTestCopy.retake, NightUnitTestCopy.done]
        for pattern in ["notebook", "saved", #"\b\d+\s?min\b"#, "defense", "streak", "previewable"] {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for line in lines {
                #expect(regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil,
                        "“\(line)” matches /\(pattern)/")
            }
        }
    }
}
#endif
