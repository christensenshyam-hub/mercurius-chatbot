#if os(macOS)
import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature
import PersistenceKit

/// What the Mac's Today overview says: the next stop, the week, the streak
/// (never a "0") and a recent chat's line.
@Suite("Mac Today")
@MainActor
struct MacTodayTests {

    private func store() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    private var unit1: CurriculumFeature.Unit { MercuriusCurriculum.units[0] }

    @Test("A fresh path: Up next is Lesson 1 of Unit 1, to start")
    func freshPath() {
        let progress = store()
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.eyebrow == "Up next · Unit 1 · Lesson 1 of \(unit1.lessons.count)")
        #expect(next.title == unit1.lessons[0].title)
        #expect(next.detail == unit1.lessons[0].objective)
        #expect(next.buttonTitle == "Start Lesson 1")
        #expect(next.unitProgress?.done == 0)
        #expect(next.unitProgress?.label == "0 of \(unit1.lessons.count) lessons done in Unit 1")
    }

    @Test("An opened lesson is continued; the next one after a finished lesson is started")
    func continueOrStart() {
        let progress = store()
        progress.markOpened(unit1.lessons[0].id)
        #expect(MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
            .buttonTitle == "Continue Lesson 1")
        progress.markCompleted(unit1.lessons[0].id)
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.buttonTitle == "Start Lesson 2")
        #expect(next.unitProgress?.done == 1)
    }

    @Test("A unit's lessons all done: Up next is its check")
    func unitCheck() {
        let progress = store()
        for lesson in unit1.lessons { progress.markCompleted(lesson.id) }
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.eyebrow == "Up next · Unit 1 check")
        #expect(next.buttonTitle == "Take the Unit 1 Check")
        #expect(next.title == unit1.title)
    }

    @Test("The whole path done: a review, no progress bar")
    func pathDone() {
        let progress = store()
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { progress.markCompleted(lesson.id) }
            progress.markUnitMastered(unit.id)
        }
        let next = MacTodayView.upNext(state: HomeState.build(streak: 0, progress: progress), progress: progress)
        #expect(next.buttonTitle == "Review Your Lessons")
        #expect(next.unitProgress == nil)
    }

    @Test("The streak card never says 0")
    func streakWords() {
        #expect(MacTodayView.streakHeadline(0) == "No streak yet")
        #expect(MacTodayView.streakHeadline(-2) == "No streak yet")
        #expect(MacTodayView.streakHeadline(1) == "1 day")
        #expect(MacTodayView.streakHeadline(6) == "6 days")
    }

    @Test("The week card counts lessons against the goal, and past it")
    func weekWords() {
        let start = Date()
        func week(_ done: Int, _ goal: Int) -> WeeklyPlan {
            WeeklyPlan(weekStart: start, done: done, goal: goal, next: [], projectedFinish: nil)
        }
        #expect(MacTodayView.weekHeadline(week(1, 2)) == "1 of 2 lessons")
        #expect(MacTodayView.weekHeadline(week(3, 2)) == "3 lessons")
        #expect(MacTodayView.weekDetail(week(1, 2)) == "Goal: 2 lessons a week.")
        #expect(MacTodayView.weekDetail(week(2, 2)) == "Goal met. Anything more is a bonus.")
    }

    @Test("A recent chat's line names its mode")
    func chatLine() {
        let summary = ConversationSummary(id: UUID(), mode: "debate", title: "Is AI art art?", preview: "",
                                          messageCount: 4, createdAt: Date(), updatedAt: Date())
        #expect(MacTodayView.chatDetail(summary).hasPrefix("Debate · "))
    }
}
#endif
