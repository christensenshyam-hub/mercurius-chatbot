import Foundation

/// Plans the reminder notifications:
///
/// - **Daily** — the next two weeks of one-off reminders: rotating Merc-voiced
///   copy, with the FIRST upcoming slot upgraded to a streak-defense line when
///   there's a live streak to protect. A repeating trigger can only ever say
///   the same sentence and can't know about the streak; planning a rolling
///   window (re-planned on every launch / foreground / streak change) lets the
///   copy rotate, keeps the streak number accurate, and means a user who stops
///   opening the app stops getting daily pings once the window runs out.
/// - **Weekly** — two fixed nudges (Wednesday evening, Sunday evening) on
///   repeating triggers. They keep going while the user is away — that's their
///   job — so they're capped at two a week and turned off with one switch.
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
        /// "mercurius.weekly.wed") so re-planning replaces rather than
        /// duplicates.
        public let id: String
        /// Local wall-clock fire time: year/month/day/hour/minute for a daily
        /// reminder, weekday/hour/minute for a weekly one.
        public let fireDate: DateComponents
        public let body: String
        public let pose: Pose
    }

    /// Identifier prefix for every planned daily reminder — the scheduler
    /// uses it to find and clear previous plans.
    public static let idPrefix = "mercurius.reminder."

    /// Identifier prefix for the weekly nudges. Disjoint from `idPrefix`, so
    /// clearing one family never touches the other.
    public static let weeklyIdPrefix = "mercurius.weekly."

    /// The two weekly nudges, fired on repeating calendar triggers. Weekdays
    /// use Gregorian numbering (1 = Sunday … 7 = Saturday); pass
    /// `weeklyWeekdays` as `plan(quietWeekdays:)` while they're on.
    public static func weeklyPlan() -> [PlannedReminder] {
        [
            PlannedReminder(
                id: weeklyIdPrefix + "wed",
                fireDate: DateComponents(hour: 19, minute: 0, weekday: 4),
                body: "This week's lesson is waiting — six minutes with Merc?",
                pose: .wave
            ),
            PlannedReminder(
                id: weeklyIdPrefix + "sun",
                fireDate: DateComponents(hour: 18, minute: 0, weekday: 1),
                body: "New week, new lesson.",
                pose: .happy
            ),
        ]
    }

    /// The weekdays the weekly nudges fire on.
    public static var weeklyWeekdays: Set<Int> {
        Set(weeklyPlan().compactMap(\.fireDate.weekday))
    }

    /// The Merc-voiced rotation, each line paired with the pose Merc strikes
    /// on the banner. Warm and inviting — this app's audience is 9+, so no
    /// Duo-style guilt, just personality.
    static let dailyLines: [(body: String, pose: Pose)] = [
        ("Merc here! Got two minutes to think together today?", .wave),
        ("Curious about anything today? Merc loves a good question.", .thinking),
        ("Two minutes of thinking beats two hours of scrolling — Merc's ready.", .happy),
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

    /// Build the daily plan.
    ///
    /// - Parameters:
    ///   - streak: the live, server-confirmed streak to defend, or `nil` when
    ///     there's nothing at risk (no streak, or the cache isn't fresh).
    ///   - chattedToday: today's slot is dropped when the user already chatted
    ///     (that day is saved — pinging them after the fact reads as noise),
    ///     and the defense line moves to the first future slot.
    ///   - quietWeekdays: Gregorian weekdays (1 = Sunday) a weekly nudge
    ///     already covers; their rotation slots are dropped so the day gets
    ///     one notification, not two. The defense slot is never dropped.
    public static func plan(
        now: Date,
        calendar: Calendar = .current,
        hour: Int,
        minute: Int,
        streak: Int?,
        chattedToday: Bool,
        horizonDays: Int = 14,
        quietWeekdays: Set<Int> = []
    ) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        var defensePending = streak != nil

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }

            // Today's slot only exists if its time hasn't passed and the user
            // hasn't already saved the day.
            if offset == 0, (fire <= now || chattedToday) { continue }

            let body: String
            let pose: Pose
            if defensePending, let streak {
                body = defenseLine(streak: streak)
                pose = .sleep
                defensePending = false
            } else if quietWeekdays.contains(calendar.component(.weekday, from: fire)) {
                continue
            } else {
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: fire) ?? offset
                (body, pose) = dailyLines[dayOfYear % dailyLines.count]
            }

            var comps = calendar.dateComponents([.year, .month, .day], from: fire)
            comps.hour = hour
            comps.minute = minute
            let key = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            reminders.append(PlannedReminder(id: idPrefix + key, fireDate: comps, body: body, pose: pose))
        }
        return reminders
    }
}
