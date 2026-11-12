import Foundation

/// `GET /api/lesson-player/config`: whether the server has the interactive
/// lesson player pilot on, and for which lessons.
public struct LessonPlayerConfig: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let lessons: [String]

    public init(enabled: Bool, lessons: [String]) {
        self.enabled = enabled
        self.lessons = lessons
    }

    public static let off = LessonPlayerConfig(enabled: false, lessons: [])
}

extension APIClient {
    /// The pilot flag. No session id: the answer is the same for everyone.
    public func lessonPlayerConfig() async throws -> LessonPlayerConfig {
        try await send(method: "GET", path: "/api/lesson-player/config", body: Optional<Empty>.none)
    }
}

/// `POST /api/lesson-player/evaluate`: the server's check of one short
/// response against a rubric it holds. Ids and the answer only.
public enum LessonResponseCheck: Equatable, Sendable {
    /// `status` is "meets" or "not_yet"; the client validates the rest again.
    case evaluated(status: String, feedback: String, hint: String?, flags: [String])
    /// The answer read as a crisis: show support, never a grade.
    case crisis(message: String)
}

extension APIClient {
    public func checkLessonResponse(
        sessionId: String,
        lessonId: String,
        contentVersion: Int,
        stepId: String,
        rubricId: String,
        answer: String
    ) async throws -> LessonResponseCheck {
        struct Body: Encodable {
            let sessionId: String
            let lessonId: String
            let contentVersion: Int
            let stepId: String
            let rubricId: String
            let answer: String
        }
        struct Reply: Decodable {
            let status: String?
            let feedback: String?
            let hint: String?
            let flags: [String]?
            let crisis: Bool?
            let message: String?
        }
        let reply: Reply = try await send(
            method: "POST",
            path: "/api/lesson-player/evaluate",
            body: Body(sessionId: sessionId, lessonId: lessonId, contentVersion: contentVersion,
                       stepId: stepId, rubricId: rubricId, answer: answer)
        )
        if reply.crisis == true { return .crisis(message: reply.message ?? "") }
        guard let status = reply.status, let feedback = reply.feedback else {
            throw APIError.invalidModelOutput(reason: "evaluation without status")
        }
        return .evaluated(status: status, feedback: feedback, hint: reply.hint, flags: reply.flags ?? [])
    }
}
