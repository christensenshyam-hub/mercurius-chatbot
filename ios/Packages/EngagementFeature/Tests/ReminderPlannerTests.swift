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
        // 14 daily + every weekly nudge stays far under iOS's 64
        // pending-request cap.
        let weekly = ReminderPlanner.weeklyPlan(now: morning, calendar: calendar,
                                                week: self.week(done: 0))
        #expect(weekly.count <= 2 * ReminderPlanner.weeklyHorizonWeeks)
        #expect(plan(streak: 3).count + 2 * ReminderPlanner.weeklyHorizonWeeks <= 64)
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

        // A day a weekly nudge covers yields its rotation slot to the nudge.
        let quiet = ReminderPlanner.plan(now: day(6, hour: 12), calendar: calendar, hour: 18, minute: 0,
                                         streak: 4, streakDay: day(6), chattedToday: true,
                                         quietDays: ["2026-07-08"])
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

    // MARK: - Weekly nudges (AUD-36)

    /// The week containing `morning` (Monday 6 July 2026) starts Thursday
    /// 2 July: its Sunday nudge (5 July) is past, its Wednesday one (8 July)
    /// is ahead.
    private func week(done: Int, goal: Int = 2, start: Date? = nil) -> ReminderPlanner.WeekProgress {
        ReminderPlanner.WeekProgress(weekStart: start ?? day(2), done: done, goal: goal)
    }

    private func weekly(done: Int, goal: Int = 2, now: Date? = nil,
                        weeks: Int = ReminderPlanner.weeklyHorizonWeeks) -> [ReminderPlanner.PlannedReminder] {
        ReminderPlanner.weeklyPlan(now: now ?? morning, calendar: calendar,
                                   week: week(done: done, goal: goal), weeks: weeks)
    }

    private func ymd(_ r: ReminderPlanner.PlannedReminder) -> String {
        String(format: "%02d-%02d %02d:%02d", r.fireDate.month ?? 0, r.fireDate.day ?? 0,
               r.fireDate.hour ?? 0, r.fireDate.minute ?? 0)
    }

    @Test("The week starts Thursday 00:00, as WeeklyPlan counts it")
    func weekStartIsThursday() {
        #expect(ReminderPlanner.weekStart(containing: morning, calendar: calendar) == day(2))
        #expect(ReminderPlanner.weekStart(containing: day(9), calendar: calendar) == day(9))
        #expect(ReminderPlanner.weekStart(containing: day(8, hour: 23), calendar: calendar) == day(2))
        #expect(ReminderPlanner.weekStart(containing: day(12, hour: 18), calendar: calendar) == day(9))
    }

    @Test("Nothing done: Wednesday 19:00 and Sunday 18:00 nudges as dated one-offs, eight weeks out")
    func weeklyNothingDone() {
        let w = weekly(done: 0)
        // This week's Sunday (5 July) is past, so 1 + 7 × 2.
        #expect(w.count == 1 + 2 * (ReminderPlanner.weeklyHorizonWeeks - 1))
        #expect(w.prefix(4).map(ymd) == ["07-08 19:00", "07-12 18:00", "07-15 19:00", "07-19 18:00"])
        // Every fire date is a full local date, so the trigger fires once.
        #expect(w.allSatisfy { $0.fireDate.year == 2026 && $0.fireDate.month != nil && $0.fireDate.day != nil })
        #expect(w.allSatisfy { $0.fireDate.weekday == nil })
        // Sorted, date-keyed, unique.
        #expect(w.map(\.id) == w.map(\.id).sorted())
        #expect(Set(w.map(\.id)).count == w.count)
        #expect(w[0].id == "mercurius.weekly.2026-07-08")
        // Pin the weekdays: 8 July 2026 is a Wednesday, 12 July a Sunday.
        let wednesday = calendar.date(from: w[0].fireDate)!
        let sunday = calendar.date(from: w[1].fireDate)!
        #expect(calendar.component(.weekday, from: wednesday) == 4)
        #expect(calendar.component(.weekday, from: sunday) == 1)
    }

    @Test("Nothing done: the nudges ask, with their poses")
    func weeklyCopyNothingDone() {
        let w = weekly(done: 0)
        #expect(w[0].body == "This week's lesson is waiting — six minutes with Merc?")
        #expect(w[0].pose == .wave)
        #expect(w[1].body == "This week's first lesson is ready — six minutes with Merc?")
        #expect(w[1].pose == .happy)
    }

    @Test("One of two done: this week's Wednesday says one more; later weeks start over")
    func weeklyOneDone() {
        let w = weekly(done: 1)
        #expect(w[0].fireDate.day == 8)
        #expect(w[0].body == "One more lesson rounds out your week — six minutes with Merc?")
        #expect(w[1].body == "This week's first lesson is ready — six minutes with Merc?")
        #expect(w[2].body == "This week's lesson is waiting — six minutes with Merc?")

        // Seen from Thursday morning, both of this week's nudges are ahead.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9))!
        let fromThursday = weekly(done: 1, now: thursday)
        #expect(fromThursday.prefix(2).map(ymd) == ["07-05 18:00", "07-08 19:00"])
        #expect(fromThursday[0].body == "One lesson down this week. Ready for the next one with Merc?")
    }

    @Test("Goal met: no nudge this week — not \"This week's lesson is waiting\"")
    func weeklyGoalMet() {
        for done in [2, 3] {
            let w = weekly(done: done)
            #expect(!w.contains { $0.fireDate.day == 8 && $0.fireDate.month == 7 })
            // Next week (from Thursday 9 July) nudges again, from zero.
            #expect(w.first.map(ymd) == "07-12 18:00")
            #expect(w.count == 2 * (ReminderPlanner.weeklyHorizonWeeks - 1))
        }
        // The two finished on Thursday: Sunday's and Wednesday's both go.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 20))!
        #expect(weekly(done: 2, now: thursday).first.map(ymd) == "07-12 18:00")
    }

    @Test("A different goal is honoured: one of three is not met")
    func weeklyOtherGoal() {
        #expect(weekly(done: 2, goal: 3).first.map(ymd) == "07-08 19:00")
        #expect(weekly(done: 1, goal: 1).first.map(ymd) == "07-12 18:00")
    }

    @Test("No line ever calls Sunday a new week: Sunday is mid-week in a Thursday week")
    func sundayIsMidWeek() {
        let lines = [0, 1].flatMap { done in
            ReminderPlanner.weeklySlots.map { ReminderPlanner.weeklyLine(weekday: $0.weekday, done: done) }
        }
        #expect(lines.allSatisfy { !$0.localizedCaseInsensitiveContains("new week") })
        // Thursday 2 July + 3 days is the Sunday nudge, + 6 the Wednesday one.
        #expect(weekly(done: 0, now: day(2)).prefix(2).map(\.fireDate.day) == [5, 8])
    }

    @Test("Past slots are dropped; the horizon counts weeks from this one")
    func weeklyHorizonAndPast() {
        #expect(weekly(done: 0, weeks: 1).map(ymd) == ["07-08 19:00"])
        #expect(weekly(done: 0, weeks: 0).isEmpty)
        // After Wednesday's slot, nothing is left this week.
        let lateWednesday = day(8, hour: 20)
        #expect(weekly(done: 0, now: lateWednesday, weeks: 1).isEmpty)
    }

    @Test("Local wall-clock times hold across a DST change")
    func weeklyAcrossDST() {
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        // Thursday 29 October 2026; DST ends Sunday 1 November.
        let now = chicago.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 9))!
        let start = ReminderPlanner.weekStart(containing: now, calendar: chicago)
        let w = ReminderPlanner.weeklyPlan(
            now: now, calendar: chicago,
            week: ReminderPlanner.WeekProgress(weekStart: start, done: 0, goal: 2), weeks: 2)
        #expect(w.map(ymd) == ["11-01 18:00", "11-04 19:00", "11-08 18:00", "11-11 19:00"])
        for reminder in w {
            let fire = chicago.date(from: reminder.fireDate)!
            #expect(chicago.component(.hour, from: fire) == reminder.fireDate.hour)
        }
    }

    @Test("WeekProgress clamps nonsense and has a nothing-known default")
    func weekProgressValues() {
        let odd = ReminderPlanner.WeekProgress(weekStart: day(2), done: -3, goal: 0)
        #expect(odd.done == 0)
        #expect(odd.goal == 1)
        #expect(!odd.goalMet)
        let unknown = ReminderPlanner.WeekProgress.unknown(now: morning, calendar: calendar)
        #expect(unknown.weekStart == day(2))
        #expect(unknown.done == 0)
        #expect(unknown.goal == ReminderPlanner.defaultWeeklyGoal)
        #expect(ReminderPlanner.defaultWeeklyGoal == 2)
    }

    // MARK: - Both families

    private var dailyOn: ReminderPlanner.DailySettings {
        // A streak confirmed Monday the 6th: Tuesday and Wednesday can save it.
        ReminderPlanner.DailySettings(hour: 18, minute: 0, streak: 4, streakDay: day(6), chattedToday: true)
    }

    @Test("A day with a weekly nudge drops its daily rotation slot")
    func scheduleQuietsNudgeDays() {
        let all = ReminderPlanner.schedule(now: day(6, hour: 12), calendar: calendar,
                                           daily: dailyOn, week: week(done: 0))
        let daily = all.filter { $0.id.hasPrefix(ReminderPlanner.idPrefix) }
        let weekly = all.filter { $0.id.hasPrefix(ReminderPlanner.weeklyIdPrefix) }
        #expect(daily.map(\.fireDate.day) == [7])
        #expect(daily[0].body.contains("4-day streak"))
        #expect(weekly.first.map(ymd) == "07-08 19:00")
    }

    @Test("The streak-defense slot is never dropped, even on a weekly-nudge day")
    func quietDayKeepsDefense() {
        let p = ReminderPlanner.plan(now: day(8, hour: 10), calendar: calendar, hour: 18, minute: 0,
                                     streak: 6, chattedToday: false,
                                     quietDays: ["2026-07-08", "2026-07-12"])
        #expect(p[0].fireDate.day == 8)
        #expect(p[0].body.contains("6-day streak"))
        #expect(!p.dropFirst().contains { $0.fireDate.day == 12 })
        #expect(p.dropFirst().contains { $0.fireDate.day == 9 })
    }

    @Test("A goal met this week brings Wednesday's daily slot back")
    func scheduleGoalMetKeepsDaily() {
        let all = ReminderPlanner.schedule(now: day(6, hour: 12), calendar: calendar,
                                           daily: dailyOn, week: week(done: 2))
        let daily = all.filter { $0.id.hasPrefix(ReminderPlanner.idPrefix) }
        #expect(daily.map(\.fireDate.day) == [7, 8])
        #expect(!all.contains { $0.id == "mercurius.weekly.2026-07-08" })
    }

    @Test("Weekly off: daily only, no quiet days; daily off: weekly only")
    func scheduleEachFamilyAlone() {
        let dailyOnly = ReminderPlanner.schedule(now: day(6, hour: 12), calendar: calendar,
                                                 daily: dailyOn, week: nil)
        #expect(dailyOnly.map(\.fireDate.day) == [7, 8])
        let weeklyOnly = ReminderPlanner.schedule(now: morning, calendar: calendar,
                                                  daily: nil, week: week(done: 0))
        #expect(weeklyOnly == weekly(done: 0))
        #expect(ReminderPlanner.schedule(now: morning, calendar: calendar, daily: nil, week: nil).isEmpty)
    }

    @Test("Weekly ids live under their own prefix, which also clears the old repeating pair")
    func weeklyIds() {
        let w = weekly(done: 0)
        #expect(w.allSatisfy { $0.id.hasPrefix(ReminderPlanner.weeklyIdPrefix) })
        // The daily family clears by `idPrefix` — it must never match a weekly id…
        #expect(w.allSatisfy { !$0.id.hasPrefix(ReminderPlanner.idPrefix) })
        // …and weekly clearing must never match a daily id.
        #expect(plan(streak: 2).allSatisfy { !$0.id.hasPrefix(ReminderPlanner.weeklyIdPrefix) })
        // Builds before AUD-36 left two repeating requests behind; clearing
        // by the weekly prefix removes them on the first re-plan.
        for legacy in ["mercurius.weekly.wed", "mercurius.weekly.sun"] {
            #expect(legacy.hasPrefix(ReminderPlanner.weeklyIdPrefix))
        }
    }
}
