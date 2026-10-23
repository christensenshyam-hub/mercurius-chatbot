import Foundation

/// This week's lesson plan: how many lessons are done this week against a
/// small goal, what's next on the path, and when the path would finish at
/// that pace. A pure value computed from the progress store — no storage.
///
/// Weeks start Thursday 00:00 local time, so the Wednesday evening nudge
/// lands on a week's last day.
///
/// It counts one course (`track`): the Deep dive by default, or Basics for
/// a learner who follows it, so the weekly nudge's goal and wording read
/// that course's lessons (a Basics lesson never counts toward the Deep
/// dive's week, nor the other way round).
public struct WeeklyPlan: Equatable, Sendable {
    /// Thursday 00:00 local, at or before `now`.
    public let weekStart: Date
    /// Lessons first completed in `[weekStart, weekStart + 7 days)`. Lessons
    /// with no recorded completion date never count.
    public let done: Int
    public let goal: Int
    /// Up to two upcoming stops, starting at the frontier.
    public let next: [MercuriusCurriculum.PathStop]
    /// `weekStart` plus one week per `goal` remaining lessons (rounded up);
    /// nil when every lesson is complete.
    public let projectedFinish: Date?

    public init(weekStart: Date, done: Int, goal: Int,
                next: [MercuriusCurriculum.PathStop], projectedFinish: Date?) {
        self.weekStart = weekStart
        self.done = done
        self.goal = goal
        self.next = next
        self.projectedFinish = projectedFinish
    }

    /// Gregorian weekday number for Thursday (Sunday = 1).
    static let weekStartWeekday = 5
    static let maxNextStops = 2

    @MainActor
    public static func compute(
        progress: CurriculumProgressStore,
        track: CurriculumTrack = .deepDive,
        now: Date = Date(),
        calendar: Calendar = .current,
        goal: Int = 2
    ) -> WeeklyPlan {
        let goal = max(goal, 1)
        let start = weekStart(containing: now, calendar: calendar)
        let end = addingWeeks(1, to: start, calendar: calendar)

        let lessonIds = Set(track.allLessons.map(\.id))
        let done = progress.completions(since: start).filter { id in
            guard lessonIds.contains(id), let at = progress.completedAt(id) else { return false }
            return at < end
        }.count

        let remaining = track.allLessons.count - progress.totalCompleted(in: track)
        let finish = remaining > 0
            ? addingWeeks((remaining + goal - 1) / goal, to: start, calendar: calendar)
            : nil

        let next = track == .basics
            ? upcomingBasicsStops(progress: progress)
            : upcomingStops(progress: progress)
        return WeeklyPlan(weekStart: start, done: done, goal: goal,
                          next: next, projectedFinish: finish)
    }

    /// The most recent Thursday 00:00 (local to `calendar`) at or before `date`.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let daysBack = (weekday - weekStartWeekday + 7) % 7
        let thursday = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        return calendar.startOfDay(for: thursday)
    }

    /// Calendar-day arithmetic, so a week that crosses a DST change still ends
    /// at local midnight rather than an hour off.
    private static func addingWeeks(_ weeks: Int, to date: Date, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .day, value: 7 * weeks, to: date)
            ?? date.addingTimeInterval(TimeInterval(7 * weeks) * 86_400)
        return calendar.startOfDay(for: shifted)
    }

    /// Basics: the next unfinished lessons from its frontier (it has no unit
    /// checks).
    @MainActor
    private static func upcomingBasicsStops(progress: CurriculumProgressStore) -> [MercuriusCurriculum.PathStop] {
        let lessons = CurriculumTrack.basics.allLessons
        guard case .lesson(let first)? = progress.frontier(in: .basics),
              let start = lessons.firstIndex(where: { $0.id == first.id })
        else { return [] }
        return lessons[start...]
            .filter { !progress.isCompleted($0.id) }
            .prefix(maxNextStops)
            .map { .lesson($0) }
    }

    /// Walk the path from the frontier, skipping completed lessons and
    /// mastered unit tests.
    @MainActor
    private static func upcomingStops(progress: CurriculumProgressStore) -> [MercuriusCurriculum.PathStop] {
        var stops: [MercuriusCurriculum.PathStop] = []
        var cursor = progress.frontier()
        while let stop = cursor, stops.count < maxNextStops {
            switch stop {
            case .lesson(let lesson):
                if !progress.isCompleted(lesson.id) { stops.append(stop) }
                cursor = MercuriusCurriculum.nextStop(after: lesson.id)
            case .unitTest(let unit):
                if !progress.isUnitMastered(unit.id) { stops.append(stop) }
                cursor = MercuriusCurriculum.nextStop(afterUnitTest: unit.id)
            }
        }
        return stops
    }
}
