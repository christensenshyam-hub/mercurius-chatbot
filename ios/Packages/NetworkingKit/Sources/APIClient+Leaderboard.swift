import Foundation

/// One row of the global leaderboard. The server (`db.getLeaderboard`) returns an
/// already-anonymized projection: a 4-char `badge` derived from the session id
/// (never the id itself), and `name` only if the student opted into a display
/// name via `/api/profile`. Safe to render for a minors' audience.
public struct LeaderboardEntry: Decodable, Sendable, Equatable, Identifiable {
    public let rank: Int
    public let badge: String
    public let streak: Int
    public let messages: Int
    public let unlocked: Bool
    public let name: String?

    public var id: Int { rank }

    public init(rank: Int, badge: String, streak: Int, messages: Int, unlocked: Bool, name: String?) {
        self.rank = rank
        self.badge = badge
        self.streak = streak
        self.messages = messages
        self.unlocked = unlocked
        self.name = name
    }
}

extension APIClient {
    /// Fetch the global top-20 leaderboard (ranked by streak, then message count).
    public func leaderboard() async throws -> [LeaderboardEntry] {
        try await send(method: "GET", path: "/api/leaderboard", body: Optional<Empty>.none)
    }
}

/// Narrow protocol so `LeaderboardViewModel` can depend on this instead of the
/// concrete `APIClient` and inject a stub in tests — mirrors `Reporting`.
public protocol LeaderboardFetching: Sendable {
    func leaderboard() async throws -> [LeaderboardEntry]
}

extension APIClient: LeaderboardFetching {}
