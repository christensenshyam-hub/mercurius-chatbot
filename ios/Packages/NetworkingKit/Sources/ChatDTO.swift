import Foundation

/// Wire-format chat message. The role matches the server's contract:
/// `"user"` | `"assistant"`. Represented as a `String` in JSON rather than
/// an enum so unknown roles from the server don't fail decoding.
public struct ChatMessageDTO: Codable, Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Request body for `POST /api/chat`.
struct ChatRequestBody: Encodable {
    let messages: [ChatMessageDTO]
    let sessionId: String
}

/// Full (non-streaming) response body. Only used as a fallback; the
/// streaming path emits the equivalent via `.complete`.
public struct ChatResponse: Decodable, Sendable, Equatable {
    public let reply: String
    public let sessionId: String
    public let mode: String
    public let unlocked: Bool
    public let justUnlocked: Bool?
    public let streak: Int?
    public let difficulty: Int?
    public let suggestSummary: Bool?
    /// Set by the server's curriculum path when the student demonstrated
    /// proficiency this turn (the stripped `[LESSON_COMPLETE]` marker). nil from
    /// older servers / non-curriculum turns → treated as "not complete".
    public let lessonComplete: Bool?

    public init(
        reply: String,
        sessionId: String,
        mode: String,
        unlocked: Bool,
        justUnlocked: Bool? = nil,
        streak: Int? = nil,
        difficulty: Int? = nil,
        suggestSummary: Bool? = nil,
        lessonComplete: Bool? = nil
    ) {
        self.reply = reply
        self.sessionId = sessionId
        self.mode = mode
        self.unlocked = unlocked
        self.justUnlocked = justUnlocked
        self.streak = streak
        self.difficulty = difficulty
        self.suggestSummary = suggestSummary
        self.lessonComplete = lessonComplete
    }
}

/// Events emitted by the SSE stream.
///
/// Mirrors the server's payload shape:
/// - `delta`: incremental text chunk
/// - `complete`: final reply with session/mode/streak/etc
/// - `error`: a recoverable error reported mid-stream
public enum ChatStreamEvent: Sendable, Equatable {
    /// A text chunk to append to the assistant message in progress.
    case delta(text: String)

    /// The stream finished and the server sent the final reply.
    case complete(ChatResponse)

    /// The server reported an error. No more events will follow.
    case streamError(message: String)
}

/// Internal JSON shape of a single SSE payload. We decode it to this
/// first, then normalize into `ChatStreamEvent` at the parse boundary.
struct SSEPayload: Decodable {
    let type: String
    let text: String?
    // Fields below are only present on `complete`:
    let reply: String?
    let sessionId: String?
    let mode: String?
    let unlocked: Bool?
    let justUnlocked: Bool?
    let streak: Int?
    let difficulty: Int?
    let suggestSummary: Bool?
    let lessonComplete: Bool?
    // Only present on `error`:
    let error: String?
}
