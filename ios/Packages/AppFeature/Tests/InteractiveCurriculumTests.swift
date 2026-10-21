import Foundation
import Testing
import CurriculumFeature
import LessonInteractives
@testable import AppFeature

/// The interactives' registry against the curriculum it points into (the
/// one test module that sees both): every card's lesson exists, none is a
/// Review lesson, and the DEBUG lesson preview opens Unit 1, Lesson 1 when
/// no card is asked for.
@Suite("Interactives: the registry against the curriculum")
struct InteractiveCurriculumTests {
    private var lessons: [CurriculumFeature.Lesson] { MercuriusCurriculum.units.flatMap(\.lessons) }

    @Test("Every card's lesson exists in Curriculum.swift")
    func lessonsExist() {
        let ids = Set(lessons.map(\.id))
        for spec in InteractiveRegistry.all {
            #expect(ids.contains(spec.lessonID), "\(spec.id)'s lesson \(spec.lessonID) isn't in the curriculum")
        }
    }

    @Test("The registry's Review lessons are the curriculum's last lesson of each unit, and hold no card")
    func reviewLessons() {
        let lastOfEachUnit = Set(MercuriusCurriculum.units.compactMap { $0.lessons.last?.id })
        #expect(InteractiveRegistry.reviewLessons == lastOfEachUnit)
        for spec in InteractiveRegistry.all {
            #expect(!lastOfEachUnit.contains(spec.lessonID), "\(spec.id) sits in a Review lesson")
        }
    }

    @Test("Every unit has at least one card, and at most two")
    func coverage() {
        for unit in MercuriusCurriculum.units {
            let ids = Set(unit.lessons.map(\.id))
            let cards = InteractiveRegistry.all.filter { ids.contains($0.lessonID) }.count
            #expect((1...2).contains(cards), "unit \(unit.number) has \(cards) cards")
        }
    }

    #if DEBUG
    @Test("With no -Interactive, the lesson preview opens Unit 1, Lesson 1")
    @MainActor
    func previewLesson() {
        #expect(RootView.previewLesson?.lesson.id == "u1_l1")
    }
    #endif
}
