import Foundation

extension APIClient {
    /// Result of a successful mode change.
    ///
    /// `unlocked` was a Direct-Mode-era field: the current server's
    /// `/api/mode` returns only `{ mode }`, while the deployed legacy
    /// generation still includes `unlocked`. Decoding it as required would
    /// make EVERY mode switch fail against the current server, so it
    /// defaults to `false` when absent (nothing reads it anymore).
    public struct ModeChange: Decodable, Sendable, Equatable {
        public let mode: String
        public let unlocked: Bool

        private enum CodingKeys: String, CodingKey { case mode, unlocked }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mode = try container.decode(String.self, forKey: .mode)
            unlocked = try container.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
        }

        public init(mode: String, unlocked: Bool = false) {
            self.mode = mode
            self.unlocked = unlocked
        }
    }

    /// Ask the server to change the active mode for a session.
    ///
    /// The server is the source of truth and rejects unsupported modes.
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
