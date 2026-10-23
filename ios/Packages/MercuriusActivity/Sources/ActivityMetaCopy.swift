import Foundation

/// The Live Activity's words, as plain strings. Outside the iOS-only guard so
/// the copy and the lock card's length budget are tested on the macOS host.
///
/// AUD-37: the activity used to read "On a roll · 4 to go · 15:29:59 left" on
/// a student's very first lesson — a countdown to midnight next to the
/// lessons left in the unit, which reads as "finish the unit today" against
/// the club's two-lessons-a-week pace. Now the active card shows the weekly
/// frame ("This week · 0 of 2") and a countdown only when a live streak
/// really ends tonight, labelled as such ("Streak ends in 4:59:59").
enum ActivityMetaCopy {
    static let separator = " · "

    /// Prefix of the one countdown the active card may show, followed by the
    /// system timer. Only when `streakAtRisk`.
    static let streakCountdownPrefix = "Streak ends in "

    /// The active headline: neutral until something is done this week.
    /// Activities started by builds before AUD-37 carry no week, so they
    /// fall back to the unit's count.
    static func activeHeadline(weekDone: Int?, lessonsDone: Int) -> String {
        (weekDone ?? lessonsDone) > 0 ? "On a roll" : "In a lesson"
    }

    /// The active second line: the unit and its lessons done
    /// ("Unit 1 · 0 of 4 done"), since the meta line no longer names it.
    static func activeProgressPhrase(lessonsDone: Int, lessonsTotal: Int, unitNumber: Int) -> String {
        let count = "\(max(lessonsDone, 0)) of \(max(lessonsTotal, 0)) done"
        return unitNumber > 0 ? "Unit \(unitNumber)" + separator + count : count
    }

    /// What the active meta line shows.
    enum ActiveMeta: Equatable {
        /// `prefix`, then the system countdown to the activity's deadline.
        case countdown(prefix: String)
        case text(String)
    }

    /// The active meta line. `compact` is the lock card's short form; the
    /// Dynamic Island has room for a few more words.
    static func activeMeta(
        weekDone: Int?,
        weekGoal: Int?,
        streakAtRisk: Bool,
        lessonsLeft: Int,
        unitNumber: Int,
        compact: Bool
    ) -> ActiveMeta {
        if streakAtRisk {
            return .countdown(prefix: streakCountdownPrefix)
        }
        if let weekDone, let weekGoal {
            return .text(weekPhrase(done: weekDone, goal: weekGoal, compact: compact))
        }
        // An activity from an older build: no week known, and no countdown.
        return .text(lessonsLeftPhrase(lessonsLeft: lessonsLeft, unitNumber: unitNumber, compact: compact))
    }

    /// "This week · 1 of 2" (the island: "… of 2 lessons"). Past the goal it
    /// counts lessons instead of reading "3 of 2", as Home does.
    static func weekPhrase(done: Int, goal: Int, compact: Bool) -> String {
        let done = max(done, 0)
        let goal = max(goal, 1)
        if done > goal {
            return "This week" + separator + "\(done) lessons"
        }
        return "This week" + separator + "\(done) of \(goal)" + (compact ? "" : " lessons")
    }

    /// The lessons left in the unit — the meta line of activities started
    /// before AUD-37, which carry no week. The Dynamic Island has room for
    /// the unit ("2 lessons left in Unit 6"); the lock card (`compact`) keeps
    /// only the count ("2 to go").
    static func lessonsLeftPhrase(lessonsLeft: Int, unitNumber: Int, compact: Bool) -> String {
        let left = max(lessonsLeft, 0)
        if compact {
            // Zero left: replaying a lesson in a unit that's already finished.
            return left == 0 ? "All done" : "\(left) to go"
        }
        let unit = unitNumber > 0 ? "Unit \(unitNumber)" : nil
        if left == 0 {
            return unit.map { "\($0) complete" } ?? "All lessons done"
        }
        let count = left == 1 ? "1 lesson left" : "\(left) lessons left"
        return unit.map { "\(count) in \($0)" } ?? count
    }
}
