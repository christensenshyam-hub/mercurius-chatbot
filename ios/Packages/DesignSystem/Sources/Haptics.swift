import SwiftUI

/// The named haptics for the lesson player and the learning path, on
/// SwiftUI's `.sensoryFeedback` (iPhone plays them; the Mac and the iPad,
/// which have no haptic engine for these, ignore them).
///
///     OptionRow(...)
///         .haptic(.selection, trigger: selectedOptionId)
public enum Haptic: Sendable, CaseIterable {
    /// Picking an option or a claim.
    case selection
    /// A correct answer; a lesson finished.
    case success
    /// A wrong answer the student can try again.
    case warning
    /// A light tap: a depth card opening, a button with weight.
    case lightImpact

    public var feedback: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .success: return .success
        case .warning: return .warning
        case .lightImpact: return .impact(weight: .light)
        }
    }
}

public extension View {
    /// Plays `haptic` each time `trigger` changes.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// Plays `haptic` when `trigger` changes and `condition(old, new)` holds,
    /// for example only when a check's result arrives, not when it clears.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
    }
}
