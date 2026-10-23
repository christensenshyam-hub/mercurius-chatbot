import Foundation
import Testing
@testable import ChatFeature
@testable import LessonInteractives

/// The interactives' placement, generalised (BUILD_PLAN.md §1.3): every
/// anchor rule against canned threads, the spoiler scan and its stable
/// flag, Lesson 1.1's card placed exactly as before through the registry,
/// and the DEBUG stub replies landing each card where its rule says. All
/// pure. (Lesson 1.1's own placement tests, unchanged:
/// TokenizerInteractiveTests.)

private func reply(_ text: String, _ status: ChatMessage.Status = .idle) -> ChatMessage {
    ChatMessage(role: .assistant, content: text, status: status)
}

private func student(_ text: String) -> ChatMessage {
    ChatMessage(role: .user, content: text)
}

private func sections(_ message: ChatMessage) -> [LessonPart] {
    LessonParts.sections(of: message.content, isStreaming: message.status == .streaming)
}

/// `id`'s spec, enabled (the wave-1 and wave-2 cards ship dark).
private func spec(_ id: InteractiveID) -> InteractiveSpec {
    InteractiveRegistry.spec(for: id)!.enabled(true)
}

private func place(_ spec: InteractiveSpec, _ messages: [ChatMessage]) -> LessonInteractivePlacement? {
    LessonInteractiveAnchor.placement(spec: spec, messages: messages,
                                      crisisReplies: LessonCrisisGuard.guardedReplies(in: messages),
                                      sections: sections)
}

private let check = """
[Q]
What is it?
A) One thing
B) Another
ANS: A
[/Q]
"""

/// A teach reply: an opening part, an [EX] part, then a check part.
private func teach(_ words: String = "A teach reply.", example: Bool = true) -> String {
    let middle = example ? "**The example**\n\n[EX]\(words) An example.[/EX]\n\nAfter the example." : "No example here."
    return "\(words) Opening.\n\n---\n\n\(middle)\n\n---\n\n\(check)"
}

private let exercise = "Now the exercise: write three sentences about it. Take your best shot."

// MARK: - Lesson 1.1, through the registry

@Suite("Interactives: Lesson 1.1's card, placed as before")
struct TokenizerThroughRegistryTests {

    @Test("The registry gives Lesson 1.1 its card and rule, enabled")
    func registryRow() throws {
        let row = try #require(InteractiveRegistry.spec(forLesson: TokenizerInteractive.lessonID))
        #expect(row.id == .tokenizer)
        #expect(row.anchor == .firstExample)
        #expect(row.spoilers.isEmpty)
        #expect(row.enabled)
        #expect(InteractiveRegistry.spec(for: .tokenizer)?.lessonID == TokenizerInteractive.lessonID)
    }

    @Test("The lesson-id path and the spec path agree on every recorded and edge thread")
    func samePlacement() throws {
        let row = try #require(InteractiveRegistry.spec(for: .tokenizer))
        let first = reply(LessonReplay.replies[0])
        var cut = reply(LessonReplay.replies[0])
        cut.content = String(LessonReplay.replies[0].prefix(300))
        cut.status = .interrupted
        let threads: [[ChatMessage]] = [
            [first],
            [first, student("I picked B) A chunk of text"), reply(LessonReplay.replies[1]),
             student("I picked B)"), reply(LessonReplay.replies[2])],
            [reply(String(LessonReplay.replies[0].prefix(600)), .streaming)],
            [cut, student("ok"), reply(LessonReplay.replies[1])],
            [reply("", .streaming)],
            [reply(LessonReplay.replies[0] + "\n\nIf you need to talk, call 988.")],
            [reply("Hello.\n\n---\n\n" + check)],
        ]
        for thread in threads {
            let byLesson = LessonInteractiveAnchor.placement(
                lessonID: "u1_l1", messages: thread, crisisReplies: LessonCrisisGuard.guardedReplies(in: thread),
                sections: sections)
            #expect(byLesson == place(row, thread))
            #expect(byLesson.map(\.card) == byLesson.map { _ in InteractiveID.tokenizer })
            #expect(byLesson?.spoiled != true)
        }
        // The recorded lesson: the Tokenization part's end, before the check.
        let found = try #require(place(row, [first]))
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 3))
        #expect(found.cardRef == .tokenizer)
    }

    @Test("A lesson whose card ships dark has none (until DEBUG forces it)")
    func darkCards() {
        let thread = [reply(teach())]
        for lesson in ["u6_l4", "u8_l1", "u1_l3", "u3_l1", "u5_l1", "u2_l2", "u3_l2"] {
            #expect(LessonInteractiveAnchor.placement(lessonID: lesson, messages: thread, crisisReplies: [],
                                                      sections: sections) == nil, "\(lesson)")
        }
        #expect(place(spec(.doubtDial), thread)?.card == .doubtDial)
    }
}

// MARK: - The rules

@Suite("Interactives: the anchor rules")
struct AnchorRuleTests {

    @Test("firstExample: [EX] in reply 1 → after its part, before the check")
    func firstExampleInReplyOne() throws {
        let first = reply(teach())
        let found = try #require(place(spec(.doubtDial), [first]))
        #expect(found.messageID == first.id)
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 2))
        #expect(found.card == .doubtDial && !found.spoiled)
    }

    @Test("firstExample: no [EX] → the first complete reply's end, before its check")
    func firstExampleNoExample() throws {
        let first = reply(teach(example: false))
        let found = try #require(place(spec(.pageWithASecret), [first]))
        #expect(found.messageID == first.id)
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 0))
    }

    @Test("teachReply(2): the second reply with a check, after its example's part")
    func teachReplyTwo() throws {
        let one = reply(teach("Northpointe isn't here yet."))
        let two = reply(teach("Northpointe answered: the scores are calibrated."))
        let thread = [one, student("I picked A) One thing"), two]
        let found = try #require(place(spec(.twoTestsOneLine), thread))
        #expect(found.messageID == two.id)
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 2))
        // One teach reply so far: nothing yet.
        #expect(place(spec(.twoTestsOneLine), [one]) == nil)
        // A reply without a check doesn't count.
        let chat = reply("Good question. Let me explain more.")
        #expect(place(spec(.twoTestsOneLine), [one, student("why?"), chat]) == nil)
        #expect(place(spec(.twoTestsOneLine), [one, student("why?"), chat, student("ok"), two])?.messageID == two.id)
    }

    @Test("teachReply(2) without an example: the reply's end, before its check")
    func teachReplyNoExample() throws {
        let one = reply(teach())
        let two = reply(teach("Second.", example: false))
        let found = try #require(place(spec(.twoTestsOneLine), [one, student("A"), two]))
        #expect(found.messageID == two.id)
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 0))
    }

    @Test("teachReply(2) while streaming: it waits for the check to begin")
    func teachReplyStreaming() throws {
        let one = reply(teach())
        let full = teach("Second.")
        let beforeCheck = String(full[..<full.range(of: "[Q]")!.lowerBound])
        #expect(place(spec(.twoTestsOneLine), [one, student("A"), reply(beforeCheck, .streaming)]) == nil)
        let checkBegun = String(full[..<full.range(of: "A) One")!.lowerBound])
        let found = try #require(place(spec(.twoTestsOneLine), [one, student("A"), reply(checkBegun, .streaming)]))
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 2))
    }

    @Test("teachReply(2): a nth reply whose check comes first hands the card to the next teach reply")
    func teachReplyPassOver() throws {
        let one = reply(teach())
        let bare = reply(check)
        let three = reply(teach("Third."))
        let found = try #require(place(spec(.twoTestsOneLine), [one, student("A"), bare, student("A"), three]))
        #expect(found.messageID == three.id)
    }

    @Test("firstReplyMentioning: sepsis in reply 1 → reply 1")
    func mentionInReplyOne() throws {
        let one = reply(teach("Sepsis kills many patients."))
        let found = try #require(place(spec(.wardOf1000), [one]))
        #expect(found.messageID == one.id)
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 2))
    }

    @Test("firstReplyMentioning: sepsis in reply 2 → reply 2, not reply 1")
    func mentionInReplyTwo() throws {
        let one = reply(teach("FDA-authorized diagnostics read scans."))
        let two = reply(teach("A sepsis model at Michigan Medicine."))
        let found = try #require(place(spec(.wardOf1000), [one, student("A"), two]))
        #expect(found.messageID == two.id)
        #expect(place(spec(.wardOf1000), [one]) == nil, "reply 1 is teach reply 1 of the fallback's 2")
    }

    @Test("firstReplyMentioning: no mention by teach reply 2 → the fallback, teach reply 2")
    func mentionFallback() throws {
        let one = reply(teach("Diagnostics."))
        let two = reply(teach("Triage tools."))
        let found = try #require(place(spec(.wardOf1000), [one, student("A"), two]))
        #expect(found.messageID == two.id)
    }

    @Test("firstReplyMentioning: a reply still arriving without the term is waited for")
    func mentionStreaming() throws {
        let one = reply(teach("Diagnostics."))
        let full = teach("Triage tools, and then sepsis.")
        let early = String(full.prefix(10))
        #expect(place(spec(.wardOf1000), [one, student("A"), reply(early, .streaming)]) == nil)
        let checkBegun = String(full[..<full.range(of: "A) One")!.lowerBound])
        let found = try #require(place(spec(.wardOf1000), [one, student("A"), reply(checkBegun, .streaming)]))
        #expect(found.position == LessonInteractivePosition(section: 1, afterBlock: 2))
    }

    @Test("A reply cut mid-example is passed over; the next reply decides (every rule)")
    func cutMidExample() throws {
        let full = teach("Sepsis first.")
        let cutText = String(full[..<full.range(of: "An example.")!.lowerBound])
        let cut = reply(cutText, .interrupted)
        let next = reply(teach("Sepsis again."))
        for id in [InteractiveID.doubtDial, .wardOf1000] {
            #expect(place(spec(id), [cut]) == nil, "\(id)")
            #expect(place(spec(id), [cut, student("go on"), next])?.messageID == next.id, "\(id)")
        }
    }

    @Test("AUD-29: a saved cut reply comes back .idle; with a reply after it, it must show its part ended")
    func aud29() throws {
        // Cut right after the example's part ended, no later part arrived:
        // saved as .idle, answered, then the next reply.
        let full = teach()
        let keptText = String(full[..<full.range(of: "After the example.")!.lowerBound])
        let kept = reply(keptText)
        let next = reply(teach("Next."))
        let found = try #require(place(spec(.doubtDial), [kept, student("ok"), next]))
        #expect(found.messageID == next.id, "the kept reply's part may have been cut")
        // As the thread's last message it counts as complete.
        #expect(place(spec(.doubtDial), [kept])?.messageID == kept.id)
    }

    @Test("Retry replaces a failed reply, and the rule decides again")
    func retry() throws {
        let failed = reply("", .failed(reason: "Connection lost"))
        #expect(place(spec(.doubtDial), [failed]) == nil)
        let retried = reply(teach())
        #expect(place(spec(.doubtDial), [retried])?.messageID == retried.id)
    }

    @Test("A crisis line before, in or after the anchor: no card, for every rule")
    func crisis() {
        let crisisLine = reply("If you need to talk, call or text 988.")
        let one = reply(teach("Sepsis."))
        let two = reply(teach("Second, sepsis."))
        for id in [InteractiveID.doubtDial, .twoTestsOneLine, .wardOf1000] {
            #expect(place(spec(id), [crisisLine, student("ok"), one, student("A"), two]) == nil, "\(id) before")
            #expect(place(spec(id), [one, student("A"), reply(teach("Call 988 if you need to.")), student("A"), two]) == nil,
                    "\(id) in")
            #expect(place(spec(id), [one, student("A"), two, student("I feel awful"), crisisLine]) == nil, "\(id) after")
        }
    }
}

// MARK: - Spoilers

@Suite("Interactives: spoilers")
struct SpoilerTests {

    @Test("A term above the card in its own reply spoils it; one below it doesn't")
    func inTheAnchorReply() throws {
        let above = reply(teach("Some pages hide text for AI tools: prompt injection."))
        #expect(try #require(place(spec(.pageWithASecret), [above])).spoiled)
        let belowText = teach("An agent plans, acts and observes.")
            .replacingOccurrences(of: "What is it?", with: "What is prompt injection?")
        let below = reply(belowText)
        #expect(try #require(place(spec(.pageWithASecret), [below])).spoiled == false)
    }

    @Test("A term in an earlier reply spoils it")
    func inAnEarlierReply() throws {
        let one = reply(teach("Kleinberg showed something."))
        let two = reply(teach("Northpointe's answer."))
        let found = try #require(place(spec(.twoTestsOneLine), [one, student("A"), two]))
        #expect(found.messageID == two.id && found.spoiled)
        let clean = try #require(place(spec(.twoTestsOneLine), [reply(teach("ProPublica.")), student("A"), two]))
        #expect(!clean.spoiled)
    }

    @Test("A card without spoiler terms is never spoiled")
    func noTerms() throws {
        let found = try #require(place(spec(.doubtDial), [reply(teach("hidden text, prompt injection, 88%"))]))
        #expect(!found.spoiled)
    }

    @Test("The flag is worked out once and kept: later replies, a reopen, never flip it")
    @MainActor
    func stable() throws {
        let memory = LessonInteractiveMemory()
        let index = LessonInteractiveIndex(memory: memory)
        let row = spec(.pageWithASecret)
        let one = reply(teach("An agent plans and acts."))
        func ask(_ index: LessonInteractiveIndex, _ thread: [ChatMessage]) -> LessonInteractivePlacement? {
            index.placement(spec: row, messages: thread, crisisReplies: LessonCrisisGuard.guardedReplies(in: thread),
                            sections: sections)
        }
        let found = try #require(ask(index, [one]))
        #expect(!found.spoiled)
        // The next reply names the spoiler: the card was already met, unspoiled.
        let later = [one, student("A"), reply(teach("That was prompt injection, as in the Guardian test."))]
        #expect(ask(index, later) == found)
        // Reopened in the same run: the same place, the same flag.
        let reopened = LessonInteractiveIndex(memory: memory)
        #expect(ask(reopened, later) == found)
        // Worked out fresh from the whole thread, the earlier-reply rule
        // agrees: the anchor reply itself is unspoiled.
        #expect(place(row, later)?.spoiled == false)
    }
}

// MARK: - The DEBUG stub replies

@Suite("Interactives: the DEBUG stub replies")
struct StubReplyTests {

    /// The stub thread up to (and including) reply `count`, as the replay
    /// and its auto-answers would build it.
    private func thread(_ replies: [String], upTo count: Int) -> [ChatMessage] {
        var thread: [ChatMessage] = []
        for (index, text) in replies.prefix(count).enumerated() {
            if index > 0 { thread.append(student(LessonReplay.stubAnswer)) }
            thread.append(reply(text))
        }
        return thread
    }

    @Test("Every card's stubs land it in the reply its rule says, unspoiled")
    func landing() throws {
        for row in InteractiveRegistry.all where row.id != .tokenizer {
            let stubs = InteractiveStubReplies.replies(forLesson: row.lessonID, spoiled: false)
            let reach = row.anchor.repliesToReach
            #expect(stubs.count == reach + 1, "\(row.id)")
            let messages = thread(stubs, upTo: reach)
            let found = try #require(place(row.enabled(true), messages), "\(row.id)")
            #expect(found.messageID == messages.last?.id, "\(row.id)")
            #expect(!found.spoiled, "\(row.id)")
            // Before the card's reply has arrived, nothing.
            if reach > 1 {
                #expect(place(row.enabled(true), thread(stubs, upTo: reach - 1)) == nil, "\(row.id)")
            }
        }
    }

    @Test("Spoiled stubs reach the spoiled mode through the real scan")
    func spoiled() throws {
        for row in InteractiveRegistry.all where !row.spoilers.isEmpty {
            let stubs = InteractiveStubReplies.replies(forLesson: row.lessonID, spoiled: true)
            let found = try #require(place(row.enabled(true), thread(stubs, upTo: row.anchor.repliesToReach)))
            #expect(found.spoiled, "\(row.id)")
        }
    }

    @Test("Stubs say they are stubs, and carry no crisis line")
    func honest() {
        for row in InteractiveRegistry.all where row.id != .tokenizer {
            for text in InteractiveStubReplies.replies(forLesson: row.lessonID, spoiled: true) {
                #expect(text.hasPrefix("**Debug stub, reply"), "\(row.id)")
                #expect(!LessonCrisisGuard.applies(to: text), "\(row.id)")
            }
        }
        #expect(LessonReplay.replies(forLesson: "u1_l1") == LessonReplay.replies)
        #expect(LessonReplay.replies(forLesson: nil) == LessonReplay.replies)
        #expect(LessonReplay.replies(forLesson: "u6_l4").first?.hasPrefix("**Debug stub") == true)
        // A lesson without a card still gets the first-example shape.
        #expect(InteractiveStubReplies.replies(forLesson: "u4_l2", spoiled: false).count == 2)
        #expect(LessonReplay.repliesToReach(lessonID: "u2_l2") == nil, "no -Interactive in the test host")
    }
}

// MARK: - The framework's seams with Lesson 1.1's card

@Suite("Interactives: shared with Lesson 1.1's card")
struct InteractiveSeamTests {

    @Test("The honest-copy register is one list")
    func honestCopy() {
        #expect(InteractiveCopyRules.honestCopyBanned == HonestCopy.banned)
    }

    @Test("The frame's words are Lesson 1.1's")
    func shellWords() {
        #expect(InteractiveShellCopy.eyebrow == TokenizerCopy.eyebrow)
        #expect(InteractiveShellCopy.tryIt == TokenizerCopy.tryIt)
        #expect(InteractiveShellCopy.tryItHint == TokenizerCopy.tryItHint)
    }

    #if os(macOS)
    @Test("The Mac's compact width is Lesson 1.1's")
    func compactWidth() {
        #expect(InteractiveLayout.macCompactBelowWidth == NightTokenizerLayout.compactBelowWidth)
    }
    #endif

    @Test("A bubble draws Lesson 1.1's card unless told otherwise; the card is part of its equality")
    @MainActor
    func bubbleDefault() {
        let message = reply(LessonReplay.replies[0])
        let plain = MessageBubbleView(message: message, lessonStyle: true,
                                      interactiveAfter: LessonInteractivePosition(section: 1, afterBlock: 3))
        #expect(plain.interactiveCard == .tokenizer)
        var other = plain
        other.interactiveCard = LessonInteractiveCardRef(id: .doubtDial, spoiled: false)
        #expect(plain != other)
        var spoiled = other
        spoiled.interactiveCard = LessonInteractiveCardRef(id: .doubtDial, spoiled: true)
        #expect(other != spoiled)
    }
}
