import Testing
import Foundation
@testable import CurriculumFeature

/// Pins the weekly plan with a fixed Gregorian calendar + clock so results
/// don't depend on the machine's timezone or locale week conventions.
/// 2026-09-24 is a Thursday.
@Suite("WeeklyPlan")
@MainActor
struct WeeklyPlanTests {

    private func calendar(_ zone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int,
                      _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func makeStore(_ clock: TestClock) -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore(), now: { clock.now })
    }

    private func complete(_ ids: [String], at when: Date, in store: CurriculumProgressStore, clock: TestClock) {
        clock.now = when
        for id in ids { store.markCompleted(id) }
    }

    // MARK: - Week boundary

    @Test("Exactly Thursday 00:00 starts a new week; one second earlier is still last week")
    func thursdayMidnightBoundary() {
        let cal = calendar()
        let thursday = date(cal, 2026, 9, 24)
        let clock = TestClock(thursday)
        let store = makeStore(clock)

        #expect(WeeklyPlan.compute(progress: store, now: thursday, calendar: cal).weekStart == thursday)
        #expect(WeeklyPlan.compute(progress: store, now: thursday.addingTimeInterval(-1), calendar: cal).weekStart
                == date(cal, 2026, 9, 17))
    }

    @Test("Every day Thursday→Wednesday maps to the same week start")
    func wholeWeekSharesStart() {
        let cal = calendar()
        let store = makeStore(TestClock(.distantPast))
        for day in 24...30 {
            let now = date(cal, 2026, 9, day, 13)
            #expect(WeeklyPlan.compute(progress: store, now: now, calendar: cal).weekStart == date(cal, 2026, 9, 24),
                    "Sep \(day)")
        }
    }

    @Test("A locale whose week starts Monday still gets Thursday weeks")
    func ignoresLocaleFirstWeekday() {
        let cal = calendar(firstWeekday: 2)
        let store = makeStore(TestClock(.distantPast))
        let plan = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 9, 28, 9), calendar: cal)
        #expect(plan.weekStart == date(cal, 2026, 9, 24))
    }

    @Test("Wednesday night counts completions from Thursday 00:00 on, not before")
    func wednesdayNight() {
        let cal = calendar()
        let clock = TestClock(.distantPast)
        let store = makeStore(clock)
        complete(["u1_l1"], at: date(cal, 2026, 9, 23, 23, 59, 59), in: store, clock: clock)   // last week
        complete(["u1_l2"], at: date(cal, 2026, 9, 24), in: store, clock: clock)               // exactly the start
        complete(["u1_l3"], at: date(cal, 2026, 9, 30, 21), in: store, clock: clock)           // Wednesday evening

        let plan = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 9, 30, 22), calendar: cal)
        #expect(plan.weekStart == date(cal, 2026, 9, 24))
        #expect(plan.done == 2)
        #expect(plan.goal == 2)
    }

    @Test("Undated (pre-2.3.0) and orphaned completions never count toward this week")
    func undatedAndOrphansNotCounted() {
        let cal = calendar()
        let now = date(cal, 2026, 9, 25, 12)
        let store = makeStore(TestClock(now))
        store.merge(completed: ["u1_l1"], mastered: [], remoteVersion: 1)   // no server date
        store.merge(completed: ["u99_l1"], mastered: [], remoteVersion: MercuriusCurriculum.version + 1,
                    remoteUpdatedAt: ["u99_l1": now])

        let plan = WeeklyPlan.compute(progress: store, now: now, calendar: cal)
        #expect(plan.done == 0)
    }

    // MARK: - DST

    @Test("Fall-back week (169h): a late-Wednesday completion still counts")
    func fallBackWeek() {
        // US DST ends Sun 2026-11-01; the week Thu Oct 29 → Thu Nov 5 is 169 hours.
        let cal = calendar("America/New_York")
        let clock = TestClock(.distantPast)
        let store = makeStore(clock)
        let lateWednesday = date(cal, 2026, 11, 4, 23, 30)
        complete(["u1_l1"], at: lateWednesday, in: store, clock: clock)

        let plan = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 11, 4, 23, 45), calendar: cal)
        let start = date(cal, 2026, 10, 29)
        #expect(plan.weekStart == start)
        // A fixed 7×24h window would end at Wed 23:00 local and miss it.
        #expect(lateWednesday > start.addingTimeInterval(7 * 86_400))
        #expect(plan.done == 1)
    }

    @Test("Spring-forward week (167h): the next week starts at local midnight, not 01:00")
    func springForwardWeek() {
        // US DST starts Sun 2026-03-08; the week Thu Mar 5 → Thu Mar 12 is 167 hours.
        let cal = calendar("America/New_York")
        let clock = TestClock(.distantPast)
        let store = makeStore(clock)
        let lessons = MercuriusCurriculum.allLessons
        // Leave exactly two lessons: one week at goal 2.
        complete(lessons.dropLast(2).map(\.id), at: date(cal, 2026, 3, 1), in: store, clock: clock)

        let wednesday = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 3, 11, 12), calendar: cal)
        #expect(wednesday.weekStart == date(cal, 2026, 3, 5))
        #expect(wednesday.projectedFinish == date(cal, 2026, 3, 12))

        complete([lessons[lessons.count - 2].id], at: date(cal, 2026, 3, 12, 0, 15), in: store, clock: clock)
        let thursday = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 3, 12, 0, 30), calendar: cal)
        #expect(thursday.weekStart == date(cal, 2026, 3, 12))
        #expect(thursday.done == 1)
    }

    // MARK: - Next stops

    @Test("A fresh learner's next two stops are Lessons 1 and 2")
    func freshNext() {
        let store = makeStore(TestClock(.distantPast))
        let unit1 = MercuriusCurriculum.units[0]
        let plan = WeeklyPlan.compute(progress: store, now: date(calendar(), 2026, 9, 24), calendar: calendar())
        #expect(plan.next == [.lesson(unit1.lessons[0]), .lesson(unit1.lessons[1])])
    }

    @Test("At a unit's last lesson the unit test follows; after the lessons, the test then the next unit")
    func nextCrossesIntoUnitTest() {
        let clock = TestClock(.distantPast)
        let store = makeStore(clock)
        let unit1 = MercuriusCurriculum.units[0]
        let unit2 = MercuriusCurriculum.units[1]
        let now = date(calendar(), 2026, 9, 24)

        for lesson in unit1.lessons.dropLast() { store.markCompleted(lesson.id) }
        #expect(WeeklyPlan.compute(progress: store, now: now, calendar: calendar()).next
                == [.lesson(unit1.lessons.last!), .unitTest(unit1)])

        store.markCompleted(unit1.lessons.last!.id)
        #expect(WeeklyPlan.compute(progress: store, now: now, calendar: calendar()).next
                == [.unitTest(unit1), .lesson(unit2.lessons[0])])
    }

    @Test("The walk skips lessons already completed out of order and mastered unit tests")
    func nextSkipsDone() {
        let store = makeStore(TestClock(.distantPast))
        let unit1 = MercuriusCurriculum.units[0]
        let unit2 = MercuriusCurriculum.units[1]
        for lesson in unit1.lessons { store.markCompleted(lesson.id) }
        store.markUnitMastered(unit1.id)
        store.merge(completed: [unit2.lessons[1].id], mastered: [], remoteVersion: 1)

        let plan = WeeklyPlan.compute(progress: store, now: date(calendar(), 2026, 9, 24), calendar: calendar())
        #expect(plan.next == [.lesson(unit2.lessons[0]), .lesson(unit2.lessons[2])])
    }

    // MARK: - Projection

    @Test("projectedFinish is weekStart + ceil(remaining / goal) weeks")
    func projection() {
        let cal = calendar()
        let now = date(cal, 2026, 9, 26, 10)
        let store = makeStore(TestClock(now))
        let remaining = MercuriusCurriculum.allLessons.count
        let start = date(cal, 2026, 9, 24)

        let atTwo = WeeklyPlan.compute(progress: store, now: now, calendar: cal, goal: 2)
        #expect(atTwo.projectedFinish == cal.date(byAdding: .day, value: 7 * ((remaining + 1) / 2), to: start))

        let atFive = WeeklyPlan.compute(progress: store, now: now, calendar: cal, goal: 5)
        #expect(atFive.goal == 5)
        #expect(atFive.projectedFinish == cal.date(byAdding: .day, value: 7 * ((remaining + 4) / 5), to: start))
    }

    @Test("Unit tests and orphans don't count as remaining lessons; a finished path projects nothing")
    func finishedPath() {
        let cal = calendar()
        let store = makeStore(TestClock(.distantPast))
        for lesson in MercuriusCurriculum.allLessons { store.markCompleted(lesson.id) }
        store.merge(completed: ["u99_l1"], mastered: [], remoteVersion: MercuriusCurriculum.version + 1)

        let plan = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 9, 24), calendar: cal)
        #expect(plan.projectedFinish == nil)
        // Every unit test is still ahead, so the plan keeps pointing there.
        #expect(plan.next == [.unitTest(MercuriusCurriculum.units[0]), .unitTest(MercuriusCurriculum.units[1])])
    }

    @Test("A non-positive goal is clamped to 1 rather than dividing by zero")
    func goalClamped() {
        let cal = calendar()
        let store = makeStore(TestClock(.distantPast))
        let plan = WeeklyPlan.compute(progress: store, now: date(cal, 2026, 9, 24), calendar: cal, goal: 0)
        #expect(plan.goal == 1)
        #expect(plan.projectedFinish == cal.date(byAdding: .day, value: 7 * MercuriusCurriculum.allLessons.count,
                                                 to: date(cal, 2026, 9, 24)))
    }
}
