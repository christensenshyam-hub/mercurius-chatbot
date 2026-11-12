import Foundation
import Testing
@testable import ChatFeature

/// The lesson cards (key idea, example, check) render inline Markdown instead
/// of printing it: a key idea written "**Hallucination** is…" showed its
/// asterisks because `Text(String)` is verbatim.
@Suite("Lesson cards: inline Markdown")
struct InlineMarkdownTests {
    @Test("Bold markers are parsed, not printed")
    func boldParsed() {
        let s = InlineMarkdown.attributed("**Hallucination** is when an AI generates plausible text.")
        #expect(String(s.characters) == "Hallucination is when an AI generates plausible text.")
        let bold = s.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold.map { String(s[$0.range].characters) } == "Hallucination")
    }

    @Test("VoiceOver text drops the markers")
    func spoken() {
        #expect(InlineMarkdown.spoken("**Fluency is not accuracy**: a smooth answer") == "Fluency is not accuracy: a smooth answer")
    }

    @Test("Plain text, line breaks and stray symbols are unchanged")
    func plainUnchanged() {
        for text in ["A week has 7 days.", "Line one\nLine two", "5 * 3 = 15", "Costs $5,000 (2023)"] {
            #expect(String(InlineMarkdown.attributed(text).characters) == text)
        }
    }

    @Test("A wrong-pick announcement reads the answer without markers")
    func announcement() {
        let quiz = QuizBlock(stem: "Which?", options: ["**Unverified**", "Supported"], answerIndex: 0, isComplete: true)
        #expect(ChatAnnouncement.quizPick(index: 1, quiz: quiz) == "Not quite. The answer is A: Unverified.")
    }
}
