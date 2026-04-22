import Foundation

/// Narrow protocol for changing the active teaching mode. `ChatViewModel`
/// depends on this so tests can inject a stub.
public protocol ModeChanging: Sendable {
    func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange
}

extension APIClient: ModeChanging {}
