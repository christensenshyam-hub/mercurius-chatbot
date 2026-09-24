import Foundation

extension APIClient {
    /// Server-side caps on `POST /api/report` (Zod `.max(...)`). Content and
    /// the preceding user turn are clamped here so a long exchange never
    /// turns a report into a 400 — the reviewer still gets the start of it.
    static let reportContentLimit = 10_000
    static let reportUserMessageLimit = 4_000

    /// Report an AI response as objectionable (App Store Guideline 1.2). The
    /// reported text, the user turn before it, and where it happened are
    /// recorded server-side for review.
    ///
    /// Body: `{ sessionId, content, reason, userMessage?, context }` — nil
    /// keys are omitted, never sent as `null` (the server's schema rejects
    /// `null` for optional fields). Response `{ ok, id }` is decoded
    /// leniently and discarded.
    public func reportResponse(
        content: String,
        reason: ReportReason,
        userMessage: String?,
        context: ReportContext,
        sessionId: String
    ) async throws {
        struct Body: Encodable {
            let sessionId: String
            let content: String
            let reason: ReportReason
            // Optional: synthesized Encodable uses encodeIfPresent, so the key
            // is absent when nil.
            let userMessage: String?
            let context: ReportContext
        }
        struct Response: Decodable {
            let ok: Bool?
            let id: Int?
        }
        let _: Response = try await send(
            method: "POST",
            path: "/api/report",
            body: Body(
                sessionId: sessionId,
                content: String(content.prefix(Self.reportContentLimit)),
                reason: reason,
                userMessage: userMessage.map { String($0.prefix(Self.reportUserMessageLimit)) },
                context: context
            )
        )
    }
}
