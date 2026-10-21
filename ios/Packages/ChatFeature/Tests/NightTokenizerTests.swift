#if os(macOS)
import Foundation
import CoreGraphics
import Testing
@testable import ChatFeature

/// Lesson 1.1's interactive on the Mac ("How a model reads “bank”"): where
/// it sits in the thread, its content, the map's geometry, its words and
/// what VoiceOver hears, and how it shares the lesson's keys with the
/// check. All pure. The card changes nothing that is sent or stored.

private let lesson = "u1_l1"

private func reply(_ text: String, _ status: ChatMessage.Status = .idle) -> ChatMessage {
    ChatMessage(role: .assistant, content: text, status: status)
}

private func student(_ text: String) -> ChatMessage {
    ChatMessage(role: .user, content: text)
}

private func placement(_ messages: [ChatMessage], lessonID: String? = lesson) -> NightInteractivePlacement? {
    NightInteractiveAnchor.placement(
        lessonID: lessonID, messages: messages,
        crisisReplies: NightCrisisGuard.guardedReplies(in: messages)
    ) { message in
        NightParts.sections(of: message.content, isStreaming: message.status == .streaming)
    }
}

/// The recorded first reply up to (not including) `marker`.
private func firstReply(upTo marker: String) -> String {
    let text = LessonReplay.replies[0]
    guard let range = text.range(of: marker) else { return text }
    return String(text[..<range.lowerBound])
}

private func pieces(_ message: ChatMessage, at position: NightInteractivePosition?,
                    crisis: Bool = false) -> [NightReplyPiece] {
    NightReplyLayout.lesson(sections: NightParts.sections(of: message.content,
                                                          isStreaming: message.status == .streaming),
                            firstPart: 1, crisis: crisis, isStreaming: message.status == .streaming,
                            interactiveAfter: position)
}

@Suite("Night: where Lesson 1.1's interactive sits")
struct NightInteractivePlacementTests {

    @Test("In the recorded lesson it closes the Tokenization part, before the check")
    func recordedLesson() throws {
        let first = reply(LessonReplay.replies[0])
        let found = try #require(placement([first]))
        #expect(found.messageID == first.id)
        #expect(found.position == NightInteractivePosition(section: 1, afterBlock: 3))

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

    @Test("Only in Lesson 1.1: other lessons and free chat have none")
    func otherLessons() {
        let thread = [reply(LessonReplay.replies[0])]
        #expect(placement(thread, lessonID: "u1_l2") == nil)
        #expect(placement(thread, lessonID: "u2_l1") == nil)
        #expect(placement(thread, lessonID: nil) == nil)
        #expect(placement(thread, lessonID: "") == nil)
        #expect(NightTokenizer.belongs(toLesson: "u1_l1"))
    }

    @Test("A streaming reply: it waits until the example's part has finished arriving")
    func streaming() throws {
        // Mid-part: the "bank" paragraph is still arriving.
        let midPart = reply(firstReply(upTo: "That's how the model"), .streaming)
        #expect(placement([midPart]) == nil)

        // The break has arrived but nothing after it yet: still waiting.
        let atBreak = reply(firstReply(upTo: "[Q]"), .streaming)
        #expect(placement([atBreak]) == nil)

        // The check has begun: the part is in.
        let checkBegun = reply(firstReply(upTo: "A) A full sentence"), .streaming)
        let found = try #require(placement([checkBegun]))
        #expect(found.position == NightInteractivePosition(section: 1, afterBlock: 3))

        // And it stays put as the reply finishes.
        var finished = checkBegun
        finished.content = LessonReplay.replies[0]
        finished.status = .idle
        #expect(placement([finished])?.position == found.position)
    }

    @Test("Merc still thinking (an empty reply streaming): nothing yet")
    func thinking() {
        #expect(placement([reply("", .streaming)]) == nil)
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
        #expect(found.position == NightInteractivePosition(section: 0, afterBlock: 1))
        let drawn = pieces(message, at: found.position)
        let index = try #require(drawn.firstIndex(of: .interactive))
        #expect(drawn[index - 1] == .example(#""unbelievable" might become "un", "believ", "able"."#))
        if case .quiz = drawn[index + 1] {} else { Issue.record("the check should follow: \(drawn[index + 1])") }
    }

    @Test("No example: at the end of the first complete reply, before its check")
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
        // While it streams, an example may still come.
        #expect(placement([reply(text, .streaming)]) == nil)
        let done = reply(text)
        let found = try #require(placement([done]))
        #expect(found.position == NightInteractivePosition(section: 1, afterBlock: 0))
        let drawn = pieces(done, at: found.position)
        let index = try #require(drawn.firstIndex(of: .interactive))
        #expect(drawn[index + 1] == .partMark(number: 3, name: "Check"))

        // Without a check: the reply's very end.
        let plain = reply("One paragraph.\n\nAnother one.")
        #expect(placement([plain])?.position == NightInteractivePosition(section: 0, afterBlock: 0))
    }

    @Test("A reply that opens with its check: the card goes after the part before it, or at the end")
    func checkFirst() {
        let quiz = "[Q]\nPick one\nA) Yes\nB) No\nANS: A\n[/Q]"
        #expect(placement([reply("Intro.\n\n---\n\n" + quiz)])?.position
                == NightInteractivePosition(section: 0, afterBlock: 0))
        #expect(placement([reply(quiz)])?.position == NightInteractivePosition(section: 0, afterBlock: 0))
    }

    @Test("A cut-off reply keeps the card only if the example's part finished (AUD-29)")
    func cutOff() throws {
        let finishedPart = reply(firstReply(upTo: "A) A full sentence"), .failed(reason: "Connection lost."))
        #expect(placement([finishedPart])?.position == NightInteractivePosition(section: 1, afterBlock: 3))

        let interrupted = reply(firstReply(upTo: "A) A full sentence"), .interrupted)
        #expect(placement([interrupted])?.messageID == interrupted.id)

        // Cut mid-part: no card next to the failure line…
        let cut = reply(firstReply(upTo: "That's how the model"), .failed(reason: "Connection lost."))
        #expect(placement([cut]) == nil)
        // …and the next reply decides.
        let answer = student("I think it's a chunk of text")
        let next = reply(LessonReplay.replies[1])
        let found = try #require(placement([cut, answer, next]))
        #expect(found.messageID == next.id)
    }

    @Test("Retry replaces a cut reply: the card follows the new one")
    func retry() throws {
        let cut = reply(firstReply(upTo: "A) A full sentence"), .failed(reason: "Connection lost."))
        #expect(placement([cut])?.messageID == cut.id)
        let again = reply(LessonReplay.replies[0])
        #expect(placement([again])?.messageID == again.id)
    }

    @Test("A reply that failed before any text is passed over")
    func bareFailure() throws {
        let failed = reply("", .failed(reason: "You're offline."))
        let next = reply(LessonReplay.replies[0])
        #expect(placement([failed]) == nil)
        #expect(placement([failed, next])?.messageID == next.id)
    }

    @Test("Once per thread: only the first reply with an example holds it")
    func oncePerThread() throws {
        let thread = [reply(LessonReplay.replies[0]), student("I picked B) A chunk of text"),
                      reply(LessonReplay.replies[1]), student("I picked B)"), reply(LessonReplay.replies[2])]
        let found = try #require(placement(thread))
        #expect(found.messageID == thread[0].id)
        let cards = thread.filter { $0.role == .assistant }.flatMap { message in
            pieces(message, at: message.id == found.messageID ? found.position : nil)
        }.filter { $0 == .interactive }
        #expect(cards.count == 1)
    }

    @Test("A first reply without an example settles it: a later example doesn't move the card")
    func doesNotMove() throws {
        let first = reply("Let's start.\n\n**Tokens** are pieces of text.")
        let later = reply(LessonReplay.replies[1])
        #expect(placement([first])?.messageID == first.id)
        #expect(placement([first, student("ok"), later])?.messageID == first.id)
    }

    @Test("Never in a thread that carried a crisis line, wherever it was")
    func crisis() {
        let lessonReply = reply(LessonReplay.replies[0])
        let crisisReply = reply("I'm really glad you told me. You can call or text 988 any time, day or night.")
        let textLine = reply("You can also text HOME to 741741.")
        #expect(placement([lessonReply, student("I feel awful"), crisisReply]) == nil)
        #expect(placement([lessonReply, student("help"), textLine]) == nil)
        #expect(placement([crisisReply, student("ok"), lessonReply]) == nil)
        // A crisis line in the lesson's own reply.
        #expect(placement([reply(LessonReplay.replies[0] + "\n\nIf you need to talk, call 988.")]) == nil)
        // Not a crisis line: "1988" or "9880".
        #expect(placement([reply(LessonReplay.replies[0] + "\n\nThe first chatbots predate 1988.")]) != nil)
        // The layout never draws it under the guard either.
        let drawn = pieces(lessonReply, at: NightInteractivePosition(section: 1, afterBlock: 3), crisis: true)
        #expect(!drawn.contains(.interactive))
    }

    @Test("A reopened thread puts it in the same place")
    @MainActor
    func reopened() {
        let thread = [reply(LessonReplay.replies[0]), student("I picked B)"), reply(LessonReplay.replies[1])]
        let live = placement(thread)
        // The same thread loaded again: new view, new index.
        let index = NightInteractiveIndex()
        let reopened = index.placement(lessonID: lesson, messages: thread,
                                       crisisReplies: NightCrisisGuard.guardedReplies(in: thread)) {
            NightParts.sections(of: $0.content, isStreaming: $0.status == .streaming)
        }
        #expect(live != nil)
        #expect(reopened == live)
    }

    @Test("The index works it out again when the thread changes, and only then")
    @MainActor
    func indexCache() {
        let index = NightInteractiveIndex()
        var calls = 0
        func ask(_ messages: [ChatMessage]) -> NightInteractivePlacement? {
            index.placement(lessonID: lesson, messages: messages, crisisReplies: []) { message in
                calls += 1
                return NightParts.sections(of: message.content, isStreaming: message.status == .streaming)
            }
        }
        var streaming = reply(firstReply(upTo: "[Q]"), .streaming)
        #expect(ask([streaming]) == nil)
        let first = calls
        #expect(ask([streaming]) == nil)
        #expect(calls == first, "the same thread is not read again")
        streaming.content = LessonReplay.replies[0]
        #expect(ask([streaming]) != nil)
        streaming.status = .idle
        #expect(ask([streaming]) != nil)
        // Another lesson: none, whatever the thread.
        #expect(index.placement(lessonID: "u1_l2", messages: [streaming], crisisReplies: []) { _ in [] } == nil)
    }

    @Test("Without a position, a lesson reply draws exactly as before")
    func unchangedWithoutIt() {
        let message = reply(LessonReplay.replies[0])
        let before = NightReplyLayout.lesson(sections: NightParts.sections(of: message.content, isStreaming: false),
                                             firstPart: 1, crisis: false, isStreaming: false)
        #expect(pieces(message, at: nil) == before)
        #expect(!before.contains(.interactive))
        // With it: the same pieces plus the card.
        let with = pieces(message, at: NightInteractivePosition(section: 1, afterBlock: 3))
        #expect(with.filter { $0 != .interactive } == before)
    }
}

@Suite("Night: the interactive's content")
struct NightTokenizerContentTests {

    @Test("The tokens rejoin to the sentence, each space with the word after it")
    func tokens() {
        #expect(NightTokenizer.tokens.map(\.raw).joined() == NightTokenizer.sentence)
        #expect(NightTokenizer.tokens.map(\.shown) == ["I", "·went", "·to", "·the", "·bank"])
        #expect(NightTokenizer.tokens.first?.leadingSpace == false)
        let spaced = NightTokenizer.tokens.dropFirst().allSatisfy { $0.leadingSpace }
        #expect(spaced)
        #expect(NightTokenizer.bank.text == "bank")
        #expect(Set(NightTokenizer.tokens.map(\.id)).count == NightTokenizer.tokens.count)
    }

    @Test("The sentence is fixed: the card never tokenises anything else")
    func fixedSentence() {
        #expect(NightTokenizer.sentence == "I went to the bank")
        for context in NightTokenizerContext.allCases {
            // The context comes first: a left-to-right model's "bank" can
            // only be shaped by the words before it.
            #expect(context.sentence == context.opening + " " + NightTokenizer.sentence + ".")
            #expect(context.chipTitle == context.opening + "…")
        }
        #expect(NightTokenizerContext.money.sentence == "I got my paycheck, so I went to the bank.")
        #expect(NightTokenizerContext.river.sentence == "I wanted to go fishing, so I went to the bank.")
    }

    @Test("·bank's numbers: a short, signed, illustrative list, the same for both openings")
    func numbers() {
        #expect(NightTokenizer.bankNumbers.count == 8)
        #expect(NightTokenizer.bankNumbers.allSatisfy { abs($0) <= 0.35 })
        #expect(NightTokenizer.bankNumbers.contains { $0 < 0 } && NightTokenizer.bankNumbers.contains { $0 > 0 })
        #expect(NightTokenizer.formatted(0.12) == "0.12")
        #expect(NightTokenizer.formatted(-0.08) == "\u{2212}0.08")
        #expect(NightTokenizerCopy.spokenNumber(-0.27) == "minus 0.27")
    }

    @Test("Each opening's neighbours are its own neighbourhood")
    func neighbours() {
        #expect(NightTokenizerContext.money.neighbours == ["loan", "deposit"])
        #expect(NightTokenizerContext.river.neighbours == ["shore", "water"])
    }
}

@Suite("Night: the map of meaning")
struct NightMeaningMapTests {
    static let widths: [CGFloat] = [390, 440, 520, 580]

    static func size(_ width: CGFloat) -> CGSize {
        CGSize(width: width, height: NightMeaningMap.height(forWidth: width))
    }

    @Test("Each opening puts bank nearest its own neighbours, at every width", arguments: widths)
    func nearest(width: CGFloat) {
        let size = Self.size(width)
        for context in NightTokenizerContext.allCases {
            let near = NightMeaningMap.nearest(to: NightMeaningMap.bank(context), in: size)
            #expect(Set(near) == Set(context.neighbours), "\(context) at \(width): \(near)")
        }
    }

    @Test("bank starts between the two neighbourhoods, and both openings move it from there", arguments: widths)
    func start(width: CGFloat) {
        let size = Self.size(width)
        let near = NightMeaningMap.nearest(to: NightMeaningMap.start, in: size, count: 4)
        // Its nearest two words aren't one neighbourhood's.
        let first = NightMeaningMap.words.first { $0.text == near[0] }?.group
        let second = NightMeaningMap.words.first { $0.text == near[1] }?.group
        #expect(first != second)
        #expect(NightMeaningMap.bank(nil) == NightMeaningMap.start)
        for context in NightTokenizerContext.allCases {
            #expect(NightMeaningMap.bank(context) != NightMeaningMap.start)
        }
    }

    @Test("No label overlaps another, and every label stays on the panel", arguments: widths)
    func labels(width: CGFloat) {
        let size = Self.size(width)
        let panel = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let contexts: [NightTokenizerContext?] = [nil] + NightTokenizerContext.allCases.map { Optional($0) }
        for context in contexts {
            let frames = NightMeaningMap.labelFrames(context, in: size)
            for (name, frame) in frames {
                #expect(panel.contains(frame), "\(name) leaves the panel at \(width) (\(String(describing: context)))")
            }
            for i in frames.indices {
                for j in frames.indices where j > i {
                    #expect(!frames[i].1.intersects(frames[j].1),
                            "\(frames[i].0) meets \(frames[j].0) at \(width) (\(String(describing: context)))")
                }
            }
        }
    }

    @Test("bank's trail from its start never runs through the start's caption or a word's label", arguments: widths)
    func trailClear(width: CGFloat) {
        let size = Self.size(width)
        let start = NightMeaningMap.scaled(NightMeaningMap.start, in: size)
        for context in NightTokenizerContext.allCases {
            let end = NightMeaningMap.scaled(NightMeaningMap.bank(context), in: size)
            let labels = NightMeaningMap.labelFrames(context, in: size).filter { $0.0 != "bank pill" }
            for step in 0...100 {
                let t = CGFloat(step) / 100
                let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                for (name, frame) in labels {
                    #expect(!frame.contains(point), "the \(context) trail crosses \(name) at \(width)")
                }
            }
        }
    }

    @Test("The panel is shorter in a narrow card")
    func height() {
        #expect(NightMeaningMap.height(forWidth: 390) == 200)
        #expect(NightMeaningMap.height(forWidth: 580) == 240)
    }
}

@Suite("Night: the interactive's words")
struct NightTokenizerCopyTests {
    /// Lines that would teach the misconception the lesson corrects (the
    /// model "looks up" a meaning) or the concept's meaning toggle.
    static let misleading: [String] = [
        #"\blooks?\s+up\b"#, #"\blooked\s+up\b"#, #"\blook-?up\b"#, #"\btoggle"#, #"bank\s*=\s*"#,
        #"\bdictionary\b"#, #"\bchoose the meaning\b"#, #"\bpick the meaning\b"#, #"\bknows?\b"#,
    ]

    @Test("Every line keeps the honest-copy register")
    func register() {
        for line in NightTokenizerCopy.everyLine {
            for pattern in NightReplyCopyTests.banned + Self.misleading {
                #expect(line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil,
                        "\"\(line)\" matches \(pattern)")
            }
        }
    }

    @Test("The register catches the concept's toggle and a lookup")
    func catchesMisleading() {
        for line in ["bank = money", "bank = river", "The model looks up the meaning", "a lookup table"] {
            #expect(Self.misleading.contains { line.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil },
                    "\(line)")
        }
    }

    @Test("How bank moves: two short sentences, its own numbers fixed, later layers reading the words before it")
    func accuracy() {
        let note = NightTokenizerCopy.howItMoves
        let sentences = note.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(sentences.count <= 2)
        for sentence in sentences { #expect(sentence.split(separator: " ").count <= 16, "\(sentence)") }
        #expect(note.contains("always starts with the same list of numbers"))
        #expect(note.contains("later layers"))
        // Before, not after or "around": the model reads left to right.
        #expect(note.contains("words before it"))
        #expect(NightTokenizerCopy.startPrompt == "Start the sentence:")
    }

    @Test("The judges' labels are there: illustrative IDs, a list of numbers, a 2-D sketch")
    func labels() {
        #expect(NightTokenizerCopy.idNote.contains("illustrative"))
        #expect(NightTokenizerCopy.idNote.contains("depend on the model’s tokenizer"))
        #expect(NightTokenizerCopy.listLabel == "a list of numbers")
        #expect(NightTokenizerCopy.listNote.contains("thousands of numbers"))
        #expect(NightTokenizerCopy.sketch == "A 2-D sketch: the real space has thousands of dimensions.")
        #expect(NightTokenizerCopy.spaceNote.contains("space"))
        #expect(NightTokenizerCopy.steps == ["You type", "It’s cut into tokens",
                                             "Each token becomes a list of numbers",
                                             "The numbers land in a map of meaning"])
    }

    @Test("VoiceOver hears the map's state in words")
    func mapSummary() {
        #expect(NightTokenizerCopy.mapSummary(.money).hasSuffix("bank is near loan and deposit."))
        #expect(NightTokenizerCopy.mapSummary(.river).hasSuffix("bank is near shore and water."))
        #expect(NightTokenizerCopy.mapSummary(nil).contains("bank starts between two groups of words"))
        for summary in [NightTokenizerCopy.mapSummary(nil)] + NightTokenizerContext.allCases.map(NightTokenizerCopy.mapSummary) {
            #expect(summary.contains("2-D sketch"))
        }
        #expect(NightTokenizerCopy.mapSummary(.money)
                == "Map of meaning, a 2-D sketch. With “I got my paycheck, so” before it, bank is near loan and deposit.")
        #expect(NightTokenizerCopy.pickedAnnouncement(.money)
                == "I got my paycheck, so I went to the bank. " + NightTokenizerCopy.mapSummary(.money))
    }

    @Test("VoiceOver hears each step: the tokens with their spaces, the IDs as illustrative, the numbers")
    func steps() {
        #expect(NightTokenizerCopy.tokensAccessibility
                == "I went to the bank, cut into 5 tokens: I, space went, space to, space the, space bank. "
                    + "Their IDs, illustrative: 40, 4024, 311, 279, 6201.")
        #expect(NightTokenizerCopy.numbersAccessibility.hasPrefix("The token space bank becomes a list of numbers."))
        #expect(NightTokenizerCopy.numbersAccessibility.contains("minus 0.08"))
        #expect(NightTokenizerCopy.numbersAccessibility.hasSuffix("and thousands more."))
        #expect(NightTokenizerCopy.stepAccessibility(4, NightTokenizerCopy.step4)
                == "Step 4: The numbers land in a map of meaning")
        #expect(NightTokenizerCopy.chipAccessibility(.river) == "Start the sentence: I wanted to go fishing, so")
    }
}

@Suite("Night: the interactive and the lesson's keys")
@MainActor
struct NightTokenizerKeyTests {

    @Test("While an opening has the keyboard, the waiting check doesn't take the lesson's keys")
    func holdsKeys() {
        let router = NightCheckKeyRouter()
        let check = UUID()
        var got: [NightCheckKeys.Key] = []
        router.register(check) { key in got.append(key); return true }
        #expect(router.route(.option(1)))

        let card = UUID()
        router.hold(card, true)
        #expect(router.keysAreElsewhere)
        #expect(!router.route(.option(0)), "B stays with the focused opening")
        #expect(!router.route(.lockIn), "Return picks the opening, never locks in the check")
        #expect(got == [.option(1)])

        router.hold(card, false)
        #expect(!router.keysAreElsewhere)
        #expect(router.route(.move(1)))
        #expect(got == [.option(1), .move(1)])
        #expect(router.activeID == check, "the check stays registered throughout")
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

    @Test("The state starts with no opening (outside the shots' flag)")
    func state() {
        let state = NightTokenizerState(context: nil)
        if UserDefaults.standard.string(forKey: "NightTokenizer") == nil {
            #expect(state.context == nil)
        }
        #expect(!state.expanded)
        #expect(NightTokenizerState(context: .river).context == .river)
    }
}
#endif
