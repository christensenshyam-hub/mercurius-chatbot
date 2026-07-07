import Foundation
import Observation
import NetworkingKit

/// One factual reasoning-move credit for the "Recent" log. Character-free —
/// the label describes the MOVE ("Revised your position"), never correctness.
public struct ProgressCredit: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let xp: Int
    public init(id: String, label: String, xp: Int) {
        self.id = id
        self.label = label
        self.xp = xp
    }
}

/// A brief, factual acknowledgment shown right after a move is credited — the
/// quiet replacement for the old character pop-up. No voice; just the move and
/// the points.
public struct ProgressNudge: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let xp: Int
    public let leveledUp: Bool
    public init(label: String, xp: Int, leveledUp: Bool) {
        self.id = UUID()
        self.label = label
        self.xp = xp
        self.leveledUp = leveledUp
    }
}

/// Server-authoritative cache for the standby gamification system (quiet
/// progress). Mirrors `StreakStore`: the server owns the truth (XP, Level,
/// streak, every award decision); this store caches the latest values so the UI
/// can render instantly, exposes the factual recent-credits feed, and surfaces
/// the brief move nudge.
///
/// DOUBLE-GATED OFF BY DEFAULT (see `GamificationFlag`). When the client gate is
/// off, `refresh`/`recordEvent` are no-ops with NO network calls and `enabled`
/// stays false — nothing renders.
///
/// LEVEL ≠ RANK. This store holds XP/Level/streak — the engagement track. It has
/// no concept of rank; the client never derives rank from these values.
@MainActor
@Observable
public final class GamificationStore {
    /// Server-confirmed availability (server flag on AND a successful fetch).
    public private(set) var enabled: Bool
    public private(set) var xp: Int
    public private(set) var level: Int
    /// Progress through the current Level, 0…1.
    public private(set) var levelProgress: Double
    public private(set) var streak: Int

    /// Factual log of recent reasoning-move credits (newest first).
    public private(set) var recentCredits: [ProgressCredit]
    /// The most recent move credit, for a brief acknowledgment. Honors the
    /// user's "progress nudges" preference; nil when there's nothing to show.
    public private(set) var lastNudge: ProgressNudge?

    /// Load state for `refresh` (reuses `APIError`'s user-facing message on
    /// failure). The progress surface stays SILENT in every non-loaded state —
    /// it never shows a spinner or error banner — but the phase is exposed for
    /// observability and tests.
    public enum LoadPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(reason: String)
    }
    public private(set) var loadPhase: LoadPhase = .idle

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clientEnabled: Bool

    private enum Key {
        static let xp = "gamification.xp"
        static let level = "gamification.level"
        static let streak = "gamification.streak"
    }

    /// `clientEnabled` is injectable purely so tests can exercise the enabled
    /// path; production always uses the default (`GamificationFlag.clientEnabled`
    /// = false).
    public init(defaults: UserDefaults = .standard, clientEnabled: Bool = GamificationFlag.clientEnabled) {
        self.defaults = defaults
        self.clientEnabled = clientEnabled
        self.enabled = false
        self.xp = defaults.integer(forKey: Key.xp)
        self.level = max(1, defaults.integer(forKey: Key.level))
        self.levelProgress = 0
        self.streak = defaults.integer(forKey: Key.streak)
        self.recentCredits = []
        self.lastNudge = nil
    }

    /// Probe the server for the standby progress state and cache it, including
    /// the factual recent-credits feed. NO-OP (and NO network call) when the
    /// client gate is off. A failure is swallowed into `.failed` — progress is
    /// non-critical, so an error simply leaves the feature disabled.
    public func refresh(using provider: ProgressionProviding, sessionId: String) async {
        guard clientEnabled else { return }
        loadPhase = .loading
        do {
            let state = try await provider.progression(sessionId: sessionId)
            apply(enabled: state.enabled, xp: state.xp, level: state.level, progress: state.levelProgress, streak: state.streak)
            if state.enabled, let events = state.recentXpEvents {
                recentCredits = events.map { e in
                    ProgressCredit(
                        id: "\(e.reason)-\(Int(e.at ?? 0))",
                        label: ProgressionReason.creditLabel(forRaw: e.reason),
                        xp: e.amount
                    )
                }
            }
            loadPhase = .loaded
        } catch let error as APIError {
            enabled = false
            loadPhase = .failed(reason: error.userFacingMessage)
        } catch {
            enabled = false
            loadPhase = .failed(reason: "Couldn't load progress.")
        }
    }

    /// Ask the server to evaluate a reasoning/engagement event. The server
    /// decides the award; we reflect the returned state, log a factual credit,
    /// and (if the user's nudge preference is on) surface a brief acknowledgment.
    /// NO-OP when the client gate is off.
    public func recordEvent(
        using provider: ProgressionProviding,
        sessionId: String,
        reason: ProgressionReason,
        sourceType: String? = nil,
        sourceId: String? = nil,
        sessionRef: String? = nil
    ) async {
        guard clientEnabled else { return }
        do {
            let result = try await provider.recordProgressionEvent(
                sessionId: sessionId, reason: reason,
                sourceType: sourceType, sourceId: sourceId, sessionRef: sessionRef
            )
            apply(enabled: result.enabled, xp: result.xp, level: result.level, progress: result.levelProgress, streak: result.streak)
            // Only a real award is credited. The label is the factual MOVE —
            // never correctness, never a character's voice.
            if result.status == "awarded", let awarded = result.awarded, awarded > 0 {
                let credit = ProgressCredit(id: "\(reason.rawValue)-local-\(result.xp ?? 0)", label: reason.creditLabel, xp: awarded)
                recentCredits.insert(credit, at: 0)
                recentCredits = Array(recentCredits.prefix(10))
                if GamificationFlag.areNudgesEnabled(defaults) {
                    lastNudge = ProgressNudge(label: reason.creditLabel, xp: awarded, leveledUp: result.leveledUp ?? false)
                }
            }
        } catch {
            // Non-critical; leave cached state unchanged.
        }
    }

    /// Dismiss the current brief nudge.
    public func dismissNudge() { lastNudge = nil }

    private func apply(enabled: Bool, xp: Int?, level: Int?, progress: Double?, streak: Int?) {
        self.enabled = enabled
        guard enabled else { return }
        if let xp { self.xp = xp; defaults.set(xp, forKey: Key.xp) }
        if let level { self.level = max(1, level); defaults.set(self.level, forKey: Key.level) }
        if let progress { self.levelProgress = min(1, max(0, progress)) }
        if let streak { self.streak = streak; defaults.set(streak, forKey: Key.streak) }
    }
}

#if DEBUG
extension GamificationStore {
    /// Build a populated store for SwiftUI previews / snapshot fixtures. Lives
    /// in the same file so it can seed the `private(set)` state. Not compiled
    /// into release builds.
    public static func preview(
        enabled: Bool = true,
        xp: Int = 140,
        level: Int = 2,
        levelProgress: Double = 0.42,
        streak: Int = 3,
        withNudge: Bool = true
    ) -> GamificationStore {
        let store = GamificationStore(clientEnabled: true)
        store.enabled = enabled
        store.xp = xp
        store.level = level
        store.levelProgress = levelProgress
        store.streak = streak
        store.recentCredits = [
            ProgressCredit(id: "rev-0", label: ProgressionReason.positionRevision.creditLabel, xp: 14),
            ProgressCredit(id: "clar-0", label: ProgressionReason.clarifyingQuestion.creditLabel, xp: 6),
            ProgressCredit(id: "unc-0", label: ProgressionReason.uncertaintyExpressed.creditLabel, xp: 8),
        ]
        store.lastNudge = withNudge ? ProgressNudge(label: ProgressionReason.positionRevision.creditLabel, xp: 14, leveledUp: false) : nil
        store.loadPhase = enabled ? .loaded : .idle
        return store
    }
}
#endif
