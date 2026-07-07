import Foundation

// MARK: - Reasons (mirror of lib/gamification/reasons.js)

/// The XP-awardable reasoning/engagement moves. MUST stay in sync with the
/// server's `REASON` registry (lib/gamification/reasons.js). There is
/// deliberately NO case for "correct answer" — correctness is never rewarded.
public enum ProgressionReason: String, Sendable, CaseIterable, Codable {
    case dailyReturn = "DAILY_RETURN"
    case clarifyingQuestion = "CLARIFYING_QUESTION"
    case positionRevision = "POSITION_REVISION"
    case selfCorrection = "SELF_CORRECTION"
    case uncertaintyExpressed = "UNCERTAINTY_EXPRESSED"
    case reflectionCompleted = "REFLECTION_COMPLETED"
    case moduleCompleted = "MODULE_COMPLETED"

    /// Factual, character-free phrase the UI shows when crediting this move.
    /// Describes the MOVE, never correctness — "Revised your position", not
    /// "Correct!".
    public var creditLabel: String {
        switch self {
        case .dailyReturn:          return "Showed up today"
        case .clarifyingQuestion:   return "Asked a clarifying question"
        case .positionRevision:     return "Revised your position"
        case .selfCorrection:       return "Caught your own mistake"
        case .uncertaintyExpressed: return "Named what you weren't sure of"
        case .reflectionCompleted:  return "Completed a reflection"
        case .moduleCompleted:      return "Completed a module"
        }
    }

    /// Label for a raw reason string from the server's recent-events feed.
    public static func creditLabel(forRaw raw: String) -> String {
        ProgressionReason(rawValue: raw)?.creditLabel ?? "Progress"
    }
}

// MARK: - DTOs

/// One recent XP award, for the factual "Recent" credits log.
public struct ProgressionXpEvent: Decodable, Sendable, Equatable {
    public let amount: Int
    public let reason: String
    public let sourceType: String?
    public let at: Double?
    public init(amount: Int, reason: String, sourceType: String?, at: Double?) {
        self.amount = amount
        self.reason = reason
        self.sourceType = sourceType
        self.at = at
    }

    private enum CodingKeys: String, CodingKey {
        case amount, reason, sourceType, at
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amount = try container.decode(Int.self, forKey: .amount)
        reason = try container.decode(String.self, forKey: .reason)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        // `at` is xp_ledger.created_at, a BIGINT epoch-millis column. SQLite
        // serves it as a JSON number, but node-postgres returns int8 columns
        // as STRINGS by default — accept both so `/api/progression/me` decodes
        // against either driver. A malformed value degrades to nil rather than
        // failing the whole ProgressionState decode.
        if let number = try? container.decode(Double.self, forKey: .at) {
            at = number
        } else if let string = try? container.decode(String.self, forKey: .at) {
            at = Double(string)
        } else {
            at = nil
        }
    }
}

/// `GET /api/progression/me` response. Everything except `enabled` is optional
/// so the flag-off `{ "enabled": false }` shape decodes cleanly.
///
/// NOTE: no `rank` field and no character/voice payload. Level (engagement) and
/// Rank (credential) are separate tracks; this payload carries XP/Level/streak
/// plus the factual recent-credits feed only.
public struct ProgressionState: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let xp: Int?
    public let level: Int?
    public let levelProgress: Double?
    public let xpToNext: Int?
    public let streak: Int?
    public let longestStreak: Int?
    public let recentXpEvents: [ProgressionXpEvent]?

    public init(
        enabled: Bool,
        xp: Int? = nil,
        level: Int? = nil,
        levelProgress: Double? = nil,
        xpToNext: Int? = nil,
        streak: Int? = nil,
        longestStreak: Int? = nil,
        recentXpEvents: [ProgressionXpEvent]? = nil
    ) {
        self.enabled = enabled
        self.xp = xp
        self.level = level
        self.levelProgress = levelProgress
        self.xpToNext = xpToNext
        self.streak = streak
        self.longestStreak = longestStreak
        self.recentXpEvents = recentXpEvents
    }
}

/// `POST /api/progression/event` response. `reason` echoes the awarded move so
/// the client can render a factual acknowledgment ("Revised your position
/// · +14 XP") without any server-supplied voice copy.
public struct ProgressionEventResult: Decodable, Sendable, Equatable {
    public let enabled: Bool
    public let status: String?
    public let awarded: Int?
    public let leveledUp: Bool?
    public let reason: String?
    public let xp: Int?
    public let level: Int?
    public let levelProgress: Double?
    public let xpToNext: Int?
    public let streak: Int?

    public init(
        enabled: Bool,
        status: String? = nil,
        awarded: Int? = nil,
        leveledUp: Bool? = nil,
        reason: String? = nil,
        xp: Int? = nil,
        level: Int? = nil,
        levelProgress: Double? = nil,
        xpToNext: Int? = nil,
        streak: Int? = nil
    ) {
        self.enabled = enabled
        self.status = status
        self.awarded = awarded
        self.leveledUp = leveledUp
        self.reason = reason
        self.xp = xp
        self.level = level
        self.levelProgress = levelProgress
        self.xpToNext = xpToNext
        self.streak = streak
    }
}

// MARK: - Client

extension APIClient {
    /// Fetch the standby gamification snapshot. Returns
    /// `ProgressionState(enabled: false)` when the server flag is off — the
    /// caller treats that as "feature unavailable".
    public func progression(sessionId: String) async throws -> ProgressionState {
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionId
        return try await send(
            method: "GET",
            path: "/api/progression/me?sessionId=\(encoded)",
            body: Optional<Empty>.none
        )
    }

    /// REQUEST an XP evaluation for a reasoning/engagement move. The SERVER
    /// decides the award (idempotency / caps / diminishing returns are all
    /// enforced server-side); the client cannot mint XP. Optional fields are
    /// omitted from the JSON when nil (Swift's synthesized `encodeIfPresent`),
    /// matching the server's optional-not-nullable Zod schema.
    public func recordProgressionEvent(
        sessionId: String,
        reason: ProgressionReason,
        sourceType: String?,
        sourceId: String?,
        sessionRef: String?
    ) async throws -> ProgressionEventResult {
        struct Body: Encodable {
            let sessionId: String
            let reason: String
            let sourceType: String?
            let sourceId: String?
            let sessionRef: String?
        }
        return try await send(
            method: "POST",
            path: "/api/progression/event",
            body: Body(
                sessionId: sessionId,
                reason: reason.rawValue,
                sourceType: sourceType,
                sourceId: sourceId,
                sessionRef: sessionRef
            )
        )
    }
}

/// Narrow protocol so stores / view models depend on this instead of the
/// concrete `APIClient` and can inject a stub in tests — mirrors
/// `LeaderboardFetching` / `ProfileSetting`.
public protocol ProgressionProviding: Sendable {
    func progression(sessionId: String) async throws -> ProgressionState
    func recordProgressionEvent(
        sessionId: String,
        reason: ProgressionReason,
        sourceType: String?,
        sourceId: String?,
        sessionRef: String?
    ) async throws -> ProgressionEventResult
}

extension APIClient: ProgressionProviding {}
