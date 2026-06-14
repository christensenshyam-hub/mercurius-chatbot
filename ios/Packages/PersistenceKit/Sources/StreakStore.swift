import Foundation
import Observation

/// Holds the student's current learning streak for display.
///
/// The streak itself is **computed server-side** (`db.updateStreak`): it counts
/// consecutive days with at least one chat, with a one-day grace gap. The server
/// returns the authoritative value on every chat `complete` event and from
/// `GET /api/session/:id`. This store just caches the latest value so the UI can
/// show it instantly (including before the first chat of a session) and tracks
/// the personal best.
///
/// `@Observable` so the header chip and Progress screen update reactively; cached
/// in `UserDefaults` (injectable for tests). Main-actor isolated to match the
/// other stores and because it's read/written from view models on the main actor.
@MainActor
@Observable
public final class StreakStore {
    /// Latest server-reported streak. `0` means "no streak yet" (fresh install,
    /// before the first chat or session fetch).
    public private(set) var current: Int
    /// Highest streak this device has ever seen.
    public private(set) var best: Int

    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let current = "engagement.streak.current"
        static let best = "engagement.streak.best"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = defaults.integer(forKey: Key.current)
        self.best = defaults.integer(forKey: Key.best)
    }

    /// Record the latest authoritative streak from the server. No-op for
    /// non-positive values (the server's minimum is 1).
    public func update(streak: Int) {
        guard streak > 0 else { return }
        current = streak
        defaults.set(current, forKey: Key.current)
        if streak > best {
            best = streak
            defaults.set(best, forKey: Key.best)
        }
    }

    /// Clear cached streak data. Called from "Start Over" so a session reset
    /// also clears the on-device streak display (the server record is separate).
    public func reset() {
        current = 0
        best = 0
        defaults.removeObject(forKey: Key.current)
        defaults.removeObject(forKey: Key.best)
    }
}
