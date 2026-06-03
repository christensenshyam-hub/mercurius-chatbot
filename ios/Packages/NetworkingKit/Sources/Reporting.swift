import Foundation

/// Narrow protocol for reporting an objectionable AI response. `ChatViewModel`
/// depends on this (not the concrete `APIClient`) so tests can inject a stub —
/// mirrors `ModeChanging` / `ImageUploading`.
public protocol Reporting: Sendable {
    func reportResponse(content: String, reason: String?, sessionId: String) async throws
}

extension APIClient: Reporting {}
