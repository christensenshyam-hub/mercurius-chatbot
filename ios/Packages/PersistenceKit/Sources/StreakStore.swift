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
    /// When the server last confirmed `current`. `nil` for values cached
    /// before this field existed (treated as not fresh).
    public private(set) var lastUpdatedAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let current = "engagement.streak.current"
        static let best = "engagement.streak.best"
        static let updatedAt = "engagement.streak.updatedAt"
    }

    /// The streak's grace window is one missed day, so a cache older than
    /// ~2 days may describe a streak that has already died server-side.
    private static let freshnessWindow: TimeInterval = 48 * 60 * 60

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = defaults.integer(forKey: Key.current)
        self.best = defaults.integer(forKey: Key.best)
        self.lastUpdatedAt = defaults.object(forKey: Key.updatedAt) as? Date
    }

    /// Whether `current` was confirmed recently enough to make an active
    /// claim about it (e.g. the Home greeting's "Day N — keep your streak
    /// alive!"). A weeks-old cache can describe a streak that already
    /// lapsed — passive displays may still show the number, but copy that
    /// asserts the streak is alive should check this first.
    public var isCurrentFresh: Bool {
        guard current > 0, let lastUpdatedAt else { return false }
        return Date().timeIntervalSince(lastUpdatedAt) < Self.freshnessWindow
    }

    /// Whether the streak was confirmed today (local calendar) — i.e. the user
    /// already chatted today and the day is "saved". Drives the streak-defense
    /// reminder: no point warning someone about a day they already banked.
    /// (A launch `seed` stamps UTC midnight of the last chat day, which can
    /// read as "yesterday" locally — worst case one redundant reminder after a
    /// fresh install; a real in-app chat stamps precisely via `update`.)
    public var confirmedToday: Bool {
        guard let lastUpdatedAt else { return false }
        return Calendar.current.isDateInToday(lastUpdatedAt)
    }

    /// Record the latest authoritative streak from the server. No-op for
    /// non-positive values (the server's minimum is 1).
    ///
    /// Only for values the server just recomputed (the chat `complete` event) —
    /// "now" is genuinely when the server confirmed the streak was alive. For
    /// the launch fetch of the raw session row, use `seed(streak:lastSessionDate:)`
    /// instead, which anchors freshness to the server's own recency.
    public func update(streak: Int) {
        guard streak > 0 else { return }
        current = streak
        lastUpdatedAt = Date()
        defaults.set(current, forKey: Key.current)
        defaults.set(lastUpdatedAt, forKey: Key.updatedAt)
        if streak > best {
            best = streak
            defaults.set(best, forKey: Key.best)
        }
    }

    /// Seed the cache from the launch fetch of `GET /api/session/:id`. The
    /// session row's stored streak is only recomputed when the user chats, so a
    /// lapsed user's row can carry a dead streak for weeks — stamping
    /// `lastUpdatedAt` with the fetch time would defeat `isCurrentFresh` and let
    /// the Home greeting claim a dead streak is alive. Freshness is therefore
    /// taken from the server's own `last_session_date` ("yyyy-MM-dd", UTC): a
    /// month-old row seeds a month-old `lastUpdatedAt` and stays not-fresh.
    ///
    /// The stamp only ever moves FORWARD: the date parses to UTC midnight of
    /// the last chat day, so a same-day chat confirmation recorded by
    /// `update(streak:)` is more precise and must not be regressed. A missing
    /// or unparseable date seeds the value but never refreshes the stamp.
    public func seed(streak: Int, lastSessionDate: String?) {
        guard streak > 0 else { return }
        current = streak
        defaults.set(current, forKey: Key.current)
        if streak > best {
            best = streak
            defaults.set(best, forKey: Key.best)
        }
        if let confirmedAt = Self.parseSessionDate(lastSessionDate),
           confirmedAt > (lastUpdatedAt ?? .distantPast) {
            lastUpdatedAt = confirmedAt
            defaults.set(lastUpdatedAt, forKey: Key.updatedAt)
        }
    }

    /// Parse the server's `last_session_date` ("yyyy-MM-dd", UTC midnight).
    private static func parseSessionDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    /// Clear cached streak data. Called from "Start Over" so a session reset
    /// also clears the on-device streak display (the server record is separate).
    public func reset() {
        current = 0
        best = 0
        lastUpdatedAt = nil
        defaults.removeObject(forKey: Key.current)
        defaults.removeObject(forKey: Key.best)
        defaults.removeObject(forKey: Key.updatedAt)
    }
}
