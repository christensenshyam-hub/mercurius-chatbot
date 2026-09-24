import Foundation

/// Narrow protocol for reporting an objectionable AI response. `ChatViewModel`
/// depends on this (not the concrete `APIClient`) so tests can inject a stub —
/// mirrors `ModeChanging` / `ImageUploading`.
///
/// - `content`: the assistant text being reported.
/// - `userMessage`: the visible user turn that preceded it, when there is one
///   (a lesson opener has none).
/// - `context`: where the report came from — see `ReportContext`.
public protocol Reporting: Sendable {
    func reportResponse(
        content: String,
        reason: ReportReason,
        userMessage: String?,
        context: ReportContext,
        sessionId: String
    ) async throws
}

extension APIClient: Reporting {}
