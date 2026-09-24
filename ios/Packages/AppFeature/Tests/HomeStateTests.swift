import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature

@Suite("HomeState")
@MainActor
struct HomeStateTests {

    /// Thursday 2026-09-24 10:00 UTC; the week under test starts that day at
    /// 00:00.
    private let now = Date(timeIntervalSince1970: 1_790_244_000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func makeStore(at date: Date? = nil) -> CurriculumProgressStore {
        let stamp = date ?? now
        return CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { stamp })
    }

    private func build(_ store: CurriculumProgressStore, streak: Int = 0) -> HomeState {
        HomeState.build(streak: streak, progress: store, now: now, calendar: calendar)
    }

    private var unit1: CurriculumFeature.Unit { MercuriusCurriculum.units[0] }

    @Test("Fresh path: next stop is Lesson 1, offered as a start")
    func freshPath() {
        let state = build(makeStore())
        #expect(state.next == .lesson(unit1.lessons[0]))
        #expect(!state.hasProgress)
        #expect(!state.resumesNext)
        #expect(state.lastLessonTitle == nil)
        #expect(state.primaryActionTitle == "Start Lesson 1")
        #expect(state.week.done == 0)
        #expect(state.weekLabel == "This week · 0 of 2")
        #expect(state.greeting(hour: 9) == "Good morning! Your first lesson is ready when you are.")
    }

    @Test("Lesson 1 opened but not finished: continue it, and Merc names it")
    func resumesOpenedLesson() {
        let store = makeStore()
        store.markOpened(unit1.lessons[0].id)
        let state = build(store)
        #expect(state.resumesNext)
        #expect(state.lastLessonTitle == unit1.lessons[0].title)
        #expect(state.primaryActionTitle == "Continue · Lesson 1: \(unit1.lessons[0].title)")
        #expect(state.greeting(hour: 15) == "Welcome back! Let's pick up “\(unit1.lessons[0].title)”.")
    }

    @Test("Two lessons done this week: next is Lesson 3, the week ring is full")
    func weekGoalMet() {
        let store = makeStore()
        store.markCompleted(unit1.lessons[0].id)
        store.markCompleted(unit1.lessons[1].id)
        let state = build(store)
        #expect(state.next == .lesson(unit1.lessons[2]))
        #expect(state.hasProgress)
        #expect(state.primaryActionTitle == "Continue · Lesson 3: \(unit1.lessons[2].title)")
        #expect(state.week.done == 2)
        #expect(state.weekLabel == "This week · 2 of 2")
        #expect(state.weekProgress == 1)
        #expect(state.greeting(hour: 19) == "Good evening! This week's goal is done — anything more is a bonus.")
    }

    @Test("Past the goal the label counts lessons instead of reading '3 of 2'")
    func pastGoal() {
        let store = makeStore()
        for lesson in unit1.lessons.prefix(3) { store.markCompleted(lesson.id) }
        let state = build(store)
        #expect(state.weekLabel == "This week · 3 lessons")
        #expect(state.weekAccessibilityLabel == "This week: 3 lessons done. Weekly goal met.")
        #expect(state.weekProgress == 1)
    }

    @Test("Lessons finished last week don't count toward this one")
    func lastWeekDoesNotCount() {
        let lastWeek = now.addingTimeInterval(-8 * 86_400)
        let store = makeStore(at: lastWeek)
        store.markCompleted(unit1.lessons[0].id)
        let state = build(store)
        #expect(state.week.done == 0)
        #expect(state.greeting(hour: 12) == "Good afternoon! Your next lesson is waiting.")
    }

    @Test("All of a unit's lessons done: the unit check is the next stop")
    func unitCheckNext() {
        let store = makeStore()
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        let state = build(store)
        #expect(state.next == .unitTest(unit1))
        #expect(state.primaryActionTitle == "Take the Unit 1 check")
        #expect(state.greeting(hour: 9) == "Unit 1's lessons are done. Ready for the check?")
    }

    @Test("A live streak leads the greeting; a 1-day streak doesn't")
    func streakGreeting() {
        #expect(build(makeStore(), streak: 4).greeting(hour: 9) == "Day 4 — let's keep your streak alive!")
        #expect(build(makeStore(), streak: 1).greeting(hour: 9).hasPrefix("Good morning!"))
        #expect(build(makeStore(), streak: -3).streak == 0)
    }

    @Test("The whole path finished: no next stop, and the CTA offers a review")
    func pathFinished() {
        let store = makeStore()
        for unit in MercuriusCurriculum.units {
            for lesson in unit.lessons { store.markCompleted(lesson.id) }
            store.markUnitMastered(unit.id)
        }
        let state = build(store)
        #expect(state.next == nil)
        #expect(state.primaryActionTitle == "Review your lessons")
        #expect(state.greeting(hour: 9) == "You've finished the whole path. Chat with me any time to go deeper.")
    }

    @Test("A reminder opens the frontier lesson; a unit check frontier opens nothing specific")
    func frontierLessonId() {
        let store = makeStore()
        #expect(store.frontierLessonId == unit1.lessons[0].id)
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        #expect(store.frontierLessonId == nil)
    }

    @Test("Late-night opener")
    func openers() {
        #expect(HomeState.opener(hour: 2) == "Up late? Perfect time to learn.")
        #expect(HomeState.opener(hour: 23) == "Up late? Perfect time to learn.")
        #expect(HomeState.opener(hour: 5) == "Good morning!")
    }

    @Test("The celebration's next stop mirrors the path's")
    func celebrationStop() {
        #expect(AppShellView.celebrationStop(.lesson(unit1.lessons[1]))
                == .lesson(number: 2, title: unit1.lessons[1].title))
        #expect(AppShellView.celebrationStop(.unitTest(unit1))
                == .unitTest(unitNumber: unit1.number, unitTitle: unit1.title))
    }
}
