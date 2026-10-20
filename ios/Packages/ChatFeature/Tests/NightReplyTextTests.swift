#if os(macOS)
import Foundation
import Testing
@testable import ChatFeature

/// How the Mac's Night Studio reads Merc's replies before drawing them
/// (SPEC.md §5.3–§5.4): the lesson's parts, the sources, the closing
/// question, the crisis guard, the example's token line and the check's
/// keys. All pure; the reply's text itself is never changed.
@Suite("Night: lesson parts")
struct NightPartsTests {

    private func names(_ text: String, streaming: Bool = false) -> [String?] {
        NightParts.sections(of: text, isStreaming: streaming).map(\.name)
    }

    @Test("A reply with no break is one part")
    func oneSection() {
        let sections = NightParts.sections(of: "Hello there.\n\nA second paragraph.", isStreaming: false)
        #expect(sections.count == 1)
        #expect(sections[0].name == nil)
    }

    @Test("The recorded lesson reply splits into its three parts, named honestly")
    func recordedReply() {
        let sections = NightParts.sections(of: LessonReplay.replies[0], isStreaming: false)
        #expect(sections.map(\.name) == [nil, "Tokenization", "Check"])
        // The second part holds the prose, the example and the key idea.
        let kinds = sections[1].blocks.map { block -> String in
            switch block {
            case .prose: return "prose"
            case .example: return "example"
            case .key: return "key"
            case .check: return "check"
            case .quiz: return "quiz"
            }
        }
        #expect(kinds == ["prose", "example", "key", "prose"])
    }

    @Test("The later recorded replies: Check, a bold term, Exercise; no invented names")
    func laterReplies() {
        #expect(names(LessonReplay.replies[1]) == [nil, "next-token prediction", "Check"])
        #expect(names(LessonReplay.replies[2]) == [nil, nil, "Exercise"])
        let all = LessonReplay.replies.flatMap { names($0) }
        #expect(!all.contains("Hook"))
    }

    @Test("Breaks are ---, *** or ___ (three or more, spaced or not); not two, not text")
    func thematicBreaks() {
        for line in ["---", "***", "___", "- - -", "-----", "   ---", "--- "] {
            #expect(NightParts.isThematicBreak(Substring(line)), "\(line)")
        }
        for line in ["--", "-- -x", "- item", "**bold**", "    ---", "-*-", "text ---", ""] {
            #expect(!NightParts.isThematicBreak(Substring(line)), "\(line)")
        }
    }

    @Test("Whitespace-only sections don't count; a trailing break adds nothing yet")
    func emptySections() {
        #expect(NightParts.sections(of: "One.\n\n---\n\n   \n\n---\n\nTwo.", isStreaming: false).count == 2)
        #expect(NightParts.sections(of: "One.\n\n---\n\n", isStreaming: true).count == 1)
        #expect(NightParts.sections(of: "---\n\nOne.", isStreaming: false).count == 1)
    }

    @Test("Streaming: a part counts once its first character arrives")
    func streamingCount() {
        #expect(NightParts.sections(of: "One.\n\n---\n\nT", isStreaming: true).count == 2)
        // A marker still being withheld isn't content yet.
        #expect(NightParts.sections(of: "One.\n\n---\n\n[K", isStreaming: true).count == 1)
        #expect(NightParts.sections(of: "One.\n\n---\n\n[KEY]Tok", isStreaming: true).count == 2)
    }

    @Test("Streaming: a last line of one or two dashes is held back, never shown as text")
    func partialBreakHeld() {
        let sections = NightParts.sections(of: "One.\n\n--", isStreaming: true)
        #expect(sections.count == 1)
        #expect(sections[0].blocks == [.prose("One.\n\n")])
        // Complete, the same "--" is text.
        #expect(NightParts.sections(of: "One.\n\n--", isStreaming: false)[0].blocks == [.prose("One.\n\n--")])
    }

    @Test("A break inside a fenced code block is code")
    func fencedBreak() {
        let text = "Look:\n\n```\n---\n```\n\nDone."
        #expect(NightParts.sections(of: text, isStreaming: false).count == 1)
    }

    @Test("A break inside a [KEY] or [EX] stays inside it")
    func breakInsideBlock() {
        let sections = NightParts.sections(of: "Intro.\n\n[EX]a\n---\nb[/EX]\n\nAfter.", isStreaming: false)
        #expect(sections.count == 1)
    }

    @Test("Naming: a [Q] makes it Check; else the first bold term if ≤ 32 characters; else none")
    func naming() {
        #expect(NightParts.name(of: [.prose("**Tokens** and **more**")]) == "Tokens")
        #expect(NightParts.name(of: [.prose("Plain."), .quiz(QuizBlock(stem: "Q", options: [], answerIndex: nil, isComplete: false))]) == "Check")
        #expect(NightParts.name(of: [.prose("**Exercise:**")]) == "Exercise")
        #expect(NightParts.name(of: [.prose("__Attention__ matters")]) == "Attention")
        let long = "**" + String(repeating: "a", count: 33) + "**"
        #expect(NightParts.name(of: [.prose(long)]) == nil)
        let exactly = "**" + String(repeating: "b", count: 32) + "**"
        #expect(NightParts.name(of: [.prose(exactly)]) == String(repeating: "b", count: 32))
        // The first bold term decides: a long one means no name.
        #expect(NightParts.name(of: [.prose(long + " then **Short**")]) == nil)
        #expect(NightParts.name(of: [.prose("No bold here, just *italic*.")]) == nil)
        // An unclosed bold run (mid-stream) names nothing yet.
        #expect(NightParts.name(of: [.prose("**Tokeniz")]) == nil)
        #expect(NightParts.name(of: [.key("**Key term** inside")]) == "Key term")
    }

    @Test("Numbering runs across the thread over Merc's replies, counting only parts so far")
    @MainActor
    func threadPlan() {
        let messages = [
            ChatMessage(role: .assistant, content: LessonReplay.replies[0]),
            ChatMessage(role: .user, content: "I picked B) A chunk of text converted into a number the model can process"),
            ChatMessage(role: .assistant, content: "Exactly right.\n\n---\n\n**Next", status: .streaming),
        ]
        let index = NightPartIndex()
        let plan = index.plan(for: messages)
        #expect(plan.starts[messages[0].id] == 1)
        #expect(plan.starts[messages[2].id] == 4)
        #expect(plan.parts.map(\.number) == [1, 2, 3, 4, 5])
        #expect(plan.parts.map(\.name) == [nil, "Tokenization", "Check", nil, nil])
        #expect(plan.starts[messages[1].id] == nil, "the student's turns have no parts")
    }

    @Test("A reply that failed before any text has no parts")
    @MainActor
    func failedReplyNoParts() {
        let messages = [ChatMessage(role: .assistant, content: "", status: .failed(reason: "Offline"))]
        #expect(NightPartIndex().plan(for: messages).parts.isEmpty)
    }

    @Test("The strip's 'now reading': the last mark at the top, else part 1; at the end, the last in view")
    @MainActor
    func currentPart() {
        let marks = NightPartMarks()
        #expect(marks.current(partCount: 3, viewportHeight: 600) == 1)
        marks.positions = [2: 195]
        #expect(marks.current(partCount: 3, viewportHeight: 600) == 1, "part 1's text still fills the top")
        marks.positions = [2: -300, 3: 0]
        #expect(marks.current(partCount: 3, viewportHeight: 600) == 3, "a jump puts the mark at the top")
        marks.positions = [2: -300, 3: 450]
        #expect(marks.current(partCount: 3, viewportHeight: 600) == 2)
        #expect(marks.current(partCount: 3, viewportHeight: 600, atBottom: true) == 3,
                "at the end of the thread, a short last part counts once in view")
        // Marks of parts that no longer exist (a retried reply) don't count.
        marks.positions = [2: -300, 5: 10]
        #expect(marks.current(partCount: 3, viewportHeight: 600) == 2)
    }

    @Test("The lesson's layout puts a mark before every part but the first, numbered from its start")
    func lessonLayout() {
        let sections = NightParts.sections(of: LessonReplay.replies[1], isStreaming: false)
        let pieces = NightReplyLayout.lesson(sections: sections, firstPart: 4, crisis: false, isStreaming: false)
        let marks = pieces.compactMap { piece -> Int? in
            if case .partMark(let number, _) = piece { return number } else { return nil }
        }
        #expect(marks == [4, 5, 6])
        let first = NightReplyLayout.lesson(sections: NightParts.sections(of: LessonReplay.replies[0], isStreaming: false),
                                            firstPart: 1, crisis: false, isStreaming: false)
        guard case .markdown = first.first else {
            Issue.record("part 1 has no mark")
            return
        }
        #expect(first.contains(.partMark(number: 2, name: "Tokenization")))
        #expect(first.contains { if case .quiz(let q) = $0 { return q.isWellFormed } else { return false } })
    }
}

@Suite("Night: sources")
struct NightSourceTests {

    @Test("Production's raw tag: the title without quotes, the domain, the path kept for the link")
    func rawTag() throws {
        let source = try #require(NightSourceParser.parseTag(
            #""On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922"#))
        #expect(source.label == "On the Dangers of Stochastic Parrots")
        #expect(source.domain == "dl.acm.org")
        #expect(source.path == "/doi/10.1145/3442188.3445922")
        #expect(source.url?.absoluteString == "https://dl.acm.org/doi/10.1145/3442188.3445922")
    }

    @Test("Every separator the server accepts, a scheme and www, label-only and address-only tags")
    func tagForms() {
        let cases: [(String, String, String?)] = [
            (#""Attention Is All You Need" — arxiv.org/abs/1706.03762"#, "Attention Is All You Need", "arxiv.org"),
            ("Gender Shades — gendershades.org", "Gender Shades", "gendershades.org"),
            ("Gender Shades – gendershades.org", "Gender Shades", "gendershades.org"),
            ("Gender Shades - gendershades.org", "Gender Shades", "gendershades.org"),
            ("Gender Shades: https://www.gendershades.org/", "Gender Shades", "gendershades.org"),
            ("Gender Shades, gendershades.org", "Gender Shades", "gendershades.org"),
            ("Gender Shades | gendershades.org", "Gender Shades", "gendershades.org"),
            ("Gender Shades (gendershades.org)", "Gender Shades", "gendershades.org"),
            ("Gender Shades https://gendershades.org", "Gender Shades", "gendershades.org"),
            ("Pew Research survey on AI", "Pew Research survey on AI", nil),
            ("nist.gov/ai", "", "nist.gov"),
            ("“Curly Title” — Example.COM/path", "Curly Title", "example.com"),
        ]
        for (inner, label, domain) in cases {
            let source = NightSourceParser.parseTag(inner)
            #expect(source?.label == label, "\(inner)")
            #expect(source?.domain == domain, "\(inner)")
        }
        #expect(NightSourceParser.parseTag("   ") == nil)
    }

    @Test("PR #46's plain forms: a line of its own, after a sentence, mid-sentence, label only")
    func rewrittenForms() {
        let standalone = NightSourceParser.extract(from: "Source: On the Dangers of Stochastic Parrots (dl.acm.org)")
        #expect(standalone.text.isEmpty)
        #expect(standalone.sources == [NightSource(label: "On the Dangers of Stochastic Parrots", domain: "dl.acm.org", path: nil)])

        let trailing = NightSourceParser.extract(from: "Training data is mostly web text. Source: Attention Is All You Need (arxiv.org)")
        #expect(trailing.text == "Training data is mostly web text.")
        #expect(trailing.sources.first?.domain == "arxiv.org")

        let inline = NightSourceParser.extract(from: "Attention links distant words (Source: Attention Is All You Need, arxiv.org) in one step.")
        #expect(inline.text == "Attention links distant words in one step.")
        #expect(inline.sources == [NightSource(label: "Attention Is All You Need", domain: "arxiv.org", path: nil)])

        let labelOnly = NightSourceParser.extract(from: "Source: Pew Research survey on AI")
        #expect(labelOnly.text.isEmpty)
        #expect(labelOnly.sources == [NightSource(label: "Pew Research survey on AI", domain: nil, path: nil)])

        let inlineLabelOnly = NightSourceParser.extract(from: "Most teens use chatbots (Source: Pew Research).")
        #expect(inlineLabelOnly.text == "Most teens use chatbots.")
        #expect(inlineLabelOnly.sources.first?.domain == nil)
    }

    @Test("A source with no address is an inert citation; the chip shows the domain only")
    func inertAndDomainOnly() {
        #expect(NightSource(label: "Pew", domain: nil, path: nil).url == nil)
        let rewritten = NightSource(label: "Gender Shades", domain: "gendershades.org", path: nil)
        #expect(rewritten.url?.absoluteString == "https://gendershades.org")
        #expect(NightReplyCopy.sourceCaption(domain: "dl.acm.org") == "Cited by Merc · dl.acm.org")
        #expect(NightReplyCopy.sourceCaption(domain: nil) == "Cited by Merc")
        // A path that can't make a URL still opens the domain.
        let odd = NightSource(label: "X", domain: "example.org", path: "/a b<c>")
        #expect(odd.url?.host() == "example.org")
    }

    @Test("The recorded reply's tag leaves the prose and follows its paragraph as a chip")
    func segmentsKeepOrder() {
        let prose = """
        Exactly — **hallucination**.

        [SOURCE: "On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922]

        So how would you know?
        """
        let segments = NightSourceParser.segments(prose, isStreaming: false)
        #expect(segments.count == 3)
        #expect(segments[0] == .markdown("Exactly — **hallucination**."))
        if case .source(let source) = segments[1] {
            #expect(source.domain == "dl.acm.org")
        } else {
            Issue.record("expected a source chip second")
        }
        #expect(segments[2] == .markdown("So how would you know?"))
    }

    @Test("A tag mid-paragraph: the chip comes after the paragraph; the text closes up")
    func midParagraph() {
        let prose = "Training data is web text. [SOURCE: \"Attention Is All You Need\" — arxiv.org/abs/1706.03762]\n\nBut there's more."
        let segments = NightSourceParser.segments(prose, isStreaming: false)
        #expect(segments.first == .markdown("Training data is web text."))
        #expect(segments.count == 3)
    }

    @Test("Paragraphs without a source are kept byte for byte")
    func untouched() {
        let prose = "Line one  \nline two (with parens) , and  spaces.\n\n- a list\n- item"
        #expect(NightSourceParser.segments(prose, isStreaming: false) == [.markdown(prose)])
    }

    @Test("Streaming: a tag still arriving is held back; a complete reply's unclosed look-alike stays")
    func streamingHoldBack() {
        #expect(NightSourceParser.segments("Text. [SOURCE: \"Atten", isStreaming: true) == [.markdown("Text. ")]
            || NightSourceParser.segments("Text. [SOURCE: \"Atten", isStreaming: true) == [.markdown("Text.")])
        #expect(NightSourceParser.withholdingPartialTag("Text. [SOU") == "Text. ")
        #expect(NightSourceParser.withholdingPartialTag("Text. [x] done") == "Text. [x] done")
        #expect(NightSourceParser.segments("See [SOURCE: never closed", isStreaming: false)
            == [.markdown("See [SOURCE: never closed")])
        // A newline or "[" before "]" means it was never a tag.
        #expect(NightSourceParser.extract(from: "[SOURCE: a [b] c]").sources.isEmpty)
    }

    @Test("A source tag inside a fenced code block is code")
    func fenced() {
        let prose = "```\n[SOURCE: x — y.org]\n```"
        #expect(NightSourceParser.segments(prose, isStreaming: false) == [.markdown(prose)])
    }

    @Test("Shown plainly (the crisis guard), a tag becomes the server's own plain text")
    func plain() {
        #expect(NightSourceParser.plainText("Call 988. [SOURCE: 988 Lifeline — 988lifeline.org/help]")
            == "Call 988. Source: 988 Lifeline (988lifeline.org)")
        #expect(NightSourceParser.plainText("[SOURCE: Pew survey]") == "Source: Pew survey")
        #expect(NightSourceParser.plainText("[SOURCE: ]") == "")
    }
}

@Suite("Night: the closing question")
struct NightYourTurnTests {

    private static let recorded = """
    Exactly — and that distinction has a name worth knowing: **hallucination**.

    When I generate text about something rare or poorly represented, I produce fluent, confident-sounding output that can be completely fabricated — because fluency is what I'm optimized for, not truth.

    [SOURCE: "On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922]

    So here's the uncomfortable follow-up: right now, in this conversation, how would you know if I just hallucinated something?
    """

    @Test("The recorded reply's last paragraph becomes the card; the prose and the chip stay above it")
    func recorded() throws {
        let split = try #require(NightYourTurn.split(Self.recorded))
        #expect(split.question.hasPrefix("So here's the uncomfortable follow-up"))
        #expect(split.question.hasSuffix("hallucinated something?"))
        #expect(!split.before.contains("uncomfortable follow-up"))
        #expect(split.before.contains("[SOURCE:"), "the chip is drawn from the prose above")
        #expect(split.trailingSources.isEmpty)

        let pieces = NightReplyLayout.chat(content: Self.recorded, isStreaming: false, yourTurn: true, crisis: false)
        #expect(pieces.last == .yourTurn(split.question))
        #expect(pieces.contains { if case .source = $0 { return true } else { return false } })
    }

    @Test("Only a real closing question: a statement, a list item, a heading or a quote stays prose")
    func onlyQuestions() {
        #expect(NightYourTurn.split("Intro.\n\nThat's the whole idea.") == nil)
        #expect(NightYourTurn.split("Intro.\n\n- What about this?") == nil)
        #expect(NightYourTurn.split("Intro.\n\n## Why?") == nil)
        #expect(NightYourTurn.split("Intro.\n\n> Is it?") == nil)
        #expect(NightYourTurn.split("Intro.\n\n1. Which one?") == nil)
        #expect(NightYourTurn.split("Is a question first? Then a statement.") == nil)
        #expect(NightYourTurn.split("") == nil)
    }

    @Test("Closing emphasis or quotes after the ? still count")
    func closingMarks() {
        #expect(NightYourTurn.split("Intro.\n\n*What do you think?*")?.question == "*What do you think?*")
        #expect(NightYourTurn.split("Intro.\n\nWhat did they mean by \"true?\"") != nil)
    }

    @Test("400 characters is the longest question that becomes a card")
    func lengthLimit() {
        let fits = String(repeating: "a", count: 399) + "?"
        let tooLong = String(repeating: "a", count: 400) + "?"
        #expect(NightYourTurn.split("Intro.\n\n" + fits) != nil)
        #expect(NightYourTurn.split("Intro.\n\n" + tooLong) == nil)
    }

    @Test("A source cited after the question follows the card")
    func trailingSource() throws {
        let split = try #require(NightYourTurn.split("Intro.\n\nHow would you check?\n\n[SOURCE: Gender Shades — gendershades.org]"))
        #expect(split.question == "How would you check?")
        #expect(split.trailingSources.first?.domain == "gendershades.org")
    }

    @Test("Only the latest completed reply in a Socratic chat: not while streaming, not when off")
    func gating() {
        let reply = "Intro.\n\nWhat do you think?"
        #expect(!NightReplyLayout.chat(content: reply, isStreaming: true, yourTurn: true, crisis: false)
            .contains(.yourTurn("What do you think?")))
        #expect(!NightReplyLayout.chat(content: reply, isStreaming: false, yourTurn: false, crisis: false)
            .contains(.yourTurn("What do you think?")))
        #expect(NightYourTurn.modes == [.socratic])
    }

    @Test("The crisis guard: a reply with 988 or 741741 is plain text: no card, no chip")
    func crisisGuard() {
        let crisis = """
        I'm really glad you told me. You can call or text 988 any time, or text HOME to 741741.

        [SOURCE: 988 Lifeline — 988lifeline.org]

        Would you be willing to reach out to one of them now?
        """
        #expect(NightCrisisGuard.applies(to: crisis))
        let pieces = NightReplyLayout.chat(content: crisis, isStreaming: false, yourTurn: true, crisis: true)
        #expect(pieces.count == 1)
        guard case .plain(let text) = pieces.first else {
            Issue.record("expected plain text")
            return
        }
        #expect(text.contains("Would you be willing"))
        #expect(text.contains("Source: 988 Lifeline (988lifeline.org)"))
        #expect(!text.contains("[SOURCE"))
    }

    @Test("The guard matches whole words only")
    func crisisWords() {
        #expect(NightCrisisGuard.applies(to: "Call 988."))
        #expect(NightCrisisGuard.applies(to: "Text 741741"))
        #expect(!NightCrisisGuard.applies(to: "In 1988 the first chatbots"))
        #expect(!NightCrisisGuard.applies(to: "Order #9880"))
        #expect(!NightCrisisGuard.applies(to: "7417410 tokens"))
    }

    @Test("In a lesson the guard keeps the part marks, and makes every block plain")
    func crisisLesson() {
        let reply = "Please reach out: call 988.\n\n---\n\n[KEY]You matter.[/KEY]\n\n[Q]\nPick one\nA) a\nB) b\nANS: A\n[/Q]"
        let sections = NightParts.sections(of: reply, isStreaming: false)
        let pieces = NightReplyLayout.lesson(sections: sections, firstPart: 1, crisis: true, isStreaming: false)
        #expect(pieces.contains(.partMark(number: 2, name: "Check")))
        for piece in pieces {
            switch piece {
            case .plain, .partMark: continue
            default: Issue.record("a styled piece under the crisis guard: \(piece)")
            }
        }
        let plain = pieces.compactMap { piece -> String? in if case .plain(let t) = piece { return t } else { return nil } }
        #expect(plain.contains("You matter."))
        #expect(plain.contains { $0.contains("A) a") && !$0.contains("ANS") })
    }
}

@Suite("Night: the example's token line")
struct NightTokenLineTests {

    @Test("The recorded example yields un / believ / able")
    func recorded() {
        let example = #"GPT-4 uses a vocabulary of roughly 100,000 tokens. The word "unbelievable" might become three tokens: "un", "believ", "able". A short word like "cat" is one token. An emoji might be several."#
        #expect(NightTokenLine.recognize(example) == .init(word: "unbelievable", pieces: ["un", "believ", "able"]))
        #expect(NightReplyCopy.tokenLineAccessibility(.init(word: "unbelievable", pieces: ["un", "believ", "able"]))
            == "unbelievable becomes 3 tokens: un, believ, able.")
    }

    @Test("Curly quotes work too")
    func curly() {
        #expect(NightTokenLine.recognize("The word “running” splits into tokens: “run”, “ning”.")
            == .init(word: "running", pieces: ["run", "ning"]))
    }

    @Test("Nothing is drawn unless the pieces join to exactly the word")
    func mismatch() {
        #expect(NightTokenLine.recognize(#"The word "unbelievable" becomes tokens "un", "believe", "able"."#) == nil)
        #expect(NightTokenLine.recognize(#"The word "cat" is one token: "cat"."#) == nil, "a single piece")
        #expect(NightTokenLine.recognize(#"The word "unbelievable" splits into "un", "believ", "able"."#) == nil,
                "no 'token' word")
        #expect(NightTokenLine.recognize(#"The word "unbelievable" is long. Tokens: "un", "believ", "able"."#) == nil,
                "a different sentence")
        #expect(NightTokenLine.recognize("No quotes at all, just tokens.") == nil)
        #expect(NightTokenLine.recognize("") == nil)
    }
}

@Suite("Night: the check from the keyboard")
struct NightCheckKeysTests {

    @Test("A–D (either case) and 1–4 pick within the options; anything else doesn't")
    func keys() {
        #expect(NightCheckKeys.optionIndex(forKey: "a", optionCount: 4) == 0)
        #expect(NightCheckKeys.optionIndex(forKey: "D", optionCount: 4) == 3)
        #expect(NightCheckKeys.optionIndex(forKey: "1", optionCount: 3) == 0)
        #expect(NightCheckKeys.optionIndex(forKey: "3", optionCount: 3) == 2)
        #expect(NightCheckKeys.optionIndex(forKey: "4", optionCount: 3) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "d", optionCount: 3) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "e", optionCount: 4) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "0", optionCount: 4) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "ab", optionCount: 4) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "\r", optionCount: 4) == nil)
        #expect(NightCheckKeys.optionIndex(forKey: "é", optionCount: 4) == nil)
    }

    @Test("↑/↓ move the pick and stop at the ends; the first press picks an end")
    func arrows() {
        #expect(NightCheckKeys.moved(nil, by: 1, optionCount: 3) == 0)
        #expect(NightCheckKeys.moved(nil, by: -1, optionCount: 3) == 2)
        #expect(NightCheckKeys.moved(0, by: 1, optionCount: 3) == 1)
        #expect(NightCheckKeys.moved(2, by: 1, optionCount: 3) == 2)
        #expect(NightCheckKeys.moved(0, by: -1, optionCount: 3) == 0)
        #expect(NightCheckKeys.moved(nil, by: 1, optionCount: 0) == nil)
    }

    @Test("An answerable check: Merc's latest reply holds a well-formed [Q] and nothing is in flight")
    func answerable() {
        let quizReply = ChatMessage(role: .assistant, content: LessonReplay.replies[0])
        #expect(NightCheckKeys.hasAnswerableCheck(messages: [quizReply], isIdle: true))
        #expect(!NightCheckKeys.hasAnswerableCheck(messages: [quizReply], isIdle: false))
        let answered = [quizReply, ChatMessage(role: .user, content: "I picked B) A chunk")]
        #expect(!NightCheckKeys.hasAnswerableCheck(messages: answered, isIdle: true))
        let open = ChatMessage(role: .assistant, content: "[Q]\nWhat?\nA) a\nB) b")
        #expect(!NightCheckKeys.hasAnswerableCheck(messages: [open], isIdle: true), "still streaming in")
        #expect(!NightCheckKeys.hasAnswerableCheck(messages: [], isIdle: true))
    }

    @Test("Escape keeps a pick that isn't locked in")
    @MainActor
    func escapeKeepsPick() {
        #expect(CurriculumLessonView.escapeLeaves(isSending: false, draft: "", hasAttachment: false,
                                                  isCelebrating: false, hasUncommittedPick: false))
        #expect(!CurriculumLessonView.escapeLeaves(isSending: false, draft: "", hasAttachment: false,
                                                   isCelebrating: false, hasUncommittedPick: true))
    }
}

@Suite("Night: honest copy (lesson and chat)")
struct NightReplyCopyTests {
    /// The same register as AppFeature's `NightCopyTests` (SPEC §6).
    static let banned: [String] = [
        "notebook", "saved to", "\\bsaved\\b", "rest day", #"part \d+ of \d+"#, #"beat \d"#,
        #"\b\d+\s?min\b"#, #"\bminutes?\b"#, "previewable", "pinned", "give me a hint", "hint",
        "never reset", "verified",
    ]

    static func everyLine() -> [String] {
        var lines: [String] = []
        for number in 1...12 {
            for name in [nil, "Tokenization", "Check"] as [String?] {
                lines += [NightReplyCopy.partNumber(number), NightReplyCopy.partLabel(number),
                          NightReplyCopy.partStripTitle(number, name: name),
                          NightReplyCopy.partAccessibility(number, name: name),
                          NightReplyCopy.stripAccessibilityLabel(count: number, current: number, name: name),
                          NightReplyCopy.segmentHelp(number, name: name)]
            }
        }
        let sources = [NightSource(label: "On the Dangers of Stochastic Parrots", domain: "dl.acm.org", path: nil),
                       NightSource(label: "Pew", domain: nil, path: nil)]
        for source in sources {
            lines += [NightReplyCopy.sourceAccessibility(source, opens: source.url != nil),
                      NightReplyCopy.sourceCaption(domain: source.domain)]
        }
        lines += [NightReplyCopy.stripAccessibilityHint, NightReplyCopy.moreMayFollowHelp,
                  NightReplyCopy.example, NightReplyCopy.keyIdea, NightReplyCopy.yourTurn,
                  NightReplyCopy.tokenLineAccessibility(.init(word: "unbelievable", pieces: ["un", "believ", "able"])),
                  NightReplyCopy.checkOpen, NightReplyCopy.checkAnswered, NightReplyCopy.checkInert,
                  NightReplyCopy.lockIn, NightReplyCopy.lockInAccessibility(letter: "B"), NightReplyCopy.lockInHelp,
                  NightReplyCopy.checkCardHelp, NightReplyCopy.checkPlaceholder, NightReplyCopy.sourceHelp,
                  NightReplyCopy.sourceInertHelp, NightReplyCopy.merc, NightReplyCopy.aiTutor,
                  NightReplyCopy.mercAccessibility, NightReplyCopy.studentAccessibility("Hello")]
        return lines
    }

    @Test("No line promises a feature that doesn't exist")
    func honest() {
        for line in Self.everyLine() {
            for pattern in Self.banned {
                #expect(line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil,
                        "\"\(line)\" matches \(pattern)")
            }
        }
    }

    @Test("The register catches the concept's own lines")
    func catchesConcept() {
        let concept = ["Saved to notebook", "Beat 2 of 6 · Tokenization", "pinned source", "Give me a hint",
                       "about 6 min", "Part 2 of 6"]
        for line in concept {
            #expect(Self.banned.contains { line.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil },
                    "\(line)")
        }
    }

    @Test("Part labels never carry a total")
    func noTotals() {
        #expect(NightReplyCopy.partStripTitle(3, name: "Tokenization") == "Part 3 · Tokenization")
        #expect(NightReplyCopy.stripAccessibilityLabel(count: 3, current: 3, name: "Tokenization")
            == "Lesson parts so far: 3. Now reading part 3, Tokenization.")
        #expect(NightReplyCopy.partNumber(2) == "02")
    }
}
#endif
