import Foundation
#if os(iOS)
import ActivityKit
#endif

/// The Live Activity's single source of truth (per the design handoff): one
/// attributes type, one `ContentState`. Every view is a pure function of this
/// state — no view computes or stores its own time.
#if os(iOS)
public struct LearningActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Drives which of the seven visual states renders. `stale` is
        /// normally system-derived (`context.isStale`), but exists as a
        /// phase so a server push can force it too.
        public enum Phase: String, Codable {
            case active, completed, stale, error
        }
        public var phase: Phase

        // Progress
        public var lessonsDone: Int
        public var lessonsTotal: Int
        /// 0…1 — lessonsDone/lessonsTotal, or finer-grained if available.
        public var progress: Double

        // Momentum
        public var streakCount: Int

        // Unit milestone: `level` is the tracked unit's number + 1 and
        // `lessonsToLevel` the lessons left in it. The names predate the
        // unit copy (see `unitNumber`) but are Codable keys ActivityKit
        // persists for running activities, so they stay.
        public var level: Int
        public var lessonsToLevel: Int

        // The end of the local day: the activity goes stale then, and it is
        // the countdown's target while `streakAtRisk`.
        public var deadline: Date

        // For the stale state ("Updated 6m ago").
        public var lastUpdated: Date

        // The weekly frame (AUD-37): lessons done this week against the
        // goal, and whether a live streak ends at `deadline` unless the
        // student chats today. Optional, so activities started by earlier
        // builds (which ActivityKit persists) still decode; without them the
        // card shows the unit's lessons left and no countdown.
        public var weekDone: Int?
        public var weekGoal: Int?
        public var streakAtRisk: Bool?

        public init(
            phase: Phase,
            lessonsDone: Int,
            lessonsTotal: Int,
            progress: Double,
            streakCount: Int,
            level: Int,
            lessonsToLevel: Int,
            deadline: Date,
            lastUpdated: Date,
            weekDone: Int? = nil,
            weekGoal: Int? = nil,
            streakAtRisk: Bool? = nil
        ) {
            self.phase = phase
            self.lessonsDone = lessonsDone
            self.lessonsTotal = lessonsTotal
            self.progress = progress
            self.streakCount = streakCount
            self.level = level
            self.lessonsToLevel = lessonsToLevel
            self.deadline = deadline
            self.lastUpdated = lastUpdated
            self.weekDone = weekDone
            self.weekGoal = weekGoal
            self.streakAtRisk = streakAtRisk
        }
    }

    /// Static, per-activity (doesn't change over the session),
    /// e.g. "Unit 06 · Spotting AI: Deepfakes & Synthetic Media".
    public var sessionTitle: String

    public init(sessionTitle: String) {
        self.sessionTitle = sessionTitle
    }
}
#endif
