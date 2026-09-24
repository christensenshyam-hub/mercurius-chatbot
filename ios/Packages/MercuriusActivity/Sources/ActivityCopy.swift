#if os(iOS)
import SwiftUI

/// Copy shared by the lock card and the Dynamic Island expanded body. Each
/// surface passes the phase it actually renders (system-stale folded in).
extension LearningActivityAttributes.ContentState {
    /// The unit the activity tracks. Stored as `level` (unit + 1): the
    /// Codable keys predate the unit wording, and ActivityKit must still
    /// decode activities started by earlier builds, so it is derived here.
    var unitNumber: Int { level - 1 }

    func headline(for phase: Phase) -> String {
        switch phase {
        case .active:    return "On a roll"
        case .completed: return "Streak banked"
        case .stale:     return "Still there?"
        case .error:     return "Can't sync"
        }
    }

    func progressLine(for phase: Phase) -> String {
        switch phase {
        case .active, .completed: return "\(lessonsDone) of \(lessonsTotal) done"
        case .stale:              return "Paused · \(lessonsDone) of \(lessonsTotal) done"
        case .error:              return "We'll retry automatically"
        }
    }

    /// The countdown is the ONLY live value — a system timer from
    /// `deadline`, never a pre-formatted string. Hidden when stale.
    /// `compact` is the lock card's short form, so the countdown isn't
    /// truncated off its narrow text column.
    func metaLine(for phase: Phase, compact: Bool = false) -> Text {
        switch phase {
        case .active:
            let phrase = ActivityMetaCopy.lessonsLeftPhrase(
                lessonsLeft: lessonsToLevel, unitNumber: unitNumber, compact: compact)
            return Text(phrase + ActivityMetaCopy.separator)
                + Text(timerInterval: countdownRange, countsDown: true)
                + Text(ActivityMetaCopy.countdownSuffix)
        case .completed:
            return Text(unitNumber > 0 ? "Unit \(unitNumber) complete" : "All lessons done")
        case .stale:
            return Text("Updated ") + Text(lastUpdated, style: .relative) + Text(" ago")
        case .error:
            return Text("Check your connection")
        }
    }
}
#endif
