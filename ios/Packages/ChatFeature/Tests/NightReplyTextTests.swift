#if os(macOS)
import Foundation
import AppKit
import Testing
@testable import ChatFeature

/// How the Mac's Night Studio reads Merc's replies before drawing them
/// (SPEC.md §5.3–§5.4): the lesson's parts, the sources, the closing
/// question, the crisis guard, the example's token line and the check's
/// keys. All pure; the reply's text itself is never changed.
@Suite("Night: lesson parts")
struct NightPartsTests {

    private func names(_ text: String, streaming: Bool = false) -> [String?] {
        LessonParts.sections(of: text, isStreaming: streaming).map(\.name)
    }

    @Test("A reply with no break is one part")
    func oneSection() {
        let sections = LessonParts.sections(of: "Hello there.\n\nA second paragraph.", isStreaming: false)
        #expect(sections.count == 1)
        #expect(sections[0].name == nil)
    }

    @Test("The recorded lesson reply splits into its three parts, named honestly")
    func recordedReply() {
        let sections = LessonParts.sections(of: LessonReplay.replies[0], isStreaming: false)
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
            #expect(LessonParts.isThematicBreak(Substring(line)), "\(line)")
        }
        for line in ["--", "-- -x", "- item", "**bold**", "    ---", "-*-", "text ---", ""] {
            #expect(!LessonParts.isThematicBreak(Substring(line)), "\(line)")
        }
    }

    @Test("Whitespace-only sections don't count; a trailing break adds nothing yet")
    func emptySections() {
        #expect(LessonParts.sections(of: "One.\n\n---\n\n   \n\n---\n\nTwo.", isStreaming: false).count == 2)
        #expect(LessonParts.sections(of: "One.\n\n---\n\n", isStreaming: true).count == 1)
        #expect(LessonParts.sections(of: "---\n\nOne.", isStreaming: false).count == 1)
    }

    @Test("Streaming: a part counts once its first character arrives")
    func streamingCount() {
        #expect(LessonParts.sections(of: "One.\n\n---\n\nT", isStreaming: true).count == 2)
        // A marker still being withheld isn't content yet.
        #expect(LessonParts.sections(of: "One.\n\n---\n\n[K", isStreaming: true).count == 1)
        #expect(LessonParts.sections(of: "One.\n\n---\n\n[KEY]Tok", isStreaming: true).count == 2)
    }

    @Test("Streaming: a last line of one or two dashes is held back, never shown as text")
    func partialBreakHeld() {
        let sections = LessonParts.sections(of: "One.\n\n--", isStreaming: true)
        #expect(sections.count == 1)
        #expect(sections[0].blocks == [.prose("One.\n\n")])
        // Complete, the same "--" is text.
        #expect(LessonParts.sections(of: "One.\n\n--", isStreaming: false)[0].blocks == [.prose("One.\n\n--")])
    }

    @Test("A break inside a fenced code block is code")
    func fencedBreak() {
        let text = "Look:\n\n```\n---\n```\n\nDone."
        #expect(LessonParts.sections(of: text, isStreaming: false).count == 1)
    }

    @Test("A break inside a [KEY] or [EX] stays inside it")
    func breakInsideBlock() {
        let sections = LessonParts.sections(of: "Intro.\n\n[EX]a\n---\nb[/EX]\n\nAfter.", isStreaming: false)
        #expect(sections.count == 1)
    }

    @Test("Naming: a [Q] makes it Check; else the first bold term if ≤ 32 characters; else none")
    func naming() {
        #expect(LessonParts.name(of: [.prose("**Tokens** and **more**")]) == "Tokens")
        #expect(LessonParts.name(of: [.prose("Plain."), .quiz(QuizBlock(stem: "Q", options: [], answerIndex: nil, isComplete: false))]) == "Check")
        #expect(LessonParts.name(of: [.prose("**Exercise:**")]) == "Exercise")
        #expect(LessonParts.name(of: [.prose("__Attention__ matters")]) == "Attention")
        let long = "**" + String(repeating: "a", count: 33) + "**"
        #expect(LessonParts.name(of: [.prose(long)]) == nil)
        let exactly = "**" + String(repeating: "b", count: 32) + "**"
        #expect(LessonParts.name(of: [.prose(exactly)]) == String(repeating: "b", count: 32))
        // The first bold term decides: a long one means no name.
        #expect(LessonParts.name(of: [.prose(long + " then **Short**")]) == nil)
        #expect(LessonParts.name(of: [.prose("No bold here, just *italic*.")]) == nil)
        // An unclosed bold run (mid-stream) names nothing yet.
        #expect(LessonParts.name(of: [.prose("**Tokeniz")]) == nil)
        #expect(LessonParts.name(of: [.key("**Key term** inside")]) == "Key term")
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
        let sections = LessonParts.sections(of: LessonReplay.replies[1], isStreaming: false)
        let pieces = NightReplyLayout.lesson(sections: sections, firstPart: 4, crisis: false, isStreaming: false)
        let marks = pieces.compactMap { piece -> Int? in
            if case .partMark(let number, _) = piece { return number } else { return nil }
        }
        #expect(marks == [4, 5, 6])
        let first = NightReplyLayout.lesson(sections: LessonParts.sections(of: LessonReplay.replies[0], isStreaming: false),
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

    @Test("Production's raw tag: the title without quotes, the domain; the chip opens the domain, never the model's path")
    func rawTag() throws {
        let source = try #require(NightSourceParser.parseTag(
            #""On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922"#))
        #expect(source.label == "On the Dangers of Stochastic Parrots")
        #expect(source.domain == "dl.acm.org")
        #expect(source.path == "/doi/10.1145/3442188.3445922")
        // AUD-38: model-written paths are often invented (two runs, two
        // made-up CourtListener dockets), so the server drops them too.
        #expect(source.url?.absoluteString == "https://dl.acm.org")
        let docket = try #require(NightSourceParser.parseTag("Mata v. Avianca — courtlistener.com/docket/63107798/mata-v-avianca"))
        #expect(docket.url?.absoluteString == "https://courtlistener.com")
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

    @Test("PR #46's plain forms: a line of its own, after a sentence, mid-sentence; a label alone stays prose")
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

        // Without a domain its end can't be told from prose (the server's
        // own REWRITTEN_SOURCE_RE doesn't match it either): it reads as
        // written, never as a chip.
        let labelOnly = NightSourceParser.extract(from: "Source: Pew Research survey on AI")
        #expect(labelOnly.text == "Source: Pew Research survey on AI")
        #expect(labelOnly.sources.isEmpty)
        let trailingLabelOnly = NightSourceParser.extract(from: "Most teens use chatbots. Source: Pew Research")
        #expect(trailingLabelOnly.text == "Most teens use chatbots. Source: Pew Research")
        #expect(trailingLabelOnly.sources.isEmpty)

        let inlineLabelOnly = NightSourceParser.extract(from: "Most teens use chatbots (Source: Pew Research).")
        #expect(inlineLabelOnly.text == "Most teens use chatbots.")
        #expect(inlineLabelOnly.sources.first?.domain == nil)
    }

    @Test("Prose that says \"Source:\" is never a chip: PR #46's rewrite as a subject, a checklist, a question")
    func sourceInProse() {
        // PR #46's own documented output for a tag at a line's start (fix/
        // server-2026-10 docs/server-batch/04-review-fixes.md).
        let rewrite = "Source: Gender Shades (gendershades.org) backs your bias data; I'm not disputing the disparity exists."
        #expect(NightSourceParser.extract(from: rewrite).text == rewrite)
        #expect(NightSourceParser.extract(from: rewrite).sources.isEmpty)

        // An AI-literacy checklist.
        let checklist = "Before you trust a claim, run three checks:\n\nSource: who made this, and what do they gain?\nEvidence: what backs it up?\nContext: what's missing?"
        let segments = NightSourceParser.segments(checklist, isStreaming: false)
        #expect(segments == [.markdown(checklist)])
        let bold = "**Who made it?** Source: a company that sells the tool."
        #expect(NightSourceParser.extract(from: bold).sources.isEmpty)
        #expect(NightSourceParser.extract(from: bold).text == bold)

        // A closing question that says "Source:" is still the Your turn card.
        let question = "Think about where it came from.\n\nThink about the origin. Source: who benefits if you believe it?"
        let pieces = NightReplyLayout.chat(content: question, isStreaming: false, yourTurn: true, crisis: false)
        #expect(pieces.contains(.yourTurn("Think about the origin. Source: who benefits if you believe it?")))
        #expect(!pieces.contains { if case .source = $0 { return true } else { return false } })

        // VoiceOver never hears a false citation: no chip, no "Source Merc cited".
        #expect(!pieces.contains { if case .source = $0 { return true } else { return false } })
    }

    @Test("Mid-stream, a line that looks like a citation's end waits for the line to end")
    func streamingPlainForms() {
        let partial = "Bias is measurable.\n\nSource: Gender Shades (gendershades.org)"
        #expect(NightSourceParser.segments(partial, isStreaming: true) == [.markdown("Bias is measurable."),
                                                                           .markdown("Source: Gender Shades (gendershades.org)")]
            || NightSourceParser.segments(partial, isStreaming: true)
                == [.markdown("Bias is measurable.\n\nSource: Gender Shades (gendershades.org)")])
        #expect(!NightSourceParser.segments(partial, isStreaming: true).contains { if case .source = $0 { return true } else { return false } })
        // Once the line ends (or the reply does), it is the chip.
        #expect(NightSourceParser.segments(partial + "\n", isStreaming: true).contains(
            .source(NightSource(label: "Gender Shades", domain: "gendershades.org", path: nil))))
        #expect(NightSourceParser.segments(partial, isStreaming: false).contains(
            .source(NightSource(label: "Gender Shades", domain: "gendershades.org", path: nil))))
    }

    @Test("A tag wrapped as a Markdown link takes its link with it (today's production replies)")
    func markdownLinkTags() throws {
        // fix/server-2026-10 docs/evals/pacing-server-2026-10-branch-flag-off-rerun-debate.json:1108
        let first = "**Rebuttal angle:** Your strongest attack is accuracy bias — Joy Buolamwini's Gender Shades study ([SOURCE: Gender Shades — gendershades.org](http://gendershades.org)) showed error rates up to 34% higher for darker-skinned women, meaning the technology can harm the innocent."
        let one = NightSourceParser.extract(from: first)
        #expect(!one.text.contains("http"))
        #expect(!one.text.contains("()"))
        #expect(one.text.contains("Gender Shades study showed error rates"))
        #expect(one.sources == [NightSource(label: "Gender Shades", domain: "gendershades.org", path: nil)])

        // …:1148, the tag as the sentence's subject: its title stays in the sentence.
        let second = "[SOURCE: Gender Shades — gendershades.org](http://gendershades.org) backs your bias data; I'm not disputing the disparity exists."
        let two = NightSourceParser.extract(from: second)
        #expect(two.text == "Gender Shades backs your bias data; I'm not disputing the disparity exists.")
        #expect(two.sources.first?.domain == "gendershades.org")

        // The link's host fills in a tag without a domain; look-alikes stay.
        #expect(NightSourceParser.extract(from: "See [SOURCE: Gender Shades](https://www.gendershades.org/).").sources
            == [NightSource(label: "Gender Shades", domain: "gendershades.org", path: nil)])
        #expect(NightSourceParser.extract(from: "Done [SOURCE: X — x.org] (see above).").text == "Done (see above).")
        #expect(NightSourceParser.extract(from: "Done [SOURCE: X — x.org](2018).").text.contains("(2018)"))
        #expect(NightSourceParser.plainText(second)
            == "Source: Gender Shades (gendershades.org) backs your bias data; I'm not disputing the disparity exists.")

        // Mid-stream, the link is held until its ")" arrives.
        #expect(NightSourceParser.withholdingPartialTag("Study [SOURCE: X — x.org](http://x.o") == "Study [SOURCE: X — x.org]")
        #expect(NightSourceParser.withholdingPartialTag("Study [SOURCE: X — x.org] (see") == "Study [SOURCE: X — x.org] (see")
    }

    @Test("Tags inside [EX], [KEY], [CHECK] and a check's question leave the card and follow it as chips")
    func tagsInCards() {
        let reply = "[EX]Amazon's hiring model penalised résumés that mentioned women's colleges [SOURCE: Reuters — reuters.com/article/amazon-ai].[/EX]\n\n[KEY][SOURCE: Gender Shades — gendershades.org] shows the gap.[/KEY]\n\n[Q]\nWhich study measured it? [SOURCE: Gender Shades — gendershades.org]\nA) Gender Shades\nB) None\nANS: A\n[/Q]"
        let sections = LessonParts.sections(of: reply, isStreaming: false)
        let pieces = NightReplyLayout.lesson(sections: sections, firstPart: 1, crisis: false, isStreaming: false)
        for piece in pieces {
            switch piece {
            case .example(let t), .key(let t), .openQuestion(let t), .markdown(let t):
                #expect(!t.contains("[SOURCE"), "\(t)")
            case .quiz(let quiz):
                #expect(!quiz.stem.contains("[SOURCE"))
                #expect(quiz.options == ["Gender Shades", "None"])
            default: continue
            }
        }
        #expect(pieces.contains(.example("Amazon's hiring model penalised résumés that mentioned women's colleges.")))
        #expect(pieces.filter { if case .source = $0 { return true } else { return false } }.count == 3)
        // The complete card's recap and the crisis guard's plain text, too.
        let messages = [ChatMessage(role: .assistant, content: reply)]
        #expect(NightKeyIdeas.collect(from: messages) == ["Gender Shades shows the gap."])
        let plain = NightReplyLayout.lesson(sections: sections, firstPart: 1, crisis: true, isStreaming: false)
        #expect(plain.contains(.plain("Source: Gender Shades (gendershades.org) shows the gap.")))
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
        #expect(LessonCrisisGuard.applies(to: crisis))
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

    @Test("The guard covers the rest of the thread: a follow-up without the numbers is no Your turn card")
    func crisisThread() {
        let before = ChatMessage(role: .assistant, content: "Tokens are pieces of words. What do you think a token is?")
        let crisis = ChatMessage(role: .assistant, content: "I'm really glad you told me. You can call or text 988 any time.")
        let student = ChatMessage(role: .user, content: "ok")
        let followUp = ChatMessage(role: .assistant, content: "That sounds really heavy, and I'm glad you're still talking with me.\n\nIs there an adult at school or at home you'd feel okay telling tonight?")
        let thread = [before, ChatMessage(role: .user, content: "I don't want to be here anymore"), crisis, student, followUp]
        let guarded = LessonCrisisGuard.guardedReplies(in: thread)
        #expect(guarded == [crisis.id, followUp.id])
        // The follow-up alone wouldn't trip the guard…
        #expect(!LessonCrisisGuard.applies(to: followUp.content))
        // …but in this thread it is drawn plainly: one run of text, no card.
        let pieces = NightReplyLayout.chat(content: followUp.content, isStreaming: false, yourTurn: true,
                                           crisis: guarded.contains(followUp.id))
        #expect(pieces.count == 1)
        #expect(!pieces.contains { if case .yourTurn = $0 { return true } else { return false } })
        // A thread with no crisis line guards nothing.
        #expect(LessonCrisisGuard.guardedReplies(in: [before, student]).isEmpty)
    }

    @Test("The guard matches whole words only")
    func crisisWords() {
        #expect(LessonCrisisGuard.applies(to: "Call 988."))
        #expect(LessonCrisisGuard.applies(to: "Text 741741"))
        #expect(!LessonCrisisGuard.applies(to: "In 1988 the first chatbots"))
        #expect(!LessonCrisisGuard.applies(to: "Order #9880"))
        #expect(!LessonCrisisGuard.applies(to: "7417410 tokens"))
    }

    @Test("In a lesson the guard keeps the part marks, and makes every block plain")
    func crisisLesson() {
        let reply = "Please reach out: call 988.\n\n---\n\n[KEY]You matter.[/KEY]\n\n[Q]\nPick one\nA) a\nB) b\nANS: A\n[/Q]"
        let sections = LessonParts.sections(of: reply, isStreaming: false)
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

    @Test("The lesson's keys for a waiting check: A–D, 1–4, ↑/↓, Return; never with ⌘, ⌃ or ⌥")
    func routedKeys() {
        #expect(NightCheckKeys.key(characters: "b", keyCode: 11, modifiers: []) == .option(1))
        #expect(NightCheckKeys.key(characters: "B", keyCode: 11, modifiers: [.shift]) == .option(1))
        #expect(NightCheckKeys.key(characters: "3", keyCode: 20, modifiers: []) == .option(2))
        #expect(NightCheckKeys.key(characters: "\r", keyCode: 36, modifiers: []) == .lockIn)
        #expect(NightCheckKeys.key(characters: "\u{3}", keyCode: 76, modifiers: [.numericPad]) == .lockIn)
        #expect(NightCheckKeys.key(characters: "\u{F700}", keyCode: 126, modifiers: [.function, .numericPad]) == .move(-1))
        #expect(NightCheckKeys.key(characters: "\u{F701}", keyCode: 125, modifiers: [.function, .numericPad]) == .move(1))
        #expect(NightCheckKeys.key(characters: "e", keyCode: 14, modifiers: []) == nil)
        #expect(NightCheckKeys.key(characters: "a", keyCode: 0, modifiers: [.command]) == nil)
        #expect(NightCheckKeys.key(characters: "\r", keyCode: 36, modifiers: [.command]) == nil)
        #expect(NightCheckKeys.key(characters: "a", keyCode: 0, modifiers: [.option]) == nil)
    }

    @Test("The router hands keys to the one waiting check, and lets go of it")
    @MainActor
    func router() {
        let router = NightCheckKeyRouter()
        #expect(!router.route(.lockIn), "no check waits")
        let first = UUID()
        var got: [NightCheckKeys.Key] = []
        router.register(first) { key in got.append(key); return key != .lockIn }
        #expect(router.activeID == first)
        #expect(router.route(.option(0)))
        #expect(!router.route(.lockIn), "the card can decline (nothing picked yet)")
        #expect(got == [.option(0), .lockIn])
        router.unregister(UUID())
        #expect(router.activeID == first, "another card's unregister doesn't take it away")
        router.unregister(first)
        #expect(router.activeID == nil)
        #expect(!router.route(.option(1)))
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
    static let banned: [String] = HonestCopy.banned

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
