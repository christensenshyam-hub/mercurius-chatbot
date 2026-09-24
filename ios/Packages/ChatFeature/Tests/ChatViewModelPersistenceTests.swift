import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit
@testable import PersistenceKit

// Note: FakeChatClient and FakeModeClient are defined in
// ChatViewModelTests.swift / ChatViewModelModeTests.swift and are
// visible in the same test target.

@Suite("ChatViewModel + ChatStore integration")
@MainActor
struct ChatViewModelPersistenceTests {

    @Test("Init with an empty store creates a new conversation; no hydrated messages")
    func emptyStoreInit() {
        let store = InMemoryChatStore()
        let vm = ChatViewModel(
            chatClient: FakeChatClient(),
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )
        #expect(vm.messages.isEmpty)
        #expect(store.latestConversationId() != nil)  // one was lazily created
    }

    @Test("Init with pre-populated store hydrates messages in order")
    func hydratesFromStore() {
        let store = InMemoryChatStore()
        let convoId = store.createConversation(mode: .socratic)
        let t0 = Date()
        store.append(
            StoredMessage(id: UUID(), role: "user", content: "hi", createdAt: t0),
            to: convoId
        )
        store.append(
            StoredMessage(id: UUID(), role: "assistant", content: "hey", createdAt: t0.addingTimeInterval(1)),
            to: convoId
        )

        let vm = ChatViewModel(
            chatClient: FakeChatClient(),
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )

        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "hi")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "hey")
    }

    @Test("Messages with unknown roles in the store are skipped, not crashes")
    func ignoresUnknownRoles() {
        let store = InMemoryChatStore()
        let convoId = store.createConversation(mode: .socratic)
        store.append(
            StoredMessage(id: UUID(), role: "robot", content: "bleep", createdAt: Date()),
            to: convoId
        )
        let vm = ChatViewModel(
            chatClient: FakeChatClient(),
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )
        #expect(vm.messages.isEmpty)
    }

    @Test("Sending persists the user message and the finalized assistant reply")
    func sendPersistsBothMessages() async throws {
        let store = InMemoryChatStore()
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "Hello!",
            mode: "socratic",
            streak: nil
        )
        client.outcome = .events([.delta(text: "Hel"), .delta(text: "lo!"), .complete(sample)])

        let vm = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )

        vm.draft = "Hi"
        vm.send()

        // Wait for the stream to settle.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .idle = vm.phase { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard let convoId = store.latestConversationId() else {
            Issue.record("No conversation created")
            return
        }
        let persisted = store.loadMessages(conversationId: convoId)
        #expect(persisted.count == 2, "Expected user + assistant messages, got \(persisted.count)")
        #expect(persisted.first?.role == "user")
        #expect(persisted.first?.content == "Hi")
        #expect(persisted.last?.role == "assistant")
        #expect(persisted.last?.content == "Hello!")
    }

    @Test("Transport failure still persists the user message so retry works")
    func persistsUserMessageOnFailure() async throws {
        let store = InMemoryChatStore()
        let client = FakeChatClient()
        client.outcome = .failure(APIError.offline)

        let vm = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )

        vm.draft = "Hi"
        vm.send()

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .failed = vm.phase { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard let convoId = store.latestConversationId() else {
            Issue.record("No conversation")
            return
        }
        let persisted = store.loadMessages(conversationId: convoId)
        // User message persists; no assistant message persists because
        // the failure happened before we finalized one.
        #expect(persisted.count == 1)
        #expect(persisted.first?.role == "user")
    }

    @Test("Without a store, sending works exactly as before (no persistence)")
    func worksWithoutStore() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "ok",
            mode: "socratic",
            streak: nil
        )
        client.outcome = .events([.complete(sample)])

        let vm = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" }
            // no store
        )

        vm.draft = "Hi"
        vm.send()

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .idle = vm.phase { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "ok")
    }
}

// MARK: - startNewConversation after the active record is deleted

/// `startNewConversation()` reuses the active record only while it is BOTH
/// empty and still in the store. After `deleteAll()` (Settings "Delete my
/// data" / "Reset this device only") or History deleting the active row, the
/// old id points at nothing and every later `append` would be dropped.
///
/// The scenarios run against both production-shaped stores (SwiftData's
/// fetch-by-id must agree with the in-memory dictionary) from two suites
/// below, because only the SwiftData one has to be skipped on CI.
@MainActor
private enum StartNewConversationScenarios {

    static func makeModel(store: ChatStore, client: FakeChatClient) -> ChatViewModel {
        ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )
    }

    /// Send one "Hello" turn and wait for the streamed "Hi!" reply to settle.
    static func sendTurn(_ vm: ChatViewModel, client: FakeChatClient) async throws {
        let reply = ChatResponse(reply: "Hi!", mode: "socratic")
        client.outcome = .events([.delta(text: "Hi!"), .complete(reply)])
        vm.draft = "Hello"
        vm.send()

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if case .idle = vm.phase { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Stream did not settle")
    }

    static func deleteAllThenNewConversation(store: ChatStore) async throws {
        let client = FakeChatClient()
        let vm = makeModel(store: store, client: client)   // hydrates → lazily-created empty record
        let staleId = try #require(vm.conversationId, "no active record after hydrate")

        store.deleteAll()
        #expect(store.loadConversation(conversationId: staleId) == nil)

        vm.startNewConversation()
        let freshId = try #require(vm.conversationId, "no active record after New Chat")
        #expect(freshId != staleId, "kept the id of an erased record")

        try await sendTurn(vm, client: client)
        #expect(store.loadMessages(conversationId: freshId).map(\.content) == ["Hello", "Hi!"])
        #expect(store.listConversations().count == 1)
    }

    static func deleteActiveRowThenSend(store: ChatStore) async throws {
        let client = FakeChatClient()
        let vm = makeModel(store: store, client: client)
        let staleId = try #require(vm.conversationId)

        vm.deleteConversation(id: staleId)
        let freshId = try #require(vm.conversationId)
        #expect(freshId != staleId, "kept the id of the deleted row")
        #expect(store.loadConversation(conversationId: freshId) != nil)

        try await sendTurn(vm, client: client)
        #expect(store.loadMessages(conversationId: freshId).count == 2)
        #expect(store.listConversations().count == 1)
    }

    static func repeatedNewChatDoesNotLitter(store: ChatStore) throws {
        let vm = makeModel(store: store, client: FakeChatClient())
        let id = try #require(vm.conversationId)

        vm.startNewConversation()
        vm.startNewConversation()

        #expect(vm.conversationId == id, "minted a new record for an empty thread")
        #expect(store.listConversations().count == 1)
    }
}

@Suite("ChatViewModel.startNewConversation after the active record is deleted — InMemoryChatStore")
@MainActor
struct ChatViewModelStartNewConversationInMemoryTests {

    @Test("deleteAll() then startNewConversation(): the next turn persists into a live record")
    func deleteAllThenNewConversation() async throws {
        try await StartNewConversationScenarios.deleteAllThenNewConversation(store: InMemoryChatStore())
    }

    @Test("History deleting the active empty row: the next turn persists")
    func deleteActiveRowThenSend() async throws {
        try await StartNewConversationScenarios.deleteActiveRowThenSend(store: InMemoryChatStore())
    }

    @Test("Repeated New Chat on an existing empty record leaves exactly one record")
    func repeatedNewChatDoesNotLitter() throws {
        try StartNewConversationScenarios.repeatedNewChatDoesNotLitter(store: InMemoryChatStore())
    }
}

/// Same skip as PersistenceKit's own SwiftData suite: under `swift test` on
/// GitHub-hosted macOS runners SwiftData's `ModelContainer` fatals with
/// "Unable to determine Bundle Name", even in-memory. Works locally and in
/// the simulator test host.
private let isRunningUnderCI: Bool = ProcessInfo.processInfo.environment["CI"] == "true"

@Suite(
    "ChatViewModel.startNewConversation after the active record is deleted — SwiftDataChatStore",
    .disabled(if: isRunningUnderCI, "SwiftData ModelContainer fatals under swift test on CI (Xcode 16.2). Covered by the xcodebuild simulator run instead.")
)
@MainActor
struct ChatViewModelStartNewConversationSwiftDataTests {

    @Test("deleteAll() then startNewConversation(): the next turn persists into a live record")
    func deleteAllThenNewConversation() async throws {
        try await StartNewConversationScenarios.deleteAllThenNewConversation(store: try SwiftDataChatStore.inMemory())
    }

    @Test("History deleting the active empty row: the next turn persists")
    func deleteActiveRowThenSend() async throws {
        try await StartNewConversationScenarios.deleteActiveRowThenSend(store: try SwiftDataChatStore.inMemory())
    }

    @Test("Repeated New Chat on an existing empty record leaves exactly one record")
    func repeatedNewChatDoesNotLitter() throws {
        try StartNewConversationScenarios.repeatedNewChatDoesNotLitter(store: try SwiftDataChatStore.inMemory())
    }
}
