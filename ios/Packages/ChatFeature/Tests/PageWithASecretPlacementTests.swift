import Foundation
import Testing
@testable import ChatFeature
@testable import LessonInteractives

/// The Page with a Secret's spoiler terms (refined from the slate's three;
/// docs/interactives/page-with-a-secret/CONTENT.md §4), through the real
/// placement: the guide's own wordings above the card spoil it; "a parent or
/// guardian" and the agent loop's teach line don't.
@Suite("The Page with a Secret: placement and spoilers in a thread")
struct PageWithASecretPlacementTests {

    private func reply(_ text: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, status: .idle)
    }

    private func place(_ messages: [ChatMessage]) -> LessonInteractivePlacement? {
        let spec = InteractiveRegistry.spec(for: .pageWithASecret)!.enabled(true)
        return LessonInteractiveAnchor.placement(
            spec: spec, messages: messages, crisisReplies: LessonCrisisGuard.guardedReplies(in: messages),
            sections: { LessonParts.sections(of: $0.content, isStreaming: $0.status == .streaming) })
    }

    /// A first teach reply: `opening`, then an [EX] part, then a check.
    private func teach(_ opening: String) -> String {
        """
        \(opening)

        ---

        **An agent at work**

        [EX]You ask an agent to book a study room. It plans, searches the school site, and books.[/EX]

        After the example.

        ---

        [Q]
        What makes an agent different from a chatbot?
        A) It chains actions toward a goal
        B) It types faster
        ANS: A
        [/Q]
        """
    }

    @Test("The card lands after the example's part, unspoiled, on the guide's teach line")
    func clean() throws {
        let found = try #require(place([reply(teach(
            "An agent = an LLM + tools + a loop: plan, act, observe, repeat. Ask a parent or guardian before you "
            + "let one book anything."))]))
        #expect(found.card == .pageWithASecret)
        #expect(!found.spoiled)
    }

    @Test("The guide's wordings for the idea, above the card, open it spoiled")
    func spoiled() throws {
        for opening in [
            "A chatbot that reads web pages can be steered by instructions hidden in them.",
            "In December 2024 The Guardian showed hidden text on a web page changing a review.",
            "Never assume a chatbot can't be hijacked.",
            "Indirect prompt-injection is a real risk.",
        ] {
            let found = try #require(place([reply(teach(opening))]), "\(opening)")
            #expect(found.spoiled, "\(opening)")
        }
    }
}
