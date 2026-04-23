import Testing
import Foundation
@testable import PersistenceKit

@Suite("InMemoryChatStore")
@MainActor
struct InMemoryChatStoreTests {

    @Test("latestConversationId is nil before any conversation is created")
    func initiallyEmpty() {
        let store = InMemoryChatStore()
        #expect(store.latestConversationId() == nil)
    }

    @Test("createConversation returns a fresh id each time")
    func createReturnsUniqueIds() {
        let store = InMemoryChatStore()
        let a = store.createConversation()
        let b = store.createConversation()
        #expect(a != b)
    }

    @Test("latestConversationId reflects the most recently touched conversation")
    func latestFollowsActivity() async {
        let store = InMemoryChatStore()
        let a = store.createConversation()
        // Slight delay so updatedAt differs; touching `b` via append
        // bumps its updatedAt.
        try? await Task.sleep(for: .milliseconds(5))
        let b = store.createConversation()
        #expect(store.latestConversationId() == b)

        try? await Task.sleep(for: .milliseconds(5))
        store.append(
            StoredMessage(id: UUID(), role: "user", content: "hi", createdAt: Date()),
            to: a
        )
        #expect(store.latestConversationId() == a)
    }

    @Test("Messages are returned chronologically")
    func messagesOrdered() {
        let store = InMemoryChatStore()
        let id = store.createConversation()
        let t0 = Date()
        let m1 = StoredMessage(id: UUID(), role: "user", content: "first", createdAt: t0.addingTimeInterval(2))
        let m2 = StoredMessage(id: UUID(), role: "user", content: "second", createdAt: t0.addingTimeInterval(1))
        let m3 = StoredMessage(id: UUID(), role: "assistant", content: "third", createdAt: t0.addingTimeInterval(3))
        // Insert out of order.
        store.append(m1, to: id)
        store.append(m2, to: id)
        store.append(m3, to: id)

        let loaded = store.loadMessages(conversationId: id)
        #expect(loaded.map(\.content) == ["second", "first", "third"])
    }

    @Test("append to an unknown conversation is a no-op (not a crash)")
    func appendToUnknownIsNoOp() {
        let store = InMemoryChatStore()
        let phantom = UUID()
        store.append(
            StoredMessage(id: UUID(), role: "user", content: "orphan", createdAt: Date()),
            to: phantom
        )
        #expect(store.loadMessages(conversationId: phantom).isEmpty)
        #expect(store.latestConversationId() == nil)
    }

    @Test("deleteAll clears everything")
    func deleteAllClears() {
        let store = InMemoryChatStore()
        let id = store.createConversation()
        store.append(
            StoredMessage(id: UUID(), role: "user", content: "x", createdAt: Date()),
            to: id
        )
        store.deleteAll()
        #expect(store.latestConversationId() == nil)
        #expect(store.loadMessages(conversationId: id).isEmpty)
    }
}

/// Under `swift test` on GitHub-hosted macOS runners (Xcode 16.2 at
/// time of writing), SwiftData's `ModelContainer(for:...)` fatals with
/// "Unable to determine Bundle Name" — even for `isStoredInMemoryOnly`.
/// The same code path works fine locally and under `xcodebuild test`
/// on the simulator (where the test host app provides a real bundle).
/// We skip on CI only — these behaviors are still exercised by the
/// xcodebuild MercuriusTests run on every CI invocation.
private let isRunningUnderCI: Bool = ProcessInfo.processInfo.environment["CI"] == "true"

@Suite(
    "SwiftDataChatStore (in-memory container)",
    .disabled(if: isRunningUnderCI, "SwiftData ModelContainer fatals under swift test on CI (Xcode 16.2). Covered by the xcodebuild simulator run instead.")
)
@MainActor
struct SwiftDataChatStoreTests {

    @Test("Round-trips conversations and messages")
    func basicRoundTrip() throws {
        let store = try SwiftDataChatStore.inMemory()
        let id = store.createConversation()
        #expect(store.latestConversationId() == id)

        let msg = StoredMessage(
            id: UUID(),
            role: "user",
            content: "hello",
            createdAt: Date()
        )
        store.append(msg, to: id)

        let loaded = store.loadMessages(conversationId: id)
        #expect(loaded.count == 1)
        #expect(loaded.first?.content == "hello")
        #expect(loaded.first?.role == "user")
    }

    @Test("deleteAll removes conversations and messages")
    func deleteAll() throws {
        let store = try SwiftDataChatStore.inMemory()
        let id = store.createConversation()
        store.append(
            StoredMessage(id: UUID(), role: "user", content: "x", createdAt: Date()),
            to: id
        )
        store.deleteAll()
        #expect(store.latestConversationId() == nil)
    }
}
