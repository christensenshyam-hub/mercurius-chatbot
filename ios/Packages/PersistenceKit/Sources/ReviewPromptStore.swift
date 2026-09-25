import Foundation
import Observation

/// Counts completed lessons for the App Store review prompt, which is asked
/// at most twice per device: after the 3rd and the 10th completed lesson.
///
/// Deliberately separate from curriculum progress: "Delete my data" resets
/// progress, but the prompt budget is per device and must not refill. Not
/// wired into any reset path for the same reason.
///
/// Every `recordCompletion()` re-reads `UserDefaults` rather than trusting
/// its in-memory copy, so two instances over the same defaults can never
/// both claim the same threshold.
@MainActor
@Observable
public final class ReviewPromptStore {
    /// Lessons completed on this device since the counter was introduced.
    public private(set) var completedLessons: Int

    /// The completion counts that earn a prompt.
    public static let promptThresholds: Set<Int> = [3, 10]

    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let completedLessons = "review.completedLessons"
        static let promptedCounts = "review.promptedCounts"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.completedLessons = defaults.integer(forKey: Key.completedLessons)
    }

    /// Record one completed lesson. Returns `true` exactly when the new count
    /// is a prompt threshold that hasn't been used yet — and marks it used,
    /// so the caller should ask for the review when this returns `true`.
    @discardableResult
    public func recordCompletion() -> Bool {
        let count = defaults.integer(forKey: Key.completedLessons) + 1
        completedLessons = count
        defaults.set(count, forKey: Key.completedLessons)

        var prompted = Set(defaults.array(forKey: Key.promptedCounts) as? [Int] ?? [])
        guard Self.promptThresholds.contains(count), !prompted.contains(count) else { return false }
        prompted.insert(count)
        defaults.set(prompted.sorted(), forKey: Key.promptedCounts)
        return true
    }
}
