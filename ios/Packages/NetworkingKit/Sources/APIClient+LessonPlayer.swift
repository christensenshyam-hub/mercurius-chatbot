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
