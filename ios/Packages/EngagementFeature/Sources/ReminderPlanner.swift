import Foundation

/// Plans the reminder notifications:
///
/// - **Daily** — one-off reminders through the last day a chat can still save
///   the streak: rotating Merc-voiced copy, with the FIRST upcoming slot
///   upgraded to a streak-defense line. A repeating trigger can only ever say
///   the same sentence and can't know about the streak; planning a short
///   window (re-planned on every launch / foreground / streak change) lets the
///   copy rotate, keeps the streak number accurate, and means the pings stop
///   when the streak lapses even if the app is never opened again.
/// - **Weekly** — two nudges a week (Sunday evening, Wednesday evening),
///   planned as one-off dated reminders for the app's Thursday-to-Wednesday
///   week and the weeks after it, re-planned on every refresh. A week whose
///   lesson goal is already met gets none: a student who is on pace isn't
///   nagged (AUD-36). They keep going for a while when the student is away —
///   that's their job — capped at two a week for `weeklyHorizonWeeks` weeks
///   past the last re-plan, and turned off with one switch.
///
/// Pure — every input is explicit — so rotation and defense selection are
/// unit-testable without touching `UNUserNotificationCenter`.
public enum ReminderPlanner {

    /// Which Merc appears on the banner — rendered from the procedural art at
    /// schedule time, so every notification carries a matching pose (a wave
    /// for hellos, a pondering Merc for questions, a dozing Merc when the
    /// streak is about to fall asleep).
    public enum Pose: String, Sendable, CaseIterable {
        case wave, happy, thinking, celebrate, sleep
    }

    public struct PlannedReminder: Equatable, Sendable {
        /// Stable identifier ("mercurius.reminder.2026-07-06",
        /// "mercurius.weekly.2026-07-08") so re-planning replaces rather than
        /// duplicates.
        public let id: String
        /// Local wall-clock fire time: year/month/day/hour/minute.
        public let fireDate: DateComponents
        public let body: String
        public let pose: Pose
    }

    /// Identifier prefix for every planned daily reminder — the scheduler
    /// uses it to find and clear previous plans.
    public static let idPrefix = "mercurius.reminder."

    /// Identifier prefix for the weekly nudges. Disjoint from `idPrefix`, so
    /// clearing one family never touches the other. Builds before AUD-36
    /// scheduled two repeating requests under it ("mercurius.weekly.wed" and
    /// "….sun"); the scheduler's clear-by-prefix removes them on upgrade.
    public static let weeklyIdPrefix = "mercurius.weekly."

    // MARK: - Weekly nudges

    /// This week's lessons against the weekly goal. Built by the composition
    /// root from the curriculum's `WeeklyPlan` (EngagementFeature can't see
    /// the curriculum).
    public struct WeekProgress: Equatable, Sendable {
        /// Thursday 00:00 local: the start of the week `done` counts.
        public let weekStart: Date
        /// Lessons first completed this week.
        public let done: Int
        public let goal: Int

        public init(weekStart: Date, done: Int, goal: Int) {
            self.weekStart = weekStart
            self.done = max(done, 0)
            self.goal = max(goal, 1)
        }

        public var goalMet: Bool { done >= goal }

        /// Nothing known about this week: nothing done, the default goal.
        public static func unknown(now: Date, calendar: Calendar = .current) -> WeekProgress {
            WeekProgress(weekStart: ReminderPlanner.weekStart(containing: now, calendar: calendar),
                         done: 0, goal: defaultWeeklyGoal)
        }
    }

    /// The lessons-a-week goal (the curriculum's `WeeklyPlan` default).
    public static let defaultWeeklyGoal = 2

    /// How many weeks of nudges one plan covers, starting with this one.
    /// Every launch and foreground re-plans, so a student who opens the app
    /// keeps a full window; one who stops hears nothing after this many
    /// weeks (16 nudges at most).
    public static let weeklyHorizonWeeks = 8

    /// Gregorian weekday the app's week starts on (Thursday, as `WeeklyPlan`).
    static let weekStartWeekday = 5

    /// The most recent Thursday 00:00 (local to `calendar`) at or before
    /// `date` — the same week `WeeklyPlan` counts.
    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let daysBack = (weekday - weekStartWeekday + 7) % 7
        let thursday = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        return calendar.startOfDay(for: thursday)
    }

    /// One of the two weekly slots.
    struct WeeklySlot: Sendable {
        /// Gregorian weekday (1 = Sunday … 7 = Saturday).
        let weekday: Int
        let hour: Int
        let minute: Int
        let pose: Pose
    }

    /// Sunday evening (the middle of the app's week) and Wednesday evening
    /// (its last day).
    static let sundaySlot = WeeklySlot(weekday: 1, hour: 18, minute: 0, pose: .happy)
    static let wednesdaySlot = WeeklySlot(weekday: 4, hour: 19, minute: 0, pose: .wave)
    static let weeklySlots = [sundaySlot, wednesdaySlot]

    /// What a weekly nudge says, given how many of the week's lessons are
    /// done. Sunday is the middle of the Thursday week, never "a new week".
    /// Only used while the week's goal isn't met.
    static func weeklyLine(weekday: Int, done: Int) -> String {
        switch (weekday == wednesdaySlot.weekday, done > 0) {
        case (true, false):  return "This week's lesson is waiting — six minutes with Merc?"
        case (true, true):   return "One more lesson rounds out your week — six minutes with Merc?"
        case (false, false): return "This week's first lesson is ready — six minutes with Merc?"
        case (false, true):  return "One lesson down this week. Ready for the next one with Merc?"
        }
    }

    /// The weekly nudges from `now` on: two a week for `weeks` weeks starting
    /// with `week`'s, as one-off dated reminders. The current week's count
    /// picks its copy, and a met goal drops its nudges; later weeks start at
    /// zero. Slots already past are dropped.
    public static func weeklyPlan(
        now: Date,
        calendar: Calendar = .current,
        week: WeekProgress,
        weeks: Int = weeklyHorizonWeeks
    ) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        let startWeekday = calendar.component(.weekday, from: week.weekStart)
        for offset in 0..<max(weeks, 0) {
            let done = offset == 0 ? week.done : 0
            if done >= week.goal { continue }
            guard let start = calendar.date(byAdding: .day, value: 7 * offset, to: week.weekStart) else { continue }
            for slot in weeklySlots {
                let daysIn = (slot.weekday - startWeekday + 7) % 7
                guard let day = calendar.date(byAdding: .day, value: daysIn, to: start),
                      let fire = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day),
                      fire > now
                else { continue }
                var comps = calendar.dateComponents([.year, .month, .day], from: fire)
                comps.hour = slot.hour
                comps.minute = slot.minute
                reminders.append(PlannedReminder(
                    id: weeklyIdPrefix + dayKey(comps),
                    fireDate: comps,
                    body: weeklyLine(weekday: slot.weekday, done: done),
                    pose: slot.pose
                ))
            }
        }
        return reminders.sorted { dayKey($0.fireDate) < dayKey($1.fireDate) }
    }

    // MARK: - Both families

    /// The daily reminder's inputs, present only while it's on and there's a
    /// live streak to defend.
    public struct DailySettings: Equatable, Sendable {
        public let hour: Int
        public let minute: Int
        public let streak: Int
        public let streakDay: Date
        public let chattedToday: Bool

        public init(hour: Int, minute: Int, streak: Int, streakDay: Date, chattedToday: Bool) {
            self.hour = hour
            self.minute = minute
            self.streak = streak
            self.streakDay = streakDay
            self.chattedToday = chattedToday
        }
    }

    /// Everything one re-plan adds: the daily plan (when `daily` is set) and
    /// the weekly nudges (when `week` is set, i.e. the weekly switch is on).
    /// A day that gets a weekly nudge drops its daily rotation slot, so it
    /// carries one notification, not two; a weekly nudge skipped because the
    /// goal is met leaves that day's daily slot alone.
    public static func schedule(
        now: Date,
        calendar: Calendar = .current,
        daily: DailySettings?,
        week: WeekProgress?
    ) -> [PlannedReminder] {
        let weekly = week.map { weeklyPlan(now: now, calendar: calendar, week: $0) } ?? []
        let quietDays = Set(weekly.map { dayKey($0.fireDate) })
        let dailyPlan = daily.map {
            plan(now: now, calendar: calendar, hour: $0.hour, minute: $0.minute,
                 streak: $0.streak, streakDay: $0.streakDay, chattedToday: $0.chattedToday,
                 quietDays: quietDays)
        } ?? []
        return dailyPlan + weekly
    }

    /// "2026-07-06" for a fire date's day.
    static func dayKey(_ comps: DateComponents) -> String {
        String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// The Merc-voiced rotation, each line paired with the pose Merc strikes
    /// on the banner. Warm and inviting — no Duo-style guilt, and no
    /// lecturing about how students spend the rest of their time (AUD-44
    /// dropped a line about scrolling).
    static let dailyLines: [(body: String, pose: Pose)] = [
        ("Merc here! Got two minutes to think together today?", .wave),
        ("Curious about anything today? Merc loves a good question.", .thinking),
        ("Merc's been pondering something. Come ask him about it!", .thinking),
        ("Your learning path misses you. One small step today?", .happy),
        ("A question a day keeps your brain in play. Merc's waiting!", .celebrate),
        ("Merc says hi 👋 — swing by for a quick brain workout.", .wave),
    ]

    /// Defense pairs the urgency copy with a DOZING Merc — the streak is
    /// literally about to fall asleep.
    static func defenseLine(streak: Int) -> String {
        "Your \(streak)-day streak is on the line! A two-minute chat with Merc saves it."
    }

    /// The server keeps a streak through one missed day: a chat up to two
    /// days after the last one continues it (`diffDays <= 2` in
    /// `db.updateStreak`).
    static let streakGraceDays = 2

    /// How many days, starting today, the daily reminders may cover: through
    /// the last day a chat still saves the streak confirmed on `streakDay`.
    /// 0 once that day has passed.
    /// Counted in local days, assuming they match the server's STREAK_TZ
    /// days; a streak expiry sent by the server is the real fix.
    public static func dailyHorizon(now: Date, streakDay: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let lastSaveDay = calendar.date(byAdding: .day, value: streakGraceDays,
                                              to: calendar.startOfDay(for: streakDay)),
              let days = calendar.dateComponents([.day], from: today, to: lastSaveDay).day
        else { return 0 }
        return max(days + 1, 0)
    }

    /// Build the daily plan.
    ///
    /// - Parameters:
    ///   - streak: the live, server-confirmed streak to defend, or `nil` when
    ///     there's nothing at risk (no streak, or the cache isn't fresh).
    ///   - streakDay: the day that streak was last confirmed on. The plan ends
    ///     with the last day a chat can still save it (`dailyHorizon`), so a
    ///     lapsed streak gets no more pings. The scheduler always passes it.
    ///   - chattedToday: today's slot is dropped when the user already chatted
    ///     (that day is saved — pinging them after the fact reads as noise),
    ///     and the defense line moves to the first future slot.
    ///   - quietDays: days (`dayKey`, "2026-07-08") a weekly nudge already
    ///     covers; their rotation slots are dropped so the day gets one
    ///     notification, not two. The defense slot is never dropped.
    public static func plan(
        now: Date,
        calendar: Calendar = .current,
        hour: Int,
        minute: Int,
        streak: Int?,
        streakDay: Date? = nil,
        chattedToday: Bool,
        horizonDays: Int = 14,
        quietDays: Set<String> = []
    ) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        var defensePending = streak != nil
        let days = streakDay.map {
            min(horizonDays, dailyHorizon(now: now, streakDay: $0, calendar: calendar))
        } ?? horizonDays

        for offset in 0..<max(days, 0) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }

            // Today's slot only exists if its time hasn't passed and the user
            // hasn't already saved the day.
            if offset == 0, (fire <= now || chattedToday) { continue }

            var comps = calendar.dateComponents([.year, .month, .day], from: fire)
            comps.hour = hour
            comps.minute = minute
            let key = dayKey(comps)

            let body: String
            let pose: Pose
            if defensePending, let streak {
                body = defenseLine(streak: streak)
                pose = .sleep
                defensePending = false
            } else if quietDays.contains(key) {
                continue
            } else {
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: fire) ?? offset
                (body, pose) = dailyLines[dayOfYear % dailyLines.count]
            }

            reminders.append(PlannedReminder(id: idPrefix + key, fireDate: comps, body: body, pose: pose))
        }
        return reminders
    }
}
