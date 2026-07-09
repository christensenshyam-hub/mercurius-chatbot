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

        // Milestone (the NEXT level being worked toward)
        public var level: Int
        public var lessonsToLevel: Int

        // Time-sensitive completion window → rendered with a system timer.
        public var deadline: Date

        // For the stale state ("Updated 6m ago").
        public var lastUpdated: Date

        public init(
            phase: Phase,
            lessonsDone: Int,
            lessonsTotal: Int,
            progress: Double,
            streakCount: Int,
            level: Int,
            lessonsToLevel: Int,
            deadline: Date,
            lastUpdated: Date
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
        }
    }

    /// Static, per-activity (doesn't change over the session),
    /// e.g. "Unit 4 · Foundations".
    public var sessionTitle: String

    public init(sessionTitle: String) {
        self.sessionTitle = sessionTitle
    }
}
#endif
