import Testing
import Foundation
@testable import ChatFeature
@testable import NetworkingKit
@testable import PersistenceKit

// A Basics lesson on the wire (docs/basics/SERVER.md's client contract), its
// practice-line chip, and the words its screens use.

private let basicsStarter = "[BASICS: Unit 1, Lesson 1] Teach me what an AI chatbot is, in plain words. Keep it short, then let me try one."
private let completionContract = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line."

@MainActor
private func makeModel(_ client: ControllableChatClient) -> ChatViewModel {
    ChatViewModel(chatClient: client, modeClient: FakeModeClient(),
                  sessionIdProvider: { "s" }, store: nil, hydrateOnInit: false)
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

@Suite("Basics lesson on the wire")
@MainActor
struct BasicsLessonWireTests {

    @Test("The opener is the Basics tag at index 0 plus the completion contract, tagged once")
    func openerTaggedOnce() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: basicsStarter, lessonId: "b1_l1")
        await waitUntil("opener sent") { client.callCount == 1 }

        let wire = client.receivedMessages.first ?? []
        #expect(wire.count == 1)
        #expect(wire.first?.role == "user")
        // Exactly the opener: the legacy bridge must not tag it a second time.
        #expect(wire.first?.content == basicsStarter + completionContract)
        #expect(model.currentLessonId == "b1_l1")
        #expect(model.messages.allSatisfy { !$0.content.contains("[BASICS") }, "the opener is never shown")
    }

    @Test("Follow-up turns carry the opener unchanged and the Basics re-tag on the last turn")
    func followUpTurns() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: basicsStarter, lessonId: "b1_l1")
        await waitUntil("opener sent") { client.callCount == 1 }
        await client.emit(.complete(ChatResponse(reply: "Try asking me: \"Are you a real person?\"", mode: "socratic")))
        await waitUntil("idle") { model.phase == .idle }

        model.draft = "Are you a real person?"
        model.send()
        await waitUntil("practice sent") { client.callCount == 2 }

        let wire = client.receivedMessages.last ?? []
        #expect(wire.map(\.role) == ["user", "assistant", "user"])
        // Byte-identical to the first request's opener, so the server's
        // history cache keeps reading back.
        #expect(wire[0].content == client.receivedMessages.first?.first?.content)
        #expect(wire[2].content == "[BASICS: Unit 1, Lesson 1] Are you a real person?")
        // The thread shows what the learner typed.
        #expect(model.messages.last(where: { $0.role == .user })?.content == "Are you a real person?")
    }

    @Test("A [Q] tap goes out as the pick behind the Basics tag")
    func quizPick() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        model.onLessonComplete = {}
        model.beginLessonConversation(starter: basicsStarter, lessonId: "b1_l1")
        await waitUntil("opener sent") { client.callCount == 1 }
        await client.emit(.complete(ChatResponse(reply: "Pick one.", mode: "socratic")))
        await waitUntil("idle") { model.phase == .idle }

        model.sendQuickReply("I picked B) A computer program that writes answers by guessing what words fit best")
        await waitUntil("pick sent") { client.callCount == 2 }
        #expect(client.receivedMessages.last?.last?.content
                == "[BASICS: Unit 1, Lesson 1] I picked B) A computer program that writes answers by guessing what words fit best")
    }

    @Test("The server's completion flag completes a Basics lesson")
    func completion() async {
        let client = ControllableChatClient()
        let model = makeModel(client)
        var completed = 0
        model.onLessonComplete = { completed += 1 }
        model.beginLessonConversation(starter: basicsStarter, lessonId: "b1_l1")
        await waitUntil("opener sent") { client.callCount == 1 }
        await client.emit(.complete(ChatResponse(reply: "That's exactly right.", mode: "socratic",
                                                 lessonComplete: true)))
        await waitUntil("idle") { model.phase == .idle }
        #expect(completed == 1)
        #expect(model.lessonCompletionEvents == 1)
    }

    @Test("Either lesson tag counts as already tagged; plain text doesn't")
    func carriesLessonTag() {
        #expect(ChatViewModel.carriesLessonTag("[CURRICULUM: Unit 1, Lesson 1] Teach me."))
        #expect(ChatViewModel.carriesLessonTag("[BASICS: Unit 2, Lesson 3] Teach me."))
        #expect(!ChatViewModel.carriesLessonTag("Are you a real person?"))
        #expect(!ChatViewModel.carriesLessonTag("[KEY] not a lesson tag"))
    }

    @Test("The request declares blocks_v1 and this build's platform")
    func capabilities() {
        #expect(ClientCapabilities.current.contains("blocks_v1"))
        #if os(macOS)
        #expect(ClientCapabilities.current.contains("platform_mac"))
        #else
        #expect(ClientCapabilities.current.contains("platform_ios"))
        #endif
        // The server's schema: lowercase tokens of 1–32 characters, at most 16.
        for token in ClientCapabilities.current {
            #expect(token.range(of: #"^[a-z0-9_]{1,32}$"#, options: .regularExpression) != nil)
        }
        #expect(ClientCapabilities.current.count <= 16)
    }
}

@Suite("Basics practice line")
struct PracticeLineTests {

    @Test("The last paragraph's Try asking me / Now try line, straight or curly quotes")
    func extracts() {
        #expect(PracticeLine.extract(from: "Here's the idea.\n\nTry asking me: \"Are you a real person?\"")
                == "Are you a real person?")
        #expect(PracticeLine.extract(from: "Good.\n\nNow try: \u{201C}Make it short and friendly.\u{201D}")
                == "Make it short and friendly.")
        #expect(PracticeLine.extract(from: "Try asking me: \"Plan dinner for 6. One is vegetarian, one hates anything green.\"")
                == "Plan dinner for 6. One is vegetarian, one hates anything green.")
    }

    @Test("Nothing when the practice line isn't the last paragraph, or there's no quote")
    func ignores() {
        #expect(PracticeLine.extract(from: "Try asking me: \"Hi\"\n\nNow, a question for you.") == nil)
        #expect(PracticeLine.extract(from: "Try asking me anything you like.") == nil)
        #expect(PracticeLine.extract(from: "[Q]\nWhich one?\nA) x\nB) y\nC) z\nANS: B\n[/Q]") == nil)
        #expect(PracticeLine.extract(from: "") == nil)
        #expect(PracticeLine.extract(from: "Try asking me: \"\"") == nil)
    }

    @Test("The chip shows only at rest, under Merc's latest reply, with an empty box")
    func chipRules() {
        let reply = ChatMessage(role: .assistant, content: "Try asking me: \"Are you a real person?\"")
        let user = ChatMessage(role: .user, content: "Hi")
        #expect(PracticeLine.chip(messages: [reply], isIdle: true, draft: "") == "Are you a real person?")
        #expect(PracticeLine.chip(messages: [reply], isIdle: false, draft: "") == nil)
        #expect(PracticeLine.chip(messages: [reply], isIdle: true, draft: "typing") == nil)
        #expect(PracticeLine.chip(messages: [reply, user], isIdle: true, draft: "") == nil)
        #expect(PracticeLine.chip(messages: [], isIdle: true, draft: "") == nil)
    }
}

@Suite("Basics lesson words")
struct BasicsCopyTests {

    @Test("No \"just\", \"simply\", \"easy\" or urgency in what Basics screens say")
    func plainWords() {
        let lines = [BasicsCopy.back, BasicsCopy.backAccessibility, BasicsCopy.introLine, BasicsCopy.start,
                     BasicsCopy.placeholder, BasicsCopy.chipHint, BasicsCopy.headline, BasicsCopy.tryThisToday,
                     BasicsCopy.copy, BasicsCopy.copied, BasicsCopy.next("Be specific"), BasicsCopy.backToLessons,
                     BasicsCopy.enough, BasicsCopy.placeSaved]
        for line in lines {
            for word in ["just ", "simply", "easy", "quickly", "hurry", "!"] {
                #expect(!line.lowercased().contains(word), "\"\(word)\" in: \(line)")
            }
        }
    }

    @Test("A Basics unit label: its name, its eyebrow, and on the Mac its code (\"BASICS UNIT 2\" → 2.3)")
    func unitLabel() {
        #if os(macOS)
        #expect(NightLessonCode.code(unitLabel: "BASICS UNIT 2", lessonNumber: 3) == "2.3")
        #expect(NightLessonCode.code(unitLabel: "UNIT 01", lessonNumber: 2) == "1.2")
        #expect(NightLessonCode.code(unitLabel: "CURRICULUM", lessonNumber: 4) == "4")
        #endif
        #expect(CurriculumLessonView.unitName("BASICS UNIT 2") == "Basics Unit 2")
        #expect(CurriculumLessonView.eyebrow(unitLabel: "BASICS UNIT 1", lessonNumber: 2, totalInUnit: 3)
                == "BASICS UNIT 1 · LESSON 2 OF 3")
    }
}
