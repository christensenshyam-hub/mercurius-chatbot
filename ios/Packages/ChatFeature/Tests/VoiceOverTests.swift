import Testing
import Foundation
@testable import ChatFeature

// AUD-23: what VoiceOver hears in a lesson — announcements when a reply lands
// or fails and when a [Q] pick is graded, labels for the [Q] options, and
// which bubbles it walks block by block.
@Suite("VoiceOver in lessons")
struct VoiceOverTests {

    private func reply(_ text: String, status: ChatMessage.Status = .idle) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, status: status)
    }

    private let quiz = QuizBlock(stem: "Which makes a noun?", options: ["-ly", "-ness", "-ize"],
                                 answerIndex: 1, isComplete: true)

    // MARK: Announcements

    @Test("A settled reply is announced, with its question when it asks one")
    func replyLanded() {
        #expect(ChatAnnouncement.afterPhaseChange(from: .streaming, to: .idle,
                                                  latest: reply("Tokens are pieces of words."))
                == "Merc replied.")
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .streaming, to: .idle,
                    latest: reply("Tokens are pieces.\n\n[CHECK]What is a token?[/CHECK]"))
                == "Merc replied. Question: What is a token?")
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .sending, to: .idle,
                    latest: reply("Try this.\n[Q]\nWhich makes a noun?\nA) -ly\nB) -ness\nANS: B\n[/Q]"))
                == "Merc replied. Question: Which makes a noun?")
    }

    @Test("A failed reply is announced with its reason")
    func replyFailed() {
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .streaming, to: .failed(reason: "The connection dropped.", isRetryable: true),
                    latest: reply("Partial", status: .failed(reason: "The connection dropped.")))
                == "Merc's reply didn't arrive. The connection dropped.")
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .sending, to: .failed(reason: "Daily limit reached.", isRetryable: false),
                    latest: nil)
                == "Merc's reply didn't arrive. Daily limit reached.")
    }

    @Test("Nothing is announced at the start of a request, or with no reply to speak of")
    func silentChanges() {
        #expect(ChatAnnouncement.afterPhaseChange(from: .idle, to: .sending, latest: nil) == nil)
        #expect(ChatAnnouncement.afterPhaseChange(from: .sending, to: .streaming, latest: reply("T")) == nil)
        #expect(ChatAnnouncement.afterPhaseChange(from: .idle, to: .idle, latest: reply("Old")) == nil)
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .failed(reason: "x", isRetryable: true), to: .idle, latest: reply("Old")) == nil)
        #expect(ChatAnnouncement.afterPhaseChange(
                    from: .streaming, to: .idle,
                    latest: ChatMessage(role: .user, content: "Hi")) == nil)
        #expect(ChatAnnouncement.afterPhaseChange(from: .streaming, to: .idle, latest: reply("  ")) == nil)
    }

    @Test("A graded [Q] pick says right, or what the answer was")
    func quizPick() {
        #expect(ChatAnnouncement.quizPick(index: 1, quiz: quiz) == "Correct.")
        #expect(ChatAnnouncement.quizPick(index: 0, quiz: quiz) == "Not quite. The answer is B: -ness.")
        let keyless = QuizBlock(stem: "?", options: ["a", "b"], answerIndex: nil, isComplete: true)
        #expect(ChatAnnouncement.quizPick(index: 0, quiz: keyless) == "Answer sent.")
    }

    // MARK: [Q] option labels

    @Test("Options read 'Option B: …', and after grading say which was right and what the pick was")
    func optionLabels() {
        let open = CheckQuizCard.optionAccessibility(index: 1, option: "-ness", pick: nil, answerIndex: 1)
        #expect(open.label == "Option B: -ness")
        #expect(open.value == nil)

        let rightPick = CheckQuizCard.optionAccessibility(index: 1, option: "-ness", pick: 1, answerIndex: 1)
        #expect(rightPick.value == "Correct answer, your answer")

        let missed = CheckQuizCard.optionAccessibility(index: 1, option: "-ness", pick: 0, answerIndex: 1)
        #expect(missed.value == "Correct answer")
        let wrongPick = CheckQuizCard.optionAccessibility(index: 0, option: "-ly", pick: 0, answerIndex: 1)
        #expect(wrongPick.value == "Your answer, incorrect")
        let other = CheckQuizCard.optionAccessibility(index: 2, option: "-ize", pick: 0, answerIndex: 1)
        #expect(other.value == nil)
    }

    // MARK: Bubble granularity

    @Test("Settled lesson replies are walked block by block; everything else is one element")
    func readsAsBlocks() {
        #expect(MessageBubbleView.readsAsBlocks(reply("Prose"), lessonStyle: true))
        #expect(MessageBubbleView.readsAsBlocks(reply("Cut", status: .interrupted), lessonStyle: true))
        #expect(MessageBubbleView.readsAsBlocks(reply("Partial", status: .failed(reason: "x")), lessonStyle: true))
        // Still streaming: one "Mercurius is replying" element, not a moving tree.
        #expect(!MessageBubbleView.readsAsBlocks(reply("Part", status: .streaming), lessonStyle: true))
        // Failed before any text: just the failure line.
        #expect(!MessageBubbleView.readsAsBlocks(reply("", status: .failed(reason: "x")), lessonStyle: true))
        // Free chat and the student's turns are unchanged.
        #expect(!MessageBubbleView.readsAsBlocks(reply("Prose"), lessonStyle: false))
        #expect(!MessageBubbleView.readsAsBlocks(ChatMessage(role: .user, content: "B"), lessonStyle: true))
    }
}
