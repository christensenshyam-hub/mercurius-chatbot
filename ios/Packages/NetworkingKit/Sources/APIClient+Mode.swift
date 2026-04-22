import Foundation

extension APIClient {
    /// Result of a successful mode change.
    public struct ModeChange: Decodable, Sendable, Equatable {
        public let mode: String
        public let unlocked: Bool
    }

    /// Ask the server to change the active mode for a session.
    ///
    /// Throws `APIError.unauthorized` if the student is trying to enter
    /// Direct mode without having passed the comprehension test — the
    /// UI should gate this at the client too, but the server is the
    /// source of truth.
    public func changeMode(to mode: ChatMode, sessionId: String) async throws -> ModeChange {
        struct Body: Encodable {
            let sessionId: String
            let mode: String
        }
        return try await send(
            method: "POST",
            path: "/api/mode",
            body: Body(sessionId: sessionId, mode: mode.rawValue)
        )
    }
}
