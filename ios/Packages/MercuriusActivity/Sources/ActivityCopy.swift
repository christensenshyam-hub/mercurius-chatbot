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
    func metaLine(for phase: Phase) -> Text {
        switch phase {
        case .active:
            return Text("\(lessonsLeftPhrase) · ")
                + Text(timerInterval: countdownRange, countsDown: true)
                + Text(" left")
        case .completed:
            return Text(unitNumber > 0 ? "Unit \(unitNumber) complete" : "All lessons done")
        case .stale:
            return Text("Updated ") + Text(lastUpdated, style: .relative) + Text(" ago")
        case .error:
            return Text("Check your connection")
        }
    }

    private var lessonsLeftPhrase: String {
        let left = max(lessonsToLevel, 0)
        let unit = unitNumber > 0 ? "Unit \(unitNumber)" : nil
        if left == 0 {
            // Replaying a lesson in a unit that's already finished.
            return unit.map { "\($0) complete" } ?? "All lessons done"
        }
        let count = left == 1 ? "1 lesson left" : "\(left) lessons left"
        return unit.map { "\(count) in \($0)" } ?? count
    }
}
#endif
