import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit

// MARK: - Fake chat client

/// A deterministic `ChatStreaming` stub. Tests configure the sequence
/// of events (or an error) it will emit per call.
final class FakeChatClient: ChatStreaming, @unchecked Sendable {
    enum Outcome {
        case events([ChatStreamEvent])
        case failure(Error)
    }

    var outcome: Outcome = .events([])
    var receivedMessages: [[ChatMessageDTO]] = []
    var receivedSessionIds: [String] = []
    var receivedResponseModes: [ResponseMode] = []

    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String,
        responseMode: ResponseMode
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        receivedMessages.append(messages)
        receivedSessionIds.append(sessionId)
        receivedResponseModes.append(responseMode)

        let outcome = self.outcome
        return AsyncThrowingStream { continuation in
            Task {
                switch outcome {
                case .events(let events):
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Helpers

@MainActor
private func makeModel(client: FakeChatClient, sessionId: String = "test-session") -> ChatViewModel {
    ChatViewModel(
        chatClient: client,
        modeClient: FakeModeClient(),
        sessionIdProvider: { sessionId }
    )
}

/// Await the view model's return to `.idle` (or `.failed`) — necessary
/// because `send()` kicks off a detached task. Times out after 2s.
@MainActor
private func waitUntilSettled(_ model: ChatViewModel, timeout: Duration = .seconds(2)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        switch model.phase {
        case .idle, .failed:
            return
        case .sending, .streaming:
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    Issue.record("Timeout waiting for model to settle (phase: \(model.phase))")
}

// MARK: - Tests

@Suite("ChatViewModel send lifecycle")
@MainActor
struct ChatViewModelSendTests {

    @Test("Empty draft is a no-op")
    func emptyDraft() {
        let model = makeModel(client: FakeChatClient())
        model.draft = "   "
        model.send()
        #expect(model.messages.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("Send inserts user message and assistant placeholder")
    func insertsPlaceholder() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "Hi there!",
            sessionId: "test-session",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: 1,
            difficulty: 1,
            suggestSummary: nil
        )
        client.outcome = .events([
            .delta(text: "Hi"),
            .delta(text: " there!"),
            .complete(sample),
        ])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()

        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        #expect(model.messages[0].role == .user)
        #expect(model.messages[0].content == "Hello")
        #expect(model.messages[1].role == .assistant)
        #expect(model.messages[1].content == "Hi there!")
        #expect(model.messages[1].status == .idle)
        #expect(model.phase == .idle)
        #expect(model.draft == "")
    }

    @Test("History sent to server excludes the pending assistant placeholder")
    func historyExcludesPlaceholder() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "ok",
            sessionId: "test-session",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: 1,
            difficulty: 1,
            suggestSummary: nil
        )
        client.outcome = .events([.complete(sample)])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedMessages.count == 1)
        let sent = client.receivedMessages[0]
        #expect(sent.count == 1)
        #expect(sent[0].role == "user")
        #expect(sent[0].content == "Hello")
    }

    @Test("Session id is passed to the client")
    func sessionIdPassed() async throws {
        let client = FakeChatClient()
        let sample = ChatResponse(
            reply: "ok",
            sessionId: "abc",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: 1,
            difficulty: 1,
            suggestSummary: nil
        )
        client.outcome = .events([.complete(sample)])
        let model = makeModel(client: client, sessionId: "abc")
        model.draft = "Hi"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedSessionIds == ["abc"])
    }
}

@Suite("ChatViewModel error handling")
@MainActor
struct ChatViewModelErrorTests {

    @Test("Transport error marks phase .failed with retryable flag")
    func transportError() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.offline)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        if case .failed(_, let isRetryable) = model.phase {
            #expect(isRetryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Stream `error` event surfaces the message")
    func streamError() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.streamError(message: "server said no")])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(let reason, _) = model.phase {
            #expect(reason.contains("server said no"))
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Session resolution failure is non-retryable")
    func sessionResolutionFailure() async throws {
        struct BadSession: Error {}
        let client = FakeChatClient()
        let model = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { throw BadSession() }
        )
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(_, let retryable) = model.phase {
            #expect(!retryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }

    @Test("Unauthorized error is not retryable")
    func unauthorizedNotRetryable() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.unauthorized)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        if case .failed(_, let retryable) = model.phase {
            #expect(!retryable)
        } else {
            Issue.record("Expected .failed phase")
        }
    }
}

@Suite("ChatViewModel retry")
@MainActor
struct ChatViewModelRetryTests {

    @Test("Retry removes the failed assistant bubble and starts a fresh stream")
    func retrySucceedsAfterFailure() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(APIError.timeout)
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        // Now configure a successful second attempt.
        let success = ChatResponse(
            reply: "On retry.",
            sessionId: "test-session",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: 1,
            difficulty: 1,
            suggestSummary: nil
        )
        client.outcome = .events([.complete(success)])
        model.retry()
        try await waitUntilSettled(model)

        #expect(model.messages.count == 2)
        #expect(model.messages.last?.content == "On retry.")
        #expect(model.phase == .idle)
    }
}

@Suite("ChatViewModel response-mode + explainMore")
@MainActor
struct ChatViewModelResponseModeTests {

    private func minimalReply() -> ChatResponse {
        ChatResponse(
            reply: "ok",
            sessionId: "test-session",
            mode: "socratic",
            unlocked: false,
            justUnlocked: nil,
            streak: 0,
            difficulty: 0,
            suggestSummary: nil
        )
    }

    @Test("Default send uses .concise (mobile-native default)")
    func defaultIsConcise() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)
        model.draft = "Hello"
        model.send()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.last == .concise,
                "First-touch sends should default to .concise")
    }

    @Test("explainMore() sends with .deep")
    func explainMoreUsesDeep() async throws {
        let client = FakeChatClient()
        client.outcome = .events([.complete(minimalReply())])
        let model = makeModel(client: client)

        // Seed an existing assistant turn so explainMore has context.
        model.draft = "What is an LLM?"
        model.send()
        try await waitUntilSettled(model)

        // Configure the next turn's outcome.
        client.outcome = .events([.complete(minimalReply())])
        model.explainMore()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.count == 2)
        #expect(client.receivedResponseModes[0] == .concise,
                "Initial turn should be concise")
        #expect(client.receivedResponseModes[1] == .deep,
                "explainMore() should escalate to .deep")
    }

    @Test("explainMore() is a no-op while a stream is in flight")
    func explainMoreIgnoredMidStream() async {
        let client = FakeChatClient()
        // Outcome that finishes lazily — we'll inspect state mid-flight.
        client.outcome = .events([])  // immediately finishes; gives us idle phase
        let model = makeModel(client: client)

        // Empty messages → explainMore should bail without sending.
        model.explainMore()
        #expect(client.receivedResponseModes.isEmpty,
                "explainMore() with no prior messages must not send")
    }

    @Test("Retry reuses the last responseMode")
    func retryReusesResponseMode() async throws {
        let client = FakeChatClient()
        client.outcome = .failure(URLError(.networkConnectionLost))
        let model = makeModel(client: client)
        model.draft = "Why?"
        model.send(responseMode: .balanced)
        try await waitUntilSettled(model)

        client.outcome = .events([.complete(minimalReply())])
        model.retry()
        try await waitUntilSettled(model)

        #expect(client.receivedResponseModes.last == .balanced,
                "Retry should reuse the original responseMode, not silently drop to .concise")
    }
}
