import Foundation
import NetworkingKit

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

/// Lightweight summary of a stored conversation — enough to render a
/// row in the chat-history list without hydrating every message.
///
/// Sorted by `updatedAt` descending so the most recently active
/// conversation comes first. `title` is a short, derived label
/// (typically the first user message); `preview` is a snippet from
/// the most recent message regardless of role.
public struct ConversationSummary: Identifiable, Equatable, Sendable, Hashable {
    public let id: UUID
    /// `ChatMode.rawValue` — string form is forward-compatible with
    /// future modes the client might not know about. Consumers map
    /// to `ChatMode` at the UI boundary.
    public let mode: String
    public let title: String
    public let preview: String
    public let messageCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        mode: String,
        title: String,
        preview: String,
        messageCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.preview = preview
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Full-fidelity conversation read — id, mode, every message,
/// timestamps. Used when reopening an archived chat to seed
/// `ChatViewModel.messages` and synchronize `currentMode`.
public struct StoredConversation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let mode: String
    public let messages: [StoredMessage]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        mode: String,
        messages: [StoredMessage],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.mode = mode
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
    /// Most recently updated conversation across every mode. Used by
    /// `ChatViewModel` on first launch to land on whatever the user
    /// was last working on.
    func latestConversationId() -> UUID?

    /// Most recently updated conversation in `mode`, or nil if there
    /// isn't one yet. Used when the user switches modes — we resume
    /// their last conversation in that mode rather than starting a
    /// fresh one every time.
    func latestConversationId(in mode: ChatMode) -> UUID?

    /// Create a new conversation in `mode` and return its id. Mode is
    /// fixed at creation time and never changes for the life of the
    /// conversation — a Debate chat is Debate forever.
    func createConversation(mode: ChatMode) -> UUID

    /// Load the chronologically-ordered messages for a conversation.
    /// Returns an empty array if the conversation doesn't exist.
    func loadMessages(conversationId: UUID) -> [StoredMessage]

    /// Load the full conversation including its mode. Returns nil if
    /// the id is unknown. Used by "reopen archived chat" flows that
    /// need to know which mode to switch the app into.
    func loadConversation(conversationId: UUID) -> StoredConversation?

    /// Append a single message to a conversation. If the conversation
    /// id is unknown, the call is a no-op (defensive).
    func append(_ message: StoredMessage, to conversationId: UUID)

    /// List every conversation as a UI-ready summary, sorted by
    /// `updatedAt` descending. Empty list means no history.
    func listConversations() -> [ConversationSummary]

    /// Delete a single conversation (cascades to its messages).
    /// No-op on unknown id. Used by swipe-to-delete in Chat History.
    func delete(conversationId: UUID)

    /// Remove every conversation and message. Used by "Start Over"
    /// in Settings so session reset also clears local history.
    func deleteAll()
}
