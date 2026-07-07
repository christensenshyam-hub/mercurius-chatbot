import Testing
import Foundation
@testable import CurriculumFeature

/// Covers the lesson-to-lesson navigation helpers that drive the "Next lesson"
/// celebration CTA + sequential unlock.
@Suite("Curriculum navigation")
struct CurriculumNavigationTests {

    @Test("lesson(after:) returns the next lesson in the same unit")
    func nextWithinUnit() {
        let unit = MercuriusCurriculum.units[0]
        #expect(unit.lessons.count >= 2)
        #expect(MercuriusCurriculum.lesson(after: unit.lessons[0].id)?.id == unit.lessons[1].id)
    }

    @Test("lesson(after:) returns nil at a unit's last lesson")
    func nilAtUnitEnd() {
        let unit = MercuriusCurriculum.units[0]
        let last = unit.lessons.last!
        #expect(MercuriusCurriculum.lesson(after: last.id) == nil)
    }

    @Test("lesson(after:) never crosses a unit boundary")
    func doesNotCrossUnits() {
        let u1Last = MercuriusCurriculum.units[0].lessons.last!
        let u2First = MercuriusCurriculum.units[1].lessons.first!
        #expect(MercuriusCurriculum.lesson(after: u1Last.id)?.id != u2First.id)
    }

    @Test("lesson(after:) returns nil for an unknown id")
    func nilForUnknown() {
        #expect(MercuriusCurriculum.lesson(after: "no_such_lesson") == nil)
    }

    @Test("every lesson except a unit's last has a next within that unit")
    func everyNonLastHasNext() {
        for unit in MercuriusCurriculum.units {
            for (i, lesson) in unit.lessons.enumerated() {
                let next = MercuriusCurriculum.lesson(after: lesson.id)
                if i < unit.lessons.count - 1 {
                    #expect(next?.id == unit.lessons[i + 1].id)
                } else {
                    #expect(next == nil)
                }
            }
        }
    }

    @Test("unit(containingLesson:) finds the parent unit, nil for unknown")
    func parentUnitLookup() {
        let unit = MercuriusCurriculum.units[1]
        #expect(MercuriusCurriculum.unit(containingLesson: unit.lessons[0].id)?.id == unit.id)
        #expect(MercuriusCurriculum.unit(containingLesson: "nope") == nil)
    }

    /// `isLessonUnlocked` fails OPEN (returns true) when a lesson id is not
    /// found in the unit it's queried against — a defensive default that would
    /// silently bypass sequential gating. This invariant proves the real
    /// curriculum never hits that branch: every lesson resolves inside its own
    /// unit, so a future cross-unit move that forgot a migration trips here.
    @Test("Every lesson resolves within its own unit (gating never fails open)")
    func everyLessonResolvesInItsUnit() {
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons {
                #expect(
                    unit.lessons.firstIndex(where: { $0.id == lesson.id }) != nil,
                    "Lesson \(lesson.id) not found in its own unit \(unit.id)"
                )
                #expect(MercuriusCurriculum.unit(containingLesson: lesson.id)?.id == unit.id)
            }
        }
        // Lesson ids are globally unique (no id appears in two units).
        let allIds = MercuriusCurriculum.units.flatMap { $0.lessons.map(\.id) }
        #expect(allIds.count == Set(allIds).count, "Duplicate lesson id across units")
    }
}
