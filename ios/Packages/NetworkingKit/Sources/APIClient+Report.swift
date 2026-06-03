import Foundation

extension APIClient {
    /// Report an AI response as objectionable (App Store Guideline 1.2). The
    /// reported text + session are recorded server-side for review. The caller
    /// treats this as fire-and-forget.
    public func reportResponse(content: String, reason: String?, sessionId: String) async throws {
        struct Body: Encodable {
            let sessionId: String
            let content: String
            let reason: String?
        }
        // Server returns `{ ok: true }`; decode into the empty marker and ignore.
        let _: Empty = try await send(
            method: "POST",
            path: "/api/report",
            body: Body(sessionId: sessionId, content: content, reason: reason)
        )
    }
}
