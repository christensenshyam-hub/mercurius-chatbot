import Testing
import Foundation
import PersistenceKit
@testable import EngagementFeature

/// Pins the reminder plan: rotating Merc copy, streak-defense selection, and
/// the today-slot rules. All inputs fixed (calendar, now) so runs are
/// deterministic on any machine or CI timezone.
struct ReminderPlannerTests {

    /// Fixed clock: 2026-07-06 10:00 UTC, reminders at 18:00.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 10))!
    }

    private func plan(streak: Int? = nil, chattedToday: Bool = false,
                      now: Date? = nil, hour: Int = 18) -> [ReminderPlanner.PlannedReminder] {
        ReminderPlanner.plan(now: now ?? morning, calendar: calendar,
                             hour: hour, minute: 0,
                             streak: streak, chattedToday: chattedToday)
    }

    @Test("A live streak makes the FIRST slot the defense line, with the number")
    func firstSlotIsDefense() {
        let p = plan(streak: 4)
        #expect(p.count == 14)
        #expect(p[0].body.contains("4-day streak is on the line"))
        #expect(p[0].pose == .sleep)   // the streak is about to doze off
        // Only the first slot defends; the rest rotate.
        #expect(!p[1].body.contains("streak is on the line"))
        #expect(p[1].pose != .sleep)
    }

    @Test("Every rotation line carries its paired pose")
    func rotationPoses() {
        let p = plan(streak: nil)
        for reminder in p {
            let match = ReminderPlanner.dailyLines.first { $0.body == reminder.body }
            #expect(match?.pose == reminder.pose)
        }
    }

    @Test("Pose tiles render to non-empty PNG data")
    @MainActor func tilesRender() {
        for pose in ReminderPlanner.Pose.allCases {
            let data = MercNotificationArt.pngData(for: pose)
            #expect((data?.count ?? 0) > 1000, "pose \(pose.rawValue) rendered no data")
        }
    }

    @Test("Chatting today drops today's slot and moves the defense to tomorrow")
    func chattedTodayMovesDefense() {
        let p = plan(streak: 5, chattedToday: true)
        #expect(p.count == 13)                      // today's slot dropped
        #expect(p[0].fireDate.day == 7)             // first slot is tomorrow
        #expect(p[0].body.contains("5-day streak"))
    }

    @Test("A reminder time already past drops today's slot")
    func pastTimeDropsToday() {
        let evening = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 20))!
        let p = plan(streak: nil, now: evening, hour: 18)
        #expect(p.count == 13)
        #expect(p[0].fireDate.day == 7)
    }

    @Test("No streak means pure rotation — no defense copy anywhere")
    func noStreakNoDefense() {
        let p = plan(streak: nil)
        #expect(p.count == 14)
        #expect(p.allSatisfy { !$0.body.contains("streak is on the line") })
    }

    @Test("Adjacent days get different rotation lines; ids are unique + date-keyed")
    func rotationAndIds() {
        let p = plan(streak: nil)
        for (a, b) in zip(p, p.dropFirst()) {
            #expect(a.body != b.body)
        }
        #expect(Set(p.map(\.id)).count == p.count)
        #expect(p.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
        #expect(p[0].id == ReminderPlanner.idPrefix + "2026-07-06")
    }

    @Test("Fire dates carry the chosen hour/minute on consecutive days")
    func fireDates() {
        let p = plan(streak: 2)
        #expect(p.allSatisfy { $0.fireDate.hour == 18 && $0.fireDate.minute == 0 })
        #expect(p.map(\.fireDate.day) == Array(6...19))
    }

    @Test("The daily window covers two weeks by default and honours an explicit horizon")
    func horizon() {
        #expect(plan(streak: 3).count == 14)
        let week = ReminderPlanner.plan(now: morning, calendar: calendar, hour: 18, minute: 0,
                                        streak: 3, chattedToday: false, horizonDays: 7)
        #expect(week.count == 7)
        // 14 daily + 2 weekly stays far under iOS's 64 pending-request cap.
        #expect(plan(streak: 3).count + ReminderPlanner.weeklyPlan().count <= 64)
    }

    // MARK: - Streak horizon

    private func day(_ d: Int, hour: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: 2026, month: 7, day: d, hour: hour))!
    }

    @Test("The daily window runs through the last day a chat still saves the streak")
    func dailyHorizonDays() {
        // Confirmed Monday the 6th: a chat Tuesday or Wednesday continues it.
        let monday = day(6)
        #expect(ReminderPlanner.dailyHorizon(now: day(6, hour: 12), streakDay: monday, calendar: calendar) == 3)
        #expect(ReminderPlanner.dailyHorizon(now: day(7, hour: 9), streakDay: monday, calendar: calendar) == 2)
        #expect(ReminderPlanner.dailyHorizon(now: day(8, hour: 23), streakDay: monday, calendar: calendar) == 1)
        #expect(ReminderPlanner.dailyHorizon(now: day(9, hour: 0), streakDay: monday, calendar: calendar) == 0)
        #expect(ReminderPlanner.dailyHorizon(now: day(30), streakDay: monday, calendar: calendar) == 0)
    }

    @Test("A Monday chat plans Tuesday and Wednesday only — nothing once the streak has lapsed")
    func streakDayBoundsThePlan() {
        let p = ReminderPlanner.plan(now: day(6, hour: 12), calendar: calendar, hour: 18, minute: 0,
                                     streak: 4, streakDay: day(6), chattedToday: true)
        #expect(p.map(\.fireDate.day) == [7, 8])
        #expect(p[0].body.contains("4-day streak"))

        // With the weekly nudges on, Wednesday's rotation slot yields to the nudge.
        let quiet = ReminderPlanner.plan(now: day(6, hour: 12), calendar: calendar, hour: 18, minute: 0,
                                         streak: 4, streakDay: day(6), chattedToday: true,
                                         quietWeekdays: ReminderPlanner.weeklyWeekdays)
        #expect(quiet.map(\.fireDate.day) == [7])

        // Opened again on Thursday without chatting: the streak is gone.
        let lapsed = ReminderPlanner.plan(now: day(9, hour: 10), calendar: calendar, hour: 18, minute: 0,
                                          streak: 4, streakDay: day(6), chattedToday: false)
        #expect(lapsed.isEmpty)
    }

    @Test("A launch seed's UTC-midnight stamp doesn't cut the last save day west of UTC")
    func seedStampKeepsLastSaveDay() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // `seed` for last_session_date 2026-07-06 stamps 00:00 UTC — 20:00
        // on Sunday the 5th in New York.
        let seedStamp = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let streakDay = StreakStore.confirmedDay(for: seedStamp, calendar: newYork)
        let p = ReminderPlanner.plan(now: day(6, hour: 12, in: newYork), calendar: newYork, hour: 18, minute: 0,
                                     streak: 2, streakDay: streakDay, chattedToday: false)
        #expect(p.map(\.fireDate.day) == [6, 7, 8])
    }

    // MARK: - Weekly nudges

    @Test("Weekly nudges: Wednesday 19:00 and Sunday 18:00 (Gregorian weekdays)")
    func weeklyComponents() {
        let w = ReminderPlanner.weeklyPlan()
        #expect(w.count == 2)
        #expect(w[0].fireDate == DateComponents(hour: 19, minute: 0, weekday: 4))
        #expect(w[1].fireDate == DateComponents(hour: 18, minute: 0, weekday: 1))
        // Weekday-only components: no year/month/day, or a repeating trigger
        // would match a single date.
        #expect(w.allSatisfy { $0.fireDate.year == nil && $0.fireDate.month == nil && $0.fireDate.day == nil })
        // Pin the numbering: weekday 4 is a Wednesday, 1 a Sunday.
        let wednesday = calendar.nextDate(after: morning, matching: w[0].fireDate, matchingPolicy: .strict)!
        let sunday = calendar.nextDate(after: morning, matching: w[1].fireDate, matchingPolicy: .strict)!
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: wednesday)
                == DateComponents(year: 2026, month: 7, day: 8, hour: 19))
        #expect(calendar.dateComponents([.year, .month, .day, .hour], from: sunday)
                == DateComponents(year: 2026, month: 7, day: 12, hour: 18))
    }

    @Test("Weekly nudge copy and poses")
    func weeklyBodies() {
        let w = ReminderPlanner.weeklyPlan()
        #expect(w[0].body == "This week's lesson is waiting — six minutes with Merc?")
        #expect(w[1].body == "New week, new lesson.")
        #expect(w[0].pose == .wave)
        #expect(w[1].pose == .happy)
    }

    @Test("With weekly nudges on, daily rotation skips Wednesdays and Sundays")
    func quietWeekdaysSkipRotation() {
        #expect(ReminderPlanner.weeklyWeekdays == [4, 1])
        // Monday 6 July → Sunday 19 July: the 8th, 12th, 15th and 19th yield.
        let p = ReminderPlanner.plan(now: morning, calendar: calendar, hour: 18, minute: 0,
                                     streak: 3, chattedToday: false,
                                     quietWeekdays: ReminderPlanner.weeklyWeekdays)
        #expect(p.map(\.fireDate.day) == [6, 7, 9, 10, 11, 13, 14, 16, 17, 18])
        #expect(p[0].body.contains("3-day streak"))
    }

    @Test("The streak-defense slot is never dropped, even on a weekly-nudge day")
    func quietWeekdayKeepsDefense() {
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 10))!
        let p = ReminderPlanner.plan(now: wednesday, calendar: calendar, hour: 18, minute: 0,
                                     streak: 6, chattedToday: false,
                                     quietWeekdays: ReminderPlanner.weeklyWeekdays)
        #expect(p[0].fireDate.day == 8)
        #expect(p[0].body.contains("6-day streak"))
        #expect(!p.dropFirst().contains { $0.fireDate.day == 12 || $0.fireDate.day == 15 })
    }

    @Test("Weekly ids live under their own prefix, disjoint from the daily one")
    func weeklyIds() {
        let w = ReminderPlanner.weeklyPlan()
        #expect(w.map(\.id) == ["mercurius.weekly.wed", "mercurius.weekly.sun"])
        #expect(w.allSatisfy { $0.id.hasPrefix(ReminderPlanner.weeklyIdPrefix) })
        // The daily refresh clears by `idPrefix` — it must never match a weekly id…
        #expect(w.allSatisfy { !$0.id.hasPrefix(ReminderPlanner.idPrefix) })
        // …and weekly clearing must never match a daily id.
        #expect(plan(streak: 2).allSatisfy { !$0.id.hasPrefix(ReminderPlanner.weeklyIdPrefix) })
    }
}
