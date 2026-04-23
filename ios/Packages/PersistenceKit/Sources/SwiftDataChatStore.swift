import Foundation
import SwiftData

/// SwiftData-backed implementation of `ChatStore`.
///
/// Construction can throw (Swift Data can fail to set up its container
/// on disk); callers should fall back to `InMemoryChatStore` in that
/// unlikely case rather than crashing the app.
@MainActor
public final class SwiftDataChatStore: ChatStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Construct a store backed by disk.
    public init() throws {
        let schema = Schema([ConversationRecord.self, MessageRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    /// Construct an in-memory-only container — useful for tests that
    /// specifically want to exercise the SwiftData code path without
    /// touching the filesystem.
    public static func inMemory() throws -> SwiftDataChatStore {
        let store = try SwiftDataChatStore(inMemory: true)
        return store
    }

    private init(inMemory: Bool) throws {
        let schema = Schema([ConversationRecord.self, MessageRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - ChatStore

    public func latestConversationId() -> UUID? {
        var descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first?.id
        } catch {
            return nil
        }
    }

    public func createConversation() -> UUID {
        let convo = ConversationRecord()
        context.insert(convo)
        try? context.save()
        return convo.id
    }

    public func loadMessages(conversationId: UUID) -> [StoredMessage] {
        guard let convo = fetchConversation(id: conversationId) else { return [] }
        return convo.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { record in
                StoredMessage(
                    id: record.id,
                    role: record.role,
                    content: record.content,
                    createdAt: record.createdAt
                )
            }
    }

    public func append(_ message: StoredMessage, to conversationId: UUID) {
        guard let convo = fetchConversation(id: conversationId) else { return }
        let record = MessageRecord(
            id: message.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt
        )
        record.conversation = convo
        convo.messages.append(record)
        convo.updatedAt = Date()
        try? context.save()
    }

    public func deleteAll() {
        // Only delete conversations — the `.cascade` relationship rule
        // on `ConversationRecord.messages` removes their messages too.
        // Deleting messages explicitly alongside would race against the
        // cascade and triggered optimistic-locking failures on iOS 17.
        do {
            try context.delete(model: ConversationRecord.self)
            try context.save()
        } catch {
            // Swallow — "start over" should never fail the UI even if
            // the deletion is partial. The next session will still be
            // clean from the user's perspective because the session
            // id is regenerated in Keychain.
        }
    }

    // MARK: - Private

    private func fetchConversation(id: UUID) -> ConversationRecord? {
        var descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
