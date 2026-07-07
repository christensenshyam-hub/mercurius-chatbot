import Foundation

/// Plans the next week of daily-reminder notifications: rotating Merc-voiced
/// copy, with the FIRST upcoming slot upgraded to a streak-defense line when
/// there's a live streak to protect.
///
/// Why one-off notifications instead of the old repeating trigger: a repeating
/// `UNCalendarNotificationTrigger` can only ever say the same sentence, and it
/// can't know about the streak. Planning a rolling window (re-planned on every
/// launch / foreground / streak change) lets the copy rotate, lets the streak
/// number stay accurate (any streak change re-plans before the number could go
/// stale), and means a user who stops opening the app stops being pinged after
/// the window runs out — deliberate: no infinite nagging in a 9+ app.
///
/// Pure — every input is explicit — so rotation and defense selection are
/// unit-testable without touching `UNUserNotificationCenter`.
public enum ReminderPlanner {

    public struct PlannedReminder: Equatable, Sendable {
        /// Stable per-day identifier ("mercurius.reminder.2026-07-06") so
        /// re-planning replaces rather than duplicates.
        public let id: String
        /// Local wall-clock fire time (year/month/day/hour/minute).
        public let fireDate: DateComponents
        public let body: String
    }

    /// Identifier prefix for every planned reminder — the scheduler uses it
    /// to find and clear previous plans.
    public static let idPrefix = "mercurius.reminder."

    /// The Merc-voiced rotation. Warm and inviting — this app's audience is
    /// 9+, so no Duo-style guilt, just personality.
    static let dailyLines = [
        "Merc here! Got two minutes to think together today?",
        "Curious about anything today? Merc loves a good question.",
        "Two minutes of thinking beats two hours of scrolling — Merc's ready.",
        "Merc's been pondering something. Come ask him about it!",
        "Your learning path misses you. One small step today?",
        "A question a day keeps your brain in play. Merc's waiting!",
        "Merc says hi 👋 — swing by for a quick brain workout.",
    ]

    static func defenseLine(streak: Int) -> String {
        "Your \(streak)-day streak is on the line! A two-minute chat with Merc saves it."
    }

    /// Build the plan.
    ///
    /// - Parameters:
    ///   - streak: the live, server-confirmed streak to defend, or `nil` when
    ///     there's nothing at risk (no streak, or the cache isn't fresh).
    ///   - chattedToday: today's slot is dropped when the user already chatted
    ///     (that day is saved — pinging them after the fact reads as noise),
    ///     and the defense line moves to the first future slot.
    public static func plan(
        now: Date,
        calendar: Calendar = .current,
        hour: Int,
        minute: Int,
        streak: Int?,
        chattedToday: Bool,
        horizonDays: Int = 7
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
            if defensePending, let streak {
                body = defenseLine(streak: streak)
                defensePending = false
            } else {
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: fire) ?? offset
                body = dailyLines[dayOfYear % dailyLines.count]
            }

            var comps = calendar.dateComponents([.year, .month, .day], from: fire)
            comps.hour = hour
            comps.minute = minute
            let key = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            reminders.append(PlannedReminder(id: idPrefix + key, fireDate: comps, body: body))
        }
        return reminders
    }
}
