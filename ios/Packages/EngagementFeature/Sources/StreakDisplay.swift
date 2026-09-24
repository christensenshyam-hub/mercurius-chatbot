import Foundation

/// What the streak surfaces (header chip, learning-path bar, Progress hero)
/// show for a streak count. At zero there is no number: a "0" reads as a
/// failure before the student has started, so the flame stands alone with
/// an invitation instead.
struct StreakDisplay: Equatable {
    static let startMessage = "Start your streak today — one lesson does it"

    let count: Int

    init(count: Int) {
        self.count = max(0, count)
    }

    var isZero: Bool { count == 0 }

    /// The number to draw next to the flame; `nil` at zero.
    var countText: String? { isZero ? nil : "\(count)" }

    /// The streak sentence for VoiceOver labels.
    var spokenStreak: String {
        isZero ? "\(Self.startMessage)." : "Current streak: \(count) \(count == 1 ? "day" : "days")."
    }

    /// The Progress hero's line under the flame.
    var heroMessage: String {
        switch count {
        case 0: return Self.startMessage
        case 1: return "You're on the board. Come back tomorrow to keep it going."
        default: return "Keep it alive — one conversation a day."
        }
    }
}
