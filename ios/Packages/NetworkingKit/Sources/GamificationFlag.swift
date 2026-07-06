import Foundation

/// Standby gamification (quiet progress) — CLIENT-SIDE feature gate plus the
/// user's "progress nudges" preference.
///
/// TWO independent gates keep the feature OFF by default:
///   1. `clientEnabled` (this compile-time flag, default `false`) — when false
///      the client makes NO progression network calls and renders no progress
///      UI, so the shipped build is byte-identical regardless of the server.
///   2. The server's `GAMIFICATION_ENABLED` env flag — the server reports
///      `enabled: false` until it's on, and the client honors that too.
/// BOTH must be on for anything to appear.
///
/// `nudges` is a user preference (the Settings "Progress nudges" toggle) — a
/// way to quiet the brief move acknowledgments while keeping the Progress card.
///
/// ARCHITECTURE RULE — LEVEL ≠ RANK: nothing in this feature derives the
/// credentialed rank from XP/level/streak. The client surfaces engagement
/// Level only.
public enum GamificationFlag {
    /// Master client-side switch. Ship as `false`. Flip locally to develop the
    /// feature; pair with the server's `GAMIFICATION_ENABLED=1`.
    public static let clientEnabled = false

    /// UserDefaults key for the user's "show progress nudges" preference. Shared
    /// by the Settings toggle (writer, in SettingsFeature) and `GamificationStore`
    /// (reader, in PersistenceKit) so they agree without importing each other.
    public static let nudgesEnabledDefaultsKey = "gamification.nudges.enabled"

    /// The user's nudge preference. Defaults to ON — only an explicit "false"
    /// disables it — so enabling the feature shows brief move credits unless the
    /// user has opted out.
    public static func areNudgesEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: nudgesEnabledDefaultsKey) != "false"
    }

    /// Persist the user's nudge preference. Stored as a string so it shares the
    /// simple `PreferenceStore` contract used elsewhere.
    public static func setNudgesEnabled(_ enabled: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(enabled ? "true" : "false", forKey: nudgesEnabledDefaultsKey)
    }
}
