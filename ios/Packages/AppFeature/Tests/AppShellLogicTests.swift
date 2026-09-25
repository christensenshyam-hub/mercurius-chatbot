import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature

@Suite("Lesson celebration's next stop")
@MainActor
struct CelebrationNextStopTests {

    private var unit1: CurriculumFeature.Unit { MercuriusCurriculum.units[0] }

    private func makeStore() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    @Test("Mid-unit, the next lesson; after the unit's last lesson, its check once it's unlocked")
    func normalPath() {
        let store = makeStore()
        #expect(AppShellView.resolvedNextStop(after: unit1.lessons[0].id, progress: store)
                == .lesson(unit1.lessons[1]))
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        let last = unit1.lessons[unit1.lessons.count - 1]
        #expect(AppShellView.resolvedNextStop(after: last.id, progress: store) == .unitTest(unit1))
    }

    @Test("A gap earlier in the unit: the celebration sends the student there, never to a locked check")
    func lockedCheckGoesToTheGap() {
        // Legacy mark-on-open data: Lessons 1 and 3 done, Lesson 2 never was.
        let store = makeStore()
        store.markCompleted(unit1.lessons[0].id)
        store.markCompleted(unit1.lessons[2].id)
        let last = unit1.lessons[unit1.lessons.count - 1]
        store.markCompleted(last.id)
        #expect(!store.isUnitTestUnlocked(unit1))

        let next = AppShellView.resolvedNextStop(after: last.id, progress: store)
        #expect(next == .lesson(unit1.lessons[1]))
        // The celebration names Lesson 2, not "Unit 1 check" — and the button
        // opens what it names, since `advance(to:)` gets this same value.
        #expect(next.map(AppShellView.celebrationStop)
                == .lesson(number: unit1.lessons[1].number, title: unit1.lessons[1].title))

        // Finishing that gap unlocks the check: offered next, not a review
        // of the already-finished Lesson 3 — matching Home's frontier.
        store.markCompleted(unit1.lessons[1].id)
        #expect(AppShellView.resolvedNextStop(after: unit1.lessons[1].id, progress: store) == .unitTest(unit1))
        #expect(store.frontier() == .unitTest(unit1))
    }

    @Test("A finished next lesson is skipped for the unit's first unfinished one")
    func finishedNextLessonGoesToTheGap() {
        // Lessons 1 and 3 done; Lesson 2 just finished; Lesson 4 never was.
        let store = makeStore()
        store.markCompleted(unit1.lessons[0].id)
        store.markCompleted(unit1.lessons[2].id)
        store.markCompleted(unit1.lessons[1].id)
        #expect(AppShellView.resolvedNextStop(after: unit1.lessons[1].id, progress: store)
                == .lesson(unit1.lessons[3]))
    }

    @Test("Replaying inside a mastered unit is a plain review hop to the next lesson")
    func reviewHopInMasteredUnit() {
        let store = makeStore()
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        store.markUnitMastered(unit1.id)
        #expect(AppShellView.resolvedNextStop(after: unit1.lessons[1].id, progress: store)
                == .lesson(unit1.lessons[2]))
    }

    @Test("Before the last lesson itself is marked complete, no check and no self-referral")
    func lastLessonNotYetComplete() {
        let store = makeStore()
        for lesson in unit1.lessons.dropLast() { store.markCompleted(lesson.id) }
        let last = unit1.lessons[unit1.lessons.count - 1]
        #expect(AppShellView.resolvedNextStop(after: last.id, progress: store) == nil)
    }
}

@Suite("App Store review prompt timing")
struct ReviewPromptTimingTests {

    @Test("Asked only after a completion earned it and nothing covers the shell")
    func earnedAndClear() {
        var timing = AppShellView.ReviewPromptTiming()
        let unearned = timing.startIfClear(covered: false)
        #expect(!unearned)
        timing.earn()
        let whileCovered = timing.startIfClear(covered: true)
        #expect(!whileCovered)
        #expect(timing.isDue)
        let started = timing.startIfClear(covered: false)
        #expect(started)
        #expect(!timing.isDue)
        let asked = timing.askAfterSettling(covered: false)
        #expect(asked)
    }

    @Test("A cover presented during the settle delay re-arms the prompt for when it closes")
    func coverDuringDelay() {
        var timing = AppShellView.ReviewPromptTiming()
        timing.earn()
        let started = timing.startIfClear(covered: false)
        #expect(started)
        // A path node tapped, or a reminder's lesson presented, within 600 ms.
        let askedOverCover = timing.askAfterSettling(covered: true)
        #expect(!askedOverCover)
        #expect(timing.isDue)
        // That lesson closes: the prompt goes through then.
        let restarted = timing.startIfClear(covered: false)
        let asked = timing.askAfterSettling(covered: false)
        #expect(restarted && asked)
        #expect(!timing.isDue)
    }
}

@Suite("Tapped reminder presentation delay")
struct PendingLessonDelayTests {

    @Test("From the Chat tab a ChatView sheet may be closing, so the longer wait applies")
    func delays() {
        #expect(AppShellView.pendingLessonDelay(closingUnitTest: false, fromTab: .curriculum) == .milliseconds(250))
        #expect(AppShellView.pendingLessonDelay(closingUnitTest: false, fromTab: .chat) == .milliseconds(600))
        #expect(AppShellView.pendingLessonDelay(closingUnitTest: true, fromTab: .curriculum) == .milliseconds(600))
    }
}
