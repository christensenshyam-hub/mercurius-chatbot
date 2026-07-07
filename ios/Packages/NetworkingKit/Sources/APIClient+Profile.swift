import Foundation

extension APIClient {
    /// Set the student's opt-in display name (shown on the leaderboard). The
    /// server sanitizes + caps it at 30 chars. Treated as fire-and-forget by
    /// callers; the `{ ok, displayName }` body is ignored.
    public func setDisplayName(_ name: String, sessionId: String) async throws {
        struct Body: Encodable {
            let sessionId: String
            let displayName: String
        }
        let _: Empty = try await send(
            method: "POST",
            path: "/api/profile",
            body: Body(sessionId: sessionId, displayName: name)
        )
    }
}

/// Narrow protocol for setting the opt-in display name — mirrors `Reporting`.
public protocol ProfileSetting: Sendable {
    func setDisplayName(_ name: String, sessionId: String) async throws
}

extension APIClient: ProfileSetting {}
