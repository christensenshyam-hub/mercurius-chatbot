import Testing
import Foundation
import SwiftUI
@testable import CurriculumFeature

/// The unit check from the keyboard (the Mac): which key picks which
/// option, and when Escape may leave without losing anything.
@Suite("Unit check keyboard")
@MainActor
struct UnitTestKeyboardTests {

    @Test("A–D (either case) and 1–4 pick an option; other keys and out-of-range ones don't")
    func optionKeys() {
        #expect(UnitTestViewModel.optionLetter(forKey: "a", optionCount: 4) == "A")
        #expect(UnitTestViewModel.optionLetter(forKey: "D", optionCount: 4) == "D")
        #expect(UnitTestViewModel.optionLetter(forKey: "1", optionCount: 4) == "A")
        #expect(UnitTestViewModel.optionLetter(forKey: "4", optionCount: 4) == "D")
        #expect(UnitTestViewModel.optionLetter(forKey: "e", optionCount: 4) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "5", optionCount: 4) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "0", optionCount: 4) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "c", optionCount: 2) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "ab", optionCount: 4) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "\r", optionCount: 4) == nil)
        #expect(UnitTestViewModel.optionLetter(forKey: "é", optionCount: 4) == nil)
    }

    private func makeModel() throws -> UnitTestViewModel {
        let unit = try #require(MercuriusCurriculum.units.first)
        let test = try #require(MercuriusCurriculum.unitTest(for: unit.id))
        return UnitTestViewModel(unit: unit, test: test, gradeDefense: { _ in
            UnitTestViewModel.DefenseResult(grade: "A", pass: true, feedback: "Good.")
        })
    }

    @Test("Leaving loses nothing before a pick; a pick or a written answer would be lost")
    func exitLosesNothing() throws {
        let model = try makeModel()
        #expect(model.exitLosesNothing)
        let first = try #require(model.questions.first)
        model.select("A", for: first.id)
        #expect(!model.exitLosesNothing, "a pick would be lost")
    }

    @Test("On the written question, only an empty answer leaves on Escape")
    func defenseExit() throws {
        let model = try makeModel()
        for question in model.questions {
            model.select(question.answer.uppercased(), for: question.id)
        }
        model.submitQuiz()
        model.continueAfterQuiz()
        #expect(model.phase == .defense)
        #expect(model.exitLosesNothing)
        model.defenseAnswer = "Tokens are pieces of words"
        #expect(!model.exitLosesNothing)
        model.defenseAnswer = "   "
        #expect(model.exitLosesNothing)
    }
}

/// The Mac path page's window title and subtitle.
@Suite("Mac path title")
@MainActor
struct MacPathTitleTests {
    @Test("A unit's page is \"Unit N of 8\" under Learning Path; the whole path is all units")
    func subtitle() {
        let units = MercuriusCurriculum.units
        #expect(CurriculumView<EmptyView>.macSubtitle(unitId: units[0].id) == "Unit 1 of \(units.count)")
        #expect(CurriculumView<EmptyView>.macSubtitle(unitId: units[units.count - 1].id)
            == "Unit \(units.count) of \(units.count)")
        #expect(CurriculumView<EmptyView>.macSubtitle(unitId: nil) == "All units")
        #expect(CurriculumView<EmptyView>.macSubtitle(unitId: "nope") == "All units")
    }
}
