import Foundation
import Testing
@testable import ChatFeature
@testable import LessonInteractives

/// The Page with a Secret's spoiler terms (refined from the slate's three;
/// docs/interactives/page-with-a-secret/CONTENT.md §4), through the real
/// placement: the guide's own wordings above the card spoil it, and so does
/// its whole Teach line (it names prompt injection) and the one recorded
/// first reply under the fix-prompts guide; "a parent or guardian" and the
/// agent loop alone don't. Why the card ships dark until the guide keeps the
/// risk out of the hook: CONTENT.md §4, "The risk".
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

    @Test("The card lands after the example's part, unspoiled, when the hook is the agent loop alone")
    func clean() throws {
        // The first half of the guide's Teach line, without its risks (a
        // shortened line, not the guide's own), and a lone "guardian".
        let found = try #require(place([reply(teach(
            "An agent = an LLM + tools + a loop (plan \u{2192} act \u{2192} observe \u{2192} repeat) pursuing a goal "
            + "(browse, run code, call apps, click). Ask a parent or guardian before you let one book anything."))]))
        #expect(found.card == .pageWithASecret)
        #expect(!found.spoiled)
    }

    @Test("The guide's Teach line, word for word, opens it spoiled: it names prompt injection")
    func teachLine() throws {
        // fix-prompts-2026-10 server.js, U8L1 "Teach:" (also on main).
        let teachLine = "An agent = an LLM + tools + a loop (plan \u{2192} act \u{2192} observe \u{2192} repeat) pursuing "
            + "a goal (browse, run code, call apps, click). It unlocks multi-step tasks but adds real risks: actions in "
            + "the world, prompt injection, compounding errors, and weak oversight."
        let found = try #require(place([reply(teach(teachLine))]))
        #expect(found.spoiled)
        let spec = try #require(InteractiveRegistry.spec(for: .pageWithASecret))
        #expect(spec.spoilerTerm(in: teachLine) == "prompt injection")
    }

    @Test("The recorded first reply under the fix-prompts guide opens it spoiled, from its hook")
    func recordedHook() throws {
        // v8-facts.json, u8_l1, run 0, reply 0: its opening, above its first
        // [EX] (the As-of note's "be hijacked" pulled the risk into the hook).
        let hook = "Here's something that might surprise you: a chatbot can already browse the web, run code, and "
            + "remember things across conversations \u{2014} and it can be hijacked by instructions hidden in a "
            + "webpage it reads.\n\nThat last part is real, and it happened to a major product. More on that in a moment."
        let found = try #require(place([reply(teach(hook))]))
        #expect(found.spoiled)
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
