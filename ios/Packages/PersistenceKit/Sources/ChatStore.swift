import Foundation

/// Plain-old-value representation of a stored message, decoupled from
/// the SwiftData `@Model` class. Features consume this type — they
/// never see `MessageRecord` directly.
public struct StoredMessage: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: UUID, role: String, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// Narrow persistence interface `ChatFeature` depends on. `ChatViewModel`
/// gets one of these injected — in production a `SwiftDataChatStore`,
/// in tests an `InMemoryChatStore`.
///
/// All methods are MainActor-isolated because SwiftData's
/// `ModelContext` is also main-actor-isolated on iOS 17.
@MainActor
public protocol ChatStore: AnyObject {
    /// The most recently updated conversation's id, if any.
    func latestConversationId() -> UUID?

    /// Create a new conversation and return its id. The new
    /// conversation becomes the "latest".
    func createConversation() -> UUID

    /// Load the chronologically-ordered messages for a conversation.
    /// Returns an empty array if the conversation doesn't exist.
    func loadMessages(conversationId: UUID) -> [StoredMessage]

    /// Append a single message to a conversation. If the conversation
    /// id is unknown, the call is a no-op (defensive).
    func append(_ message: StoredMessage, to conversationId: UUID)

    /// Remove every conversation and message. Used by "Start Over"
    /// in Settings so session reset also clears local history.
    func deleteAll()
}
