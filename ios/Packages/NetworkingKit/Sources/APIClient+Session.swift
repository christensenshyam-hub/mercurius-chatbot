import Foundation

extension APIClient {
    /// Fetch the server's current streak for a session. Used once on launch to
    /// seed `StreakStore` so the streak shows before the first chat of the
    /// session. Returns `nil` if the session has no record yet.
    ///
    /// `GET /api/session/:id` → `{ stats: { session, totalSessions }, recentMessages }`;
    /// `session` is the raw row, of which we only need `streak`.
    public func sessionStreak(sessionId: String) async throws -> Int? {
        struct Response: Decodable {
            struct Stats: Decodable {
                struct Session: Decodable { let streak: Int? }
                let session: Session?
            }
            let stats: Stats
        }
        let response: Response = try await send(
            method: "GET",
            path: "/api/session/\(sessionId)",
            body: Optional<Empty>.none
        )
        return response.stats.session?.streak
    }
}

/// Narrow protocol for reading session stats — mirrors `Reporting`.
public protocol SessionStatsFetching: Sendable {
    func sessionStreak(sessionId: String) async throws -> Int?
}

extension APIClient: SessionStatsFetching {}
