import Foundation

extension APIClient {
    /// Generate a comprehension quiz from the current conversation.
    ///
    /// The server needs ≥4 messages of history; the client should
    /// enforce this before calling to give users faster feedback, but
    /// the server is still the source of truth.
    public func generateQuiz(sessionId: String) async throws -> Quiz {
        struct Body: Encodable {
            let sessionId: String
            let messages: [ChatMessageDTO]
        }
        // `messages` is required by the endpoint but the server reads
        // from its own DB — the value we pass is ignored server-side.
        // Passing an empty array keeps the wire contract minimal.
        return try await send(
            method: "POST",
            path: "/api/quiz",
            body: Body(sessionId: sessionId, messages: [])
        )
    }

    /// Generate an end-of-session report card.
    public func generateReportCard(sessionId: String) async throws -> ReportCard {
        struct Body: Encodable {
            let sessionId: String
            let messages: [ChatMessageDTO]
        }
        return try await send(
            method: "POST",
            path: "/api/report-card",
            body: Body(sessionId: sessionId, messages: [])
        )
    }

    /// Grade a unit test's open-ended "defense" answer. Stateless — unlike the
    /// quiz / report-card endpoints, it carries everything it needs in the body
    /// and does not read conversation history. Returns the letter grade, a
    /// pass/fail verdict (grade A or B), and short feedback.
    public func gradeUnitDefense(
        sessionId: String,
        unitId: String,
        unitTitle: String,
        defensePrompt: String,
        answer: String
    ) async throws -> UnitDefenseResult {
        struct Body: Encodable {
            let sessionId: String
            let unitId: String
            let unitTitle: String
            let defensePrompt: String
            let answer: String
        }
        return try await send(
            method: "POST",
            path: "/api/unit-test/grade",
            body: Body(
                sessionId: sessionId, unitId: unitId, unitTitle: unitTitle,
                defensePrompt: defensePrompt, answer: answer
            )
        )
    }
}

// MARK: - Protocols for testability

/// The narrow tool-generation surface `ChatFeature` depends on, so
/// tests can inject stubs.
public protocol ToolsProviding: Sendable {
    func generateQuiz(sessionId: String) async throws -> Quiz
    func generateReportCard(sessionId: String) async throws -> ReportCard
}

extension APIClient: ToolsProviding {}
