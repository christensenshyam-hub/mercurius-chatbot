import Foundation

/// In-memory `ChatStore` — used by tests and as a safe fallback if
/// SwiftData initialization fails on disk.
///
/// Not thread-safe; MainActor-isolated via the protocol.
@MainActor
public final class InMemoryChatStore: ChatStore {

    private struct Box {
        let id: UUID
        var createdAt: Date
        var updatedAt: Date
        var messages: [StoredMessage] = []
    }

    private var conversations: [UUID: Box] = [:]

    public init() {}

    public func latestConversationId() -> UUID? {
        conversations.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.id
    }

    public func createConversation() -> UUID {
        let id = UUID()
        let now = Date()
        conversations[id] = Box(id: id, createdAt: now, updatedAt: now)
        return id
    }

    public func loadMessages(conversationId: UUID) -> [StoredMessage] {
        conversations[conversationId]?.messages.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    public func append(_ message: StoredMessage, to conversationId: UUID) {
        guard var box = conversations[conversationId] else { return }
        box.messages.append(message)
        box.updatedAt = Date()
        conversations[conversationId] = box
    }

    public func deleteAll() {
        conversations.removeAll()
    }
}
