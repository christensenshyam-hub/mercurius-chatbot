import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit
@testable import PersistenceKit

// AUD-29: a reply cut off by a failure (a dropped stream, or Stop) that the
// student answers anyway — typing, tapping a [Q] option, or asking for more —
// instead of tapping Retry. The cut-off reply must stay in the thread and on
// the wire, so the model sees what it already said and the question being
// answered. A reply that failed before any text is still dropped.

private let lessonStarter = "[CURRICULUM: Unit 1, Lesson 1] Teach me what a token is."

/// A lesson reply that streamed a complete [Q] and then dropped.
private let cutLessonReply = """
Tokens are the pieces a model reads.

[Q]
What is a token?
A) A whole sentence
B) A chunk of text turned into a number
C) A stored copy of a word
ANS: B
[/Q]

Next, we'll look at
"""

@MainActor
private func makeModel(_ client: ControllableChatClient, store: ChatStore? = nil) -> ChatViewModel {
    ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                  sessionIdProvider: { "s" }, store: store, hydrateOnInit: false)
}

@MainActor
private func waitUntil(_ label: String, timeout: Duration = .seconds(10),
                       _ condition: @escaping () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timeout waiting for: \(label)")
}

@MainActor
private func isFailed(_ model: ChatViewModel) -> Bool {
    if case .failed = model.phase { return true }
    return false
}

/// Send `text`, stream `partial`, then drop the connection.
@MainActor
private func cutOff(_ model: ChatViewModel, _ client: ControllableChatClient,
                    after partial: String) async {
    await client.emit(.delta(text: partial))
    await waitUntil("partial text shown") { model.messages.last?.content == partial }
    await client.fail(with: APIError.connectionLost)
    await waitUntil("reply failed") { isFailed(model) }
}

@Suite("ChatViewModel cut-off replies (AUD-29)")
@MainActor
struct FailedReplyWireTests {

    @Test("Typing after a cut-off reply keeps it on the wire as Merc's turn")
    func typedAnswerKeepsCutOffReply() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "What is a token?"
        model.send()
        await cutOff(model, client, after: "A token is a chunk of text. Which of these is one: ")

        model.draft = "B"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire[1].content == "A token is a chunk of text. Which of these is one:")
        #expect(wire[2].content == "B")

        // Still in the thread, marked cut off, not failed.
        #expect(model.messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(model.messages[1].status == .interrupted)
        #expect(model.messages[1].content == "A token is a chunk of text. Which of these is one:")

        await client.emit(.complete(ChatResponse(reply: "Right.", mode: "socratic")))
        await waitUntil("settled") { model.phase == .idle }
        #expect(model.messages[1].status == .interrupted)
    }

    @Test("The audit repro: a lesson [Q] cut off, then 'B' — wire[1] is the cut-off reply")
    func lessonRepro() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await cutOff(model, client, after: cutLessonReply)

        model.draft = "B"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire[0].content.hasPrefix(lessonStarter))
        #expect(wire[1].content == cutLessonReply.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(wire[1].content.contains("[Q]") && wire[1].content.contains("[/Q]"))
        #expect(wire[2].content == "[CURRICULUM: Unit 1, Lesson 1] B")
    }

    @Test("Tapping an option on a cut-off reply's complete [Q] sends the pick and keeps the reply")
    func quizPickAfterCutOff() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await cutOff(model, client, after: cutLessonReply)

        model.sendQuickReply("I picked B) A chunk of text turned into a number")
        await waitUntil("pick sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire[1].content.contains("[/Q]"))
        #expect(wire[2].content == "[CURRICULUM: Unit 1, Lesson 1] I picked B) A chunk of text turned into a number")
        #expect(model.messages.first?.status == .interrupted)
    }

    @Test("Stop mid-reply, then typing, keeps what had streamed")
    func stopThenTypeKeepsPartial() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "Explain RLHF"
        model.send()
        await client.emit(.delta(text: "RLHF means people rate"))
        await waitUntil("partial text shown") { model.messages.last?.content == "RLHF means people rate" }
        model.cancel()

        model.draft = "Go on"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.content) == ["Explain RLHF", "RLHF means people rate", "Go on"])
        #expect(model.messages[1].status == .interrupted)
    }

    @Test("A reply that failed before any text is still dropped when the student types")
    func emptyFailureIsDropped() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "First"
        model.send()
        await client.fail(with: APIError.connectionLost)
        await waitUntil("reply failed") { isFailed(model) }

        model.draft = "Second"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }

        #expect(model.messages.map(\.role) == [.user, .user, .assistant])
        #expect(client.receivedMessages.last?.map(\.role) == ["user", "user"])
        #expect(client.receivedMessages.last?.contains { $0.role == "assistant" } == false)
    }

    @Test("A failed reply of only whitespace counts as empty")
    func whitespaceFailureIsDropped() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "First"
        model.send()
        await cutOff(model, client, after: "  \n")

        model.draft = "Second"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }
        #expect(client.receivedMessages.last?.map(\.role) == ["user", "user"])
    }

    @Test("Explain more after a cut-off reply expands on it rather than dropping it")
    func explainMoreKeepsPartial() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "What is a token?"
        model.send()
        await cutOff(model, client, after: "A token is a chunk of text.")

        model.explainMore()
        await waitUntil("explain-more request sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        #expect(wire[1].content == "A token is a chunk of text.")
        #expect(wire[2].content.hasPrefix("Explain more"))
        #expect(model.messages.map(\.role) == [.user, .assistant, .assistant])
        #expect(model.messages[1].status == .interrupted)
    }

    @Test("Retry still replaces a cut-off reply with a fresh one")
    func retryStillRegenerates() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.draft = "What is a token?"
        model.send()
        await cutOff(model, client, after: "A token is")

        model.retry()
        await waitUntil("retry sent") { client.callCount == 2 }

        #expect(client.receivedMessages.last?.map(\.content) == ["What is a token?"])
        #expect(model.messages.map(\.role) == [.user, .assistant])
        #expect(model.messages.last?.status == .streaming)
    }

    @Test("A kept cut-off reply is saved with the thread, so a relaunch replays it too")
    func cutOffReplyIsPersisted() async {
        let store = InMemoryChatStore()
        let client = ControllableChatClient()
        let model = ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                                  sessionIdProvider: { "s" }, store: store)
        model.draft = "What is a token?"
        model.send()
        await cutOff(model, client, after: "A token is a chunk of text.")
        model.draft = "Got it"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }
        await client.emit(.complete(ChatResponse(reply: "Nice.", mode: "socratic")))
        await waitUntil("settled") { model.phase == .idle }

        let relaunched = ChatViewModel(chatClient: FakeChatClient(), modeClient: FakeModeClient(),
                                       sessionIdProvider: { "s" }, store: store)
        #expect(relaunched.messages.map(\.content)
                == ["What is a token?", "A token is a chunk of text.", "Got it", "Nice."])
    }

    @Test("A lesson's cut-off reply loses any control marker before it is kept")
    func lessonPartialIsScrubbed() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: lessonStarter, lessonId: "u1_l1")
        await client.emit(.delta(text: "Good work so far.\n[LESSON_COMPLETE]\n"))
        await waitUntil("partial text shown") { model.messages.last?.content.isEmpty == false }
        await client.fail(with: APIError.connectionLost)
        await waitUntil("reply failed") { isFailed(model) }

        model.draft = "ok"
        model.send()
        await waitUntil("second request sent") { client.callCount == 2 }
        #expect(client.receivedMessages.last?[1].content == "Good work so far.")
    }
}

@Suite("MessageBubbleView failed replies (AUD-29)")
struct FailedReplyBubbleTests {

    @Test("A reply that failed before any text draws no bubble — only its error line")
    func emptyFailureDrawsNoBubble() {
        let empty = ChatMessage(role: .assistant, content: "", status: .failed(reason: "Connection lost."))
        let blank = ChatMessage(role: .assistant, content: " \n", status: .failed(reason: "Connection lost."))
        #expect(MessageBubbleView.isEmptyFailure(empty))
        #expect(MessageBubbleView.isEmptyFailure(blank))
        #expect(!MessageBubbleView.drawsBubble(empty))
        #expect(!MessageBubbleView.drawsBubble(blank))
    }

    @Test("Every other message keeps its bubble")
    func otherMessagesDrawBubbles() {
        let partial = ChatMessage(role: .assistant, content: "A token is", status: .failed(reason: "Cancelled."))
        let typing = ChatMessage(role: .assistant, content: "", status: .streaming)
        let cutOff = ChatMessage(role: .assistant, content: "A token is", status: .interrupted)
        let user = ChatMessage(role: .user, content: "Hi")
        let photoOnly = ChatMessage(role: .user, content: "")
        #expect(MessageBubbleView.drawsBubble(partial))
        #expect(MessageBubbleView.drawsBubble(typing), "the thinking indicator lives in the bubble")
        #expect(MessageBubbleView.drawsBubble(cutOff))
        #expect(MessageBubbleView.drawsBubble(user))
        #expect(!MessageBubbleView.drawsBubble(photoOnly))
        #expect(!MessageBubbleView.isEmptyFailure(typing))
    }
}
