import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit
@testable import PersistenceKit

// MARK: - Controllable chat client
//
// The existing `FakeChatClient` (in ChatViewModelTests.swift) yields all
// events in a tight Task loop, so by the time the consumer observes state
// the stream has already completed. That's fine for final-state assertions
// but wrong for **intermediate** ones: "does the assistant bubble grow
// incrementally?", "does phase transition .sending → .streaming on the
// first delta?", "does cancel() interrupt an in-flight stream?".
//
// `ControllableChatClient` gives tests explicit control over when each
// event arrives. The test emits one event, polls until the view model
// observes it, emits the next, and so on.

/// A ChatStreaming stub whose event stream is driven event-by-event from
/// the test.
///
/// All control methods (`emit`, `finish`, `fail`) are `async` because a
/// freshly-spawned streaming task hasn't yet subscribed to the stream at
/// the moment `send()` returns. Each control method internally polls for
/// the continuation to exist before acting — otherwise yielded events
/// would be silently dropped.
final class ControllableChatClient: ChatStreaming, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation?
    private(set) var callCount: Int = 0

    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        lock.lock()
        callCount += 1
        lock.unlock()
        return AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    private func readyContinuation(
        timeout: Duration = .seconds(2)
    ) async -> AsyncThrowingStream<ChatStreamEvent, Error>.Continuation? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            lock.lock()
            if let cont = continuation {
                lock.unlock()
                return cont
            }
            lock.unlock()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    /// Emit a single event to the current stream.
    func emit(_ event: ChatStreamEvent) async {
        guard let cont = await readyContinuation() else {
            Issue.record("ControllableChatClient.emit: continuation never became ready")
            return
        }
        cont.yield(event)
        // Yield so the consuming for-await loop can pick up the event
        // before the test's next assertion runs.
        await Task.yield()
    }

    /// Close the stream cleanly (no terminal event).
    func finish() async {
        guard let cont = await readyContinuation() else {
            Issue.record("ControllableChatClient.finish: continuation never became ready")
            return
        }
        lock.lock()
        continuation = nil
        lock.unlock()
        cont.finish()
        await Task.yield()
    }

    /// Close the stream with an error (transport-level failure, not a
    /// `streamError` event).
    func fail(with error: Error) async {
        guard let cont = await readyContinuation() else {
            Issue.record("ControllableChatClient.fail: continuation never became ready")
            return
        }
        lock.lock()
        continuation = nil
        lock.unlock()
        cont.finish(throwing: error)
        await Task.yield()
    }
}

// MARK: - Test helpers

@MainActor
private func makeModel(
    chat: ControllableChatClient,
    mode: FakeModeClient = FakeModeClient(),
    sessionId: String = "test-session"
) -> ChatViewModel {
    ChatViewModel(
        chatClient: chat,
        modeClient: mode,
        sessionIdProvider: { sessionId }
    )
}

/// Poll until `condition()` holds, or `Issue.record` on timeout.
/// Lets tests wait for the view model to pick up events without sleeping
/// for a fixed interval on every call (flaky under load).
@MainActor
private func waitFor(
    _ label: String,
    timeout: Duration = .seconds(2),
    condition: @escaping () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timeout waiting for: \(label)")
}

private func sampleComplete(
    reply: String = "Hi there!",
    mode: String = "socratic",
    unlocked: Bool = false,
    justUnlocked: Bool? = nil
) -> ChatStreamEvent {
    .complete(
        ChatResponse(
            reply: reply,
            sessionId: "test-session",
            mode: mode,
            unlocked: unlocked,
            justUnlocked: justUnlocked,
            streak: 1,
            difficulty: 1,
            suggestSummary: nil
        )
    )
}

// MARK: - Streaming lifecycle

@Suite("ChatViewModel streaming lifecycle")
@MainActor
struct StreamingLifecycleTests {

    @Test("Phase transitions: idle → sending → streaming → idle")
    func phaseTransitions() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        #expect(model.phase == .idle)

        model.draft = "Hello"
        model.send()
        // After send() returns the task hasn't necessarily run yet, but
        // the synchronous state update must already be .sending.
        #expect(model.phase == .sending)
        #expect(model.messages.count == 2)  // user + placeholder

        // First delta transitions sending → streaming.
        await client.emit(.delta(text: "Hi"))
        await waitFor("phase == .streaming") { model.phase == .streaming }

        // Complete ends the stream; phase returns to idle.
        await client.emit(sampleComplete(reply: "Hi there!"))
        await waitFor("phase == .idle") { model.phase == .idle }
    }

    @Test("Assistant content grows incrementally as deltas arrive")
    func incrementalContent() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        // Placeholder starts empty.
        await waitFor("placeholder exists") {
            model.messages.last?.role == .assistant
        }
        #expect(model.messages.last?.content == "")

        await client.emit(.delta(text: "Hel"))
        await waitFor("delta 1 observed") { model.messages.last?.content == "Hel" }

        await client.emit(.delta(text: "lo, "))
        await waitFor("delta 2 observed") { model.messages.last?.content == "Hello, " }

        await client.emit(.delta(text: "world!"))
        await waitFor("delta 3 observed") { model.messages.last?.content == "Hello, world!" }

        await client.emit(sampleComplete(reply: "Hello, world!"))
        await waitFor("stream finalized") { model.phase == .idle }
    }

    @Test("Server reply overrides concatenated deltas on finalize")
    func serverReplyWinsOverDeltas() async {
        // Servers sometimes drop a token during streaming. The contract:
        // on `.complete`, use the full reply rather than the concatenated
        // deltas so users see the authoritative content.
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        await client.emit(.delta(text: "Hel"))
        await client.emit(.delta(text: "lo"))   // deltas add up to "Hello"
        await client.emit(sampleComplete(reply: "Hello, world!"))  // server has more

        await waitFor("phase == .idle") { model.phase == .idle }
        #expect(model.messages.last?.content == "Hello, world!")
    }

    @Test("Stream closes cleanly after deltas without a .complete event")
    func streamClosedWithoutCompleteKeepsDeltaContent() async {
        // Edge case: server stream drops the connection mid-response after
        // emitting some deltas but never sending `.complete`. The view model
        // should commit whatever was streamed rather than treating it as
        // a failure — the user has visible content already.
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        await client.emit(.delta(text: "Partial"))
        await client.emit(.delta(text: " response"))
        await waitFor("deltas rendered") {
            model.messages.last?.content == "Partial response"
        }

        await client.finish()
        await waitFor("finalized after close") { model.phase == .idle }
        #expect(model.messages.last?.content == "Partial response")
        #expect(model.messages.last?.status == .idle)
    }

    @Test("Stream closes with no deltas and no complete → retryable error")
    func streamClosedWithNoContentIsRetryableError() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        await client.finish()
        await waitFor("phase becomes .failed") {
            if case .failed = model.phase { return true }
            return false
        }
        guard case .failed(_, let isRetryable) = model.phase else {
            Issue.record("Expected .failed phase")
            return
        }
        #expect(isRetryable, "Connection drops should be retryable")
    }
}

// MARK: - Cancel behavior

@Suite("ChatViewModel cancel behavior")
@MainActor
struct CancelTests {

    @Test("cancel() during streaming marks the assistant bubble failed")
    func cancelDuringStreaming() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        await client.emit(.delta(text: "Starting"))
        await waitFor("first delta observed") {
            model.messages.last?.content == "Starting"
        }

        model.cancel()

        // cancel() synchronously sets phase to .failed.
        if case .failed(let reason, let retryable) = model.phase {
            #expect(reason == "Cancelled.")
            #expect(retryable)
        } else {
            Issue.record("Expected .failed after cancel(), got \(model.phase)")
        }
        // And the assistant bubble keeps whatever content was streamed,
        // but its status is failed.
        #expect(model.messages.last?.role == .assistant)
        if case .failed = model.messages.last?.status {
            // expected
        } else {
            Issue.record("Expected assistant status .failed after cancel()")
        }
    }

    @Test("cancel() while idle is harmless")
    func cancelWhileIdleDoesNothingBad() {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        // No crash, no spurious state change.
        model.cancel()
        // `cancel()` currently always sets phase to .failed even from
        // idle — document that by asserting it, so if we ever guard
        // against it (better UX), the test catches the change.
        if case .failed = model.phase {
            // current contract
        } else {
            Issue.record("Expected cancel() from idle to produce a .failed sentinel — if this test fails, the contract changed intentionally and should be updated.")
        }
    }
}

// MARK: - Edge cases

@Suite("ChatViewModel edge cases")
@MainActor
struct EdgeCaseTests {

    @Test("Second send() while streaming is ignored (no duplicate request)")
    func concurrentSendIgnored() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        model.draft = "First"
        model.send()
        #expect(model.phase == .sending)

        // Second send while the first is still in flight — the
        // synchronous phase guard in `send()` should short-circuit this.
        model.draft = "Second"
        model.send()

        // Verify synchronous guard worked: phase unchanged, and the
        // second draft never became a user message.
        #expect(model.phase == .sending)
        let userMessages = model.messages.filter { $0.role == .user }
        #expect(userMessages.count == 1)
        #expect(userMessages.first?.content == "First")

        // Drive the stream to completion. `emit()` only returns once
        // the continuation is live — i.e. after streamChat() has been
        // called. That's the sync point we need to assert on callCount.
        await client.emit(sampleComplete(reply: "ok"))
        await waitFor("phase idle") { model.phase == .idle }

        #expect(
            client.callCount == 1,
            "Second send() must not trigger a second streamChat call"
        )
    }

    @Test("Send after a failed attempt removes the failed assistant bubble")
    func sendAfterFailureDropsFailedBubble() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        // First attempt fails.
        model.draft = "First"
        model.send()
        await client.fail(with: APIError.offline)
        await waitFor("first attempt fails") {
            if case .failed = model.phase { return true }
            return false
        }
        // We should have user + failed assistant bubble.
        #expect(model.messages.count == 2)
        if case .failed = model.messages.last?.status {
            // expected
        } else {
            Issue.record("Expected failed assistant after transport error")
        }

        // Second attempt: fresh send, should drop the failed assistant
        // and append a new user + placeholder pair.
        model.draft = "Second"
        model.send()

        // Now we expect: First (user), Second (user), placeholder (assistant)
        let roles = model.messages.map(\.role)
        #expect(roles == [.user, .user, .assistant],
                "Expected the failed assistant to be removed and a new pair appended")
        #expect(model.messages[1].content == "Second")

        // Cleanup
        await client.emit(sampleComplete(reply: "ok"))
        await waitFor("phase idle") { model.phase == .idle }
    }

    @Test("Retry after a transient failure fires a fresh stream")
    func retryFiresFreshStream() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        // First attempt: fail.
        model.draft = "Ping"
        model.send()
        await client.fail(with: APIError.timeout)
        await waitFor("first attempt fails") {
            if case .failed = model.phase { return true }
            return false
        }
        #expect(client.callCount == 1)

        // Retry: should call streamChat again with the preserved user
        // message "Ping".
        model.retry()
        await waitFor("second stream starts") { client.callCount == 2 }

        await client.emit(sampleComplete(reply: "Pong"))
        await waitFor("retry completes") { model.phase == .idle }
        #expect(model.messages.last?.content == "Pong")
    }
}

// MARK: - Server-driven state

@Suite("ChatViewModel server-driven state")
@MainActor
struct ServerDrivenStateTests {

    @Test("complete event with unlocked=true flips isUnlocked")
    func unlockOnComplete() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        #expect(!model.isUnlocked)

        model.draft = "Pass the test?"
        model.send()
        await client.emit(sampleComplete(reply: "Yes.", unlocked: true, justUnlocked: true))

        await waitFor("phase idle") { model.phase == .idle }
        #expect(model.isUnlocked, "Server's unlocked=true should flip the flag on the client")
    }

    @Test("complete event with a different mode updates currentMode")
    func modeChangedByServer() async {
        // Curriculum lessons can make the server switch modes on the client's
        // behalf (e.g. lesson starter kicks debate mode). The client reflects
        // that by reading the mode out of the complete event.
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        #expect(model.currentMode == .socratic)

        model.draft = "Start debate"
        model.send()
        await client.emit(sampleComplete(reply: "Debate opened.", mode: "debate"))

        await waitFor("phase idle") { model.phase == .idle }
        #expect(model.currentMode == .debate)
    }

    @Test("Unknown mode string from server is ignored (no crash, no change)")
    func unknownModeIgnored() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        model.draft = "Hi"
        model.send()
        await client.emit(sampleComplete(reply: "ok", mode: "zen-master-mode"))

        await waitFor("phase idle") { model.phase == .idle }
        #expect(model.currentMode == .socratic, "Unknown modes mustn't silently unset the current one")
    }
}

// MARK: - startNewConversation

@Suite("ChatViewModel.startNewConversation")
@MainActor
struct StartNewConversationTests {

    @Test("Clears messages, draft, and returns phase to .idle")
    func clearsState() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        // Put the model into a non-idle state with messages.
        model.draft = "Hi"
        model.send()
        await client.emit(sampleComplete(reply: "Hello!"))
        await waitFor("first exchange done") { model.phase == .idle }
        #expect(model.messages.count == 2)
        model.draft = "drafting something"  // unsent draft
        #expect(model.phase == .idle)

        model.startNewConversation()

        #expect(model.messages.isEmpty)
        #expect(model.draft.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("Mode and unlock state are preserved")
    func preservesPreferences() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        // Mark unlocked + switch mode via a server reply.
        model.draft = "Hi"
        model.send()
        await client.emit(sampleComplete(reply: "ok", mode: "debate", unlocked: true))
        await waitFor("first exchange done") { model.phase == .idle }
        #expect(model.currentMode == .debate)
        #expect(model.isUnlocked)

        model.startNewConversation()

        #expect(model.currentMode == .debate, "Mode should survive startNewConversation()")
        #expect(model.isUnlocked, "Unlock state should survive startNewConversation()")
    }

    @Test("Cancels an in-flight stream silently (no failure bubble)")
    func cancelsInFlightStream() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)

        model.draft = "Starting something"
        model.send()
        await client.emit(.delta(text: "Some"))
        await waitFor("first delta arrived") {
            model.messages.last?.content == "Some"
        }
        #expect(model.phase == .streaming)

        model.startNewConversation()

        // No "Cancelled." bubble should remain — unlike `cancel()`,
        // this is a clean slate, not a stop button.
        #expect(model.messages.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("With a store, creates a new conversation record")
    func createsNewConversation() async {
        let store = InMemoryChatStore()
        let client = ControllableChatClient()
        let model = ChatViewModel(
            chatClient: client,
            modeClient: FakeModeClient(),
            sessionIdProvider: { "sid" },
            store: store
        )

        // Send a message to persist something in the first conversation.
        model.draft = "first convo"
        model.send()
        await client.emit(sampleComplete(reply: "ok"))
        await waitFor("first exchange done") { model.phase == .idle }

        let firstConvoId = store.latestConversationId()
        #expect(firstConvoId != nil)
        #expect(store.loadMessages(conversationId: firstConvoId!).count == 2)

        model.startNewConversation()

        let secondConvoId = store.latestConversationId()
        #expect(secondConvoId != nil)
        #expect(secondConvoId != firstConvoId, "A new conversation should be created")
        #expect(store.loadMessages(conversationId: secondConvoId!).isEmpty)
        // First conversation is preserved in history.
        #expect(store.loadMessages(conversationId: firstConvoId!).count == 2)
    }

    @Test("Without a store, still clears state without crashing")
    func noStoreIsFine() async {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)  // no store

        model.draft = "Hi"
        model.send()
        await client.emit(sampleComplete(reply: "ok"))
        await waitFor("first exchange done") { model.phase == .idle }

        model.startNewConversation()
        #expect(model.messages.isEmpty)
        #expect(model.phase == .idle)
    }
}

// MARK: - SSE parser → ChatViewModel round-trip
//
// These tests wire the real `SSEParser` + `parseChatEvent` up to the real
// `ChatViewModel`, driven by raw SSE payload strings that match the server's
// wire format. They catch contract drift between the parser and the view
// model — e.g. a server adding a new required field to the `complete` event
// that breaks deserialization, or the view model no longer honoring `unlocked`.

/// Feed raw SSE payload strings through `parseChatEvent` and emit the
/// resulting events to a `ControllableChatClient`.
@MainActor
private func driveFromSSEPayloads(
    _ payloads: [String],
    into client: ControllableChatClient
) async throws {
    for payload in payloads {
        if let event = try parseChatEvent(from: payload) {
            await client.emit(event)
        }
    }
}

@Suite("SSE parser → ChatViewModel round-trip")
@MainActor
struct SSERoundTripTests {

    @Test("Raw SSE payloads flow through parser into the view model")
    func endToEndDelivery() async throws {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hello"
        model.send()

        // Mirrors the server's wire format: two deltas and a complete.
        let payloads = [
            #"{"type":"delta","text":"Hi"}"#,
            #"{"type":"delta","text":" there!"}"#,
            #"""
            {"type":"complete","reply":"Hi there!","sessionId":"test-session","mode":"socratic","unlocked":false,"streak":1,"difficulty":1}
            """#,
        ]
        try await driveFromSSEPayloads(payloads, into: client)

        await waitFor("stream finalized") { model.phase == .idle }
        #expect(model.messages.last?.content == "Hi there!")
        #expect(model.messages.last?.role == .assistant)
        #expect(model.messages.last?.status == .idle)
    }

    @Test("Round-trip surfaces an unlock from the server")
    func roundTripUnlocks() async throws {
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        #expect(!model.isUnlocked)

        model.draft = "I passed!"
        model.send()

        let payloads = [
            #"""
            {"type":"complete","reply":"Direct Mode unlocked.","sessionId":"test-session","mode":"socratic","unlocked":true,"justUnlocked":true,"streak":2,"difficulty":1}
            """#,
        ]
        try await driveFromSSEPayloads(payloads, into: client)

        await waitFor("phase idle") { model.phase == .idle }
        #expect(model.isUnlocked, "The `unlocked:true` field must flow from server → parser → view model")
    }

    @Test("`[DONE]` terminator between events is tolerated")
    func doneTerminatorNoOp() async throws {
        // The server sometimes appends `data: [DONE]` before closing. The
        // parser returns nil for that payload — the view model should
        // neither crash nor treat it as an error.
        let client = ControllableChatClient()
        let model = makeModel(chat: client)
        model.draft = "Hi"
        model.send()

        // `[DONE]` parses to nil; skipped silently. Then a real complete.
        if let ev = try parseChatEvent(from: "[DONE]") {
            Issue.record("[DONE] should parse to nil, got \(ev)")
        }
        let payloads = [
            #"{"type":"delta","text":"ok"}"#,
            #"""
            {"type":"complete","reply":"ok","sessionId":"test-session","mode":"socratic","unlocked":false,"streak":1,"difficulty":1}
            """#,
        ]
        try await driveFromSSEPayloads(payloads, into: client)

        await waitFor("phase idle") { model.phase == .idle }
        #expect(model.messages.last?.content == "ok")
    }
}
