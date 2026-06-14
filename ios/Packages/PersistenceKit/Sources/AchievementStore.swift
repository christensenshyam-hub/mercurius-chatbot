import Foundation
import Observation

/// Tracks which achievements the student has earned. Client-side only (mirrors
/// the web widget's localStorage model) — there's no server endpoint for these.
///
/// `award(_:)` is idempotent and returns `true` **only on first earn**, which the
/// UI uses to decide whether to pop the "Achievement unlocked" toast. `@Observable`
/// so the gallery updates live; `UserDefaults`-backed (injectable for tests).
@MainActor
@Observable
public final class AchievementStore {
    /// The set of earned achievement ids.
    public private(set) var earned: Set<String>

    /// The achievement most recently *newly* earned, for a one-time toast. The
    /// presenter (app shell) observes this and calls `clearLastEarned()` after
    /// showing it.
    public private(set) var lastEarned: Achievement?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "engagement.achievements.earned"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.earned = Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Earn an achievement. Returns `true` only if it was newly earned (so the
    /// caller can show a one-time toast); `false` if already held or unknown id.
    @discardableResult
    public func award(_ id: String) -> Bool {
        guard AchievementCatalog.achievement(id: id) != nil else { return false }
        guard !earned.contains(id) else { return false }
        earned.insert(id)
        defaults.set(Array(earned), forKey: key)
        lastEarned = AchievementCatalog.achievement(id: id)
        return true
    }

    /// Clear the transient "just earned" marker once its toast has shown.
    public func clearLastEarned() { lastEarned = nil }

    public func has(_ id: String) -> Bool { earned.contains(id) }

    public var earnedCount: Int { earned.count }

    /// Clear all earned achievements (used by "Start Over").
    public func reset() {
        earned = []
        defaults.removeObject(forKey: key)
    }
}
