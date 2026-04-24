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
            sessionId: "sid",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: nil,
            difficulty: nil,
            suggestSummary: nil
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
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

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
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
            sessionId: "sid",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: nil,
            difficulty: nil,
            suggestSummary: nil
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

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if case .idle = vm.phase { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.content == "ok")
    }
}
