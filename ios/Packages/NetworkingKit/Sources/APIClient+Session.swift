import Foundation

/// The server's stored streak for a session plus the day it was last
/// confirmed (`last_session_date`, "yyyy-MM-dd", UTC). The stored streak is
/// only recomputed when the user chats, so on its own it can describe a
/// streak that already lapsed — callers seeding a cache must anchor freshness
/// to `lastSessionDate`, not to when they happened to fetch.
public struct SessionStreakSnapshot: Sendable, Equatable {
    public let streak: Int
    public let lastSessionDate: String?

    public init(streak: Int, lastSessionDate: String?) {
        self.streak = streak
        self.lastSessionDate = lastSessionDate
    }
}

extension APIClient {
    /// Fetch the server's current streak for a session. Used once on launch to
    /// seed `StreakStore` so the streak shows before the first chat of the
    /// session. Returns `nil` if the session has no record yet.
    ///
    /// `GET /api/session/:id` → `{ stats: { session, totalSessions }, recentMessages }`;
    /// `session` is the raw row, of which we only need `streak` and
    /// `last_session_date`.
    public func sessionStreak(sessionId: String) async throws -> SessionStreakSnapshot? {
        struct Response: Decodable {
            struct Stats: Decodable {
                struct Session: Decodable {
                    let streak: Int?
                    let lastSessionDate: String?

                    enum CodingKeys: String, CodingKey {
                        case streak
                        case lastSessionDate = "last_session_date"
                    }
                }
                let session: Session?
            }
            let stats: Stats
        }
        let response: Response = try await send(
            method: "GET",
            path: "/api/session/\(sessionId)",
            body: Optional<Empty>.none
        )
        guard let session = response.stats.session, let streak = session.streak else { return nil }
        return SessionStreakSnapshot(streak: streak, lastSessionDate: session.lastSessionDate)
    }

    /// Erase everything the server holds for a session — messages, images,
    /// reports, usage, progression. Backs "Start Over" and consent withdrawal.
    ///
    /// `DELETE /api/session/:id` → `{ ok: true, deleted: {...} }`. Idempotent:
    /// a session the server has never seen (or already erased) still returns
    /// 200, so a retry after a dropped connection is safe. The id must be the
    /// one the data was written under — call this BEFORE rotating it.
    public func deleteSession(sessionId: String) async throws {
        struct Response: Decodable {
            let ok: Bool
        }
        let response: Response = try await send(
            method: "DELETE",
            path: "/api/session/\(sessionId)",
            body: Optional<Empty>.none
        )
        guard response.ok else {
            throw APIError.unknown(underlying: "Server did not confirm deletion")
        }
    }
}

/// Narrow protocol for reading session stats — mirrors `Reporting`.
public protocol SessionStatsFetching: Sendable {
    func sessionStreak(sessionId: String) async throws -> SessionStreakSnapshot?
}

extension APIClient: SessionStatsFetching {}

/// Narrow protocol for erasing a session server-side. `SettingsViewModel`
/// depends on this (not the concrete `APIClient`) so tests can inject a stub.
public protocol SessionDeleting: Sendable {
    func deleteSession(sessionId: String) async throws
}

extension APIClient: SessionDeleting {}
