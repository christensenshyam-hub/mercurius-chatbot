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

    /// Newly earned achievements whose toast hasn't shown yet, oldest first.
    /// A single "last earned" slot would lose toasts when two achievements land
    /// in the same tick (e.g. streak 3 + streak 7 newly awarded together after
    /// a reinstall) — the queue shows each in turn instead.
    public private(set) var pendingToasts: [Achievement] = []

    /// The achievement whose toast should show now (head of the queue). The
    /// presenter observes this and calls `clearLastEarned(_:)` after showing it,
    /// which reveals the next queued achievement, if any.
    public var lastEarned: Achievement? { pendingToasts.first }

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
        guard let achievement = AchievementCatalog.achievement(id: id) else { return false }
        guard !earned.contains(id) else { return false }
        earned.insert(id)
        defaults.set(Array(earned), forKey: key)
        pendingToasts.append(achievement)
        return true
    }

    /// Dequeue `achievement`'s toast once it has shown. Head-guarded: the
    /// presenter is attached to more than one presentation layer (shell +
    /// full-screen covers), so a duplicate clear for the same achievement must
    /// be a no-op rather than also swallowing the next queued toast.
    public func clearLastEarned(_ achievement: Achievement) {
        guard pendingToasts.first?.id == achievement.id else { return }
        pendingToasts.removeFirst()
    }

    public func has(_ id: String) -> Bool { earned.contains(id) }

    public var earnedCount: Int { earned.count }

    /// Clear all earned achievements (used by "Start Over").
    public func reset() {
        earned = []
        pendingToasts = []
        defaults.removeObject(forKey: key)
    }
}
