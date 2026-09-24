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
/// - `error`: either a refusal (carries a `ServerRefusalCode`) or a
///   recoverable error reported mid-stream
public enum ChatStreamEvent: Sendable, Equatable {
    /// A text chunk to append to the assistant message in progress.
    case delta(text: String)

    /// The stream finished and the server sent the final reply.
    case complete(ChatResponse)

    /// The server declined this turn before answering — quota, spend cap,
    /// paused, busy or restarting. `code` is a `ServerRefusalCode` raw value;
    /// `message` is the server's own student-facing copy; `retryAfter` is
    /// seconds until it is worth trying again, when the server says. No more
    /// events will follow.
    case refusal(code: String, message: String, retryAfter: TimeInterval?)

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
    // Only present on `error`. `code` and `retryAfterSec` arrive on refusal
    // frames; plain mid-stream errors carry just `error` (or a code outside
    // `ServerRefusalCode`).
    let error: String?
    let code: String?
    @LenientSeconds var retryAfterSec: TimeInterval?
}

/// `retryAfterSec` however the server spells it: a number, a numeric string,
/// or nothing. A strict `Double` would make an otherwise-valid refusal frame
/// or error body undecodable over a quoted `"60"`, and the student would see
/// a generic decoding error instead of the server's own copy.
@propertyWrapper
struct LenientSeconds: Decodable, Equatable {
    var wrappedValue: TimeInterval?

    init(wrappedValue: TimeInterval?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = Self.seconds(in: container)
    }

    private static func seconds(in container: SingleValueDecodingContainer) -> TimeInterval? {
        if let number = try? container.decode(Double.self), number.isFinite {
            return number
        }
        if let text = try? container.decode(String.self),
           let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite {
            return number
        }
        return nil
    }
}

extension KeyedDecodingContainer {
    /// Synthesized `Decodable` calls `decode`, not `decodeIfPresent`, for a
    /// wrapped property — an absent or `null` key must still yield nil.
    func decode(_ type: LenientSeconds.Type, forKey key: Key) throws -> LenientSeconds {
        try decodeIfPresent(type, forKey: key) ?? LenientSeconds(wrappedValue: nil)
    }
}
