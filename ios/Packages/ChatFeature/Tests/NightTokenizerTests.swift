#if os(macOS)
import Foundation
import Testing
@testable import ChatFeature

/// Lesson 1.1's interactive on the Mac ("How a model reads “bank”"): where
/// Night Studio's reply draws it, and how it shares the lesson's keys with
/// the check. All pure. What the Mac and the iPhone share (where it sits,
/// its content, the map, its words) is in TokenizerInteractiveTests.

private func reply(_ text: String, _ status: ChatMessage.Status = .idle) -> ChatMessage {
    ChatMessage(role: .assistant, content: text, status: status)
}

private func student(_ text: String) -> ChatMessage {
    ChatMessage(role: .user, content: text)
}

private func placement(_ messages: [ChatMessage]) -> LessonInteractivePlacement? {
    LessonInteractiveAnchor.placement(
        lessonID: TokenizerInteractive.lessonID, messages: messages,
        crisisReplies: LessonCrisisGuard.guardedReplies(in: messages)
    ) { message in
        LessonParts.sections(of: message.content, isStreaming: message.status == .streaming)
    }
}

private func pieces(_ message: ChatMessage, at position: LessonInteractivePosition?,
                    crisis: Bool = false) -> [NightReplyPiece] {
    NightReplyLayout.lesson(sections: LessonParts.sections(of: message.content,
                                                          isStreaming: message.status == .streaming),
                            firstPart: 1, crisis: crisis, isStreaming: message.status == .streaming,
                            interactiveAfter: position)
}

@Suite("Night: the interactive in the drawn reply")
struct NightInteractiveDrawingTests {

    @Test("In the recorded lesson it closes the Tokenization part, before the check")
    func recordedLesson() throws {
        let first = reply(LessonReplay.replies[0])
        let found = try #require(placement([first]))
        let drawn = pieces(first, at: found.position)
        let index = try #require(drawn.firstIndex(of: .interactive))
        #expect(drawn.filter { $0 == .interactive }.count == 1)
        // Right after the "bank … loan and deposit" paragraph, right before
        // part 3's mark ("Check").
        if case .markdown(let text) = drawn[index - 1] {
            #expect(text.contains("clusters near"))
        } else {
            Issue.record("the piece before the interactive is \(drawn[index - 1])")
        }
        #expect(drawn[index + 1] == .partMark(number: 3, name: "Check"))
        // Outside the macro: Swift 6.0's #require is fussy about closures.
        let quizIndex = drawn.firstIndex { if case .quiz = $0 { return true } else { return false } }
        let quiz = try #require(quizIndex)
        #expect(index < quiz, "the check never comes first")
    }

    @Test("A check right after the example, in the same part: the card goes between them")
    func checkInTheSamePart() throws {
        let text = """
        Tokens first.

        [EX]"unbelievable" might become "un", "believ", "able".[/EX]

        [Q]
        What is a token?
        A) A chunk of text
        B) A sentence
        ANS: A
        [/Q]
        """
        let message = reply(text, .streaming)
        let found = try #require(placement([message]))
        let drawn = pieces(message, at: found.position)
        let index = try #require(drawn.firstIndex(of: .interactive))
        #expect(drawn[index - 1] == .example(#""unbelievable" might become "un", "believ", "able"."#))
        if case .quiz = drawn[index + 1] {} else { Issue.record("the check should follow: \(drawn[index + 1])") }
    }

    @Test("No example: at the end of the first complete reply, before its check's mark")
    func noExample() throws {
        let text = """
        Here's the idea.

        ---

        **Tokens** are chunks of text.

        ---

        [Q]
        What is a token?
        A) A chunk of text
        B) A sentence
        ANS: A
        [/Q]
        """
        let done = reply(text)
        let found = try #require(placement([done]))
        let drawn = pieces(done, at: found.position)
        let index = try #require(drawn.firstIndex(of: .interactive))
        #expect(drawn[index + 1] == .partMark(number: 3, name: "Check"))
    }

    @Test("Once per thread: only the first reply with an example draws it")
    func oncePerThread() throws {
        let thread = [reply(LessonReplay.replies[0]), student("I picked B) A chunk of text"),
                      reply(LessonReplay.replies[1]), student("I picked B)"), reply(LessonReplay.replies[2])]
        let found = try #require(placement(thread))
        let cards = thread.filter { $0.role == .assistant }.flatMap { message in
            pieces(message, at: message.id == found.messageID ? found.position : nil)
        }.filter { $0 == .interactive }
        #expect(cards.count == 1)
    }

    @Test("The layout never draws it under the crisis guard")
    func crisis() {
        let drawn = pieces(reply(LessonReplay.replies[0]), at: LessonInteractivePosition(section: 1, afterBlock: 3),
                           crisis: true)
        #expect(!drawn.contains(.interactive))
    }

    @Test("Without a position, a lesson reply draws exactly as before")
    func unchangedWithoutIt() {
        let message = reply(LessonReplay.replies[0])
        let before = NightReplyLayout.lesson(sections: LessonParts.sections(of: message.content, isStreaming: false),
                                             firstPart: 1, crisis: false, isStreaming: false)
        #expect(pieces(message, at: nil) == before)
        #expect(!before.contains(.interactive))
        // With it: the same pieces plus the card.
        let with = pieces(message, at: LessonInteractivePosition(section: 1, afterBlock: 3))
        #expect(with.filter { $0 != .interactive } == before)
    }
}

@Suite("Night: the interactive and the lesson's keys")
@MainActor
struct NightTokenizerKeyTests {

    @Test("While an opening has the keyboard, Return is its own; A–D and the arrows still answer the check")
    func holdsKeys() {
        let router = NightCheckKeyRouter()
        let check = UUID()
        var got: [NightCheckKeys.Key] = []
        router.register(check) { key in got.append(key); return true }
        #expect(router.route(.option(1)))

        let card = UUID()
        router.hold(card, true)
        #expect(router.keysAreElsewhere)
        #expect(!router.route(.lockIn), "Return picks the opening, never locks in the check")
        #expect(router.route(.option(0)), "B still answers the check: the openings don't use it")
        #expect(router.route(.move(1)))
        #expect(got == [.option(1), .option(0), .move(1)])

        router.hold(card, false)
        #expect(!router.keysAreElsewhere)
        #expect(router.route(.lockIn))
        #expect(got == [.option(1), .option(0), .move(1), .lockIn])
        #expect(router.activeID == check, "the check stays registered throughout")
    }

    @Test("A pick on the check takes the keys back: holders let go, so Return locks it in")
    func checkPickReleases() {
        let router = NightCheckKeyRouter()
        var got: [NightCheckKeys.Key] = []
        router.register(UUID()) { key in
            got.append(key)
            // As the check does: a pick tells the router.
            if case .option = key { router.checkPicked() }
            return true
        }
        let opening = UUID(), tryIt = UUID()
        router.hold(opening, true)
        router.hold(tryIt, true)
        let before = router.checkPicks
        #expect(!router.route(.lockIn))
        #expect(router.route(.option(1)), "B, typed with an opening focused (or a click on B)")
        #expect(!router.keysAreElsewhere, "every holder let go")
        #expect(router.checkPicks == before + 1, "the card watches this and drops the opening's focus")
        #expect(router.route(.lockIn), "Return now locks B in")
        #expect(got == [.option(1), .lockIn])
    }

    @Test("Holding is per control and idempotent")
    func holders() {
        let router = NightCheckKeyRouter()
        let a = UUID(), b = UUID()
        router.hold(a, true)
        router.hold(a, true)
        router.hold(b, true)
        router.hold(a, false)
        #expect(router.keysAreElsewhere, "b still holds")
        router.hold(b, false)
        router.hold(b, false)
        #expect(!router.keysAreElsewhere)
    }

    @Test("The card starts compact only when narrower than 440 pt, and opens for good")
    func compact() {
        #expect(!NightTokenizerLayout.isCompact(width: 0, expanded: false), "not measured yet: the full card")
        #expect(NightTokenizerLayout.isCompact(width: 390, expanded: false))
        #expect(!NightTokenizerLayout.isCompact(width: 440, expanded: false))
        #expect(!NightTokenizerLayout.isCompact(width: 580, expanded: false))
        #expect(!NightTokenizerLayout.isCompact(width: 390, expanded: true))
        #expect(NightTokenizerLayout.isCompact(width: 580, expanded: false, forced: true))
        #expect(!NightTokenizerLayout.isCompact(width: 580, expanded: true, forced: true))
    }
}
#endif
