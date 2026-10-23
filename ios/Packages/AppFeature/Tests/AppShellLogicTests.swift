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

// AUD-37: the Live Activity counts down only while a live streak ends tonight.
@Suite("Live Activity streak countdown")
struct StreakEndsTonightTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: d, hour: hour))!
    }

    private func endsTonight(streak: Int = 4, fresh: Bool = true, confirmedToday: Bool = false,
                             streakDay: Date?, now: Date) -> Bool {
        AppShellView.streakEndsTonight(streak: streak, isFresh: fresh, confirmedToday: confirmedToday,
                                       streakDay: streakDay, now: now, calendar: calendar)
    }

    @Test("Confirmed Monday: Wednesday is the last save day, so only Wednesday counts down")
    func lastSaveDay() {
        let monday = day(6)
        #expect(!endsTonight(streakDay: monday, now: day(6, hour: 20)))
        #expect(!endsTonight(streakDay: monday, now: day(7, hour: 20)))
        #expect(endsTonight(streakDay: monday, now: day(8, hour: 9)))
        // Thursday: already lapsed, nothing to count down to.
        #expect(!endsTonight(streakDay: monday, now: day(9, hour: 9)))
    }

    @Test("No countdown once today is saved, without a streak, or on a stale cache")
    func noCountdown() {
        let monday = day(6)
        let wednesday = day(8, hour: 9)
        #expect(!endsTonight(confirmedToday: true, streakDay: monday, now: wednesday))
        #expect(!endsTonight(streak: 0, streakDay: monday, now: wednesday))
        #expect(!endsTonight(fresh: false, streakDay: monday, now: wednesday))
        #expect(!endsTonight(streakDay: nil, now: wednesday))
    }
}
