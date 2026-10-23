#if os(macOS) && DEBUG
import Foundation
import NetworkingKit
import PersistenceKit

/// DEBUG `-NightChatDemo YES` (screenshots only): a Socratic thread made of
/// the first three turns of a real recorded session, verbatim
/// (docs/evals/pacing-gate8-flag-off.json, run 2, "socratic-1"): Merc's last
/// reply cites a source with the tag production sends today and closes on a
/// question, so the Night chat's source chip and Your turn card show. It is
/// written to the in-memory chat store the harness runs with (`-UITests`),
/// never to disk, and nothing is sent.
enum MacNightDemo {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "NightChatDemo")
    }

    /// The thread, oldest first: (role, text).
    static let turns: [(String, String)] = [
        ("user", "How does an LLM actually generate its answers?"),
        ("assistant", """
        Here's the core mechanism: an LLM doesn't "know" answers — it **predicts the next token** (roughly, the next word-chunk) based on patterns learned from massive amounts of text.

        Every word it outputs is a probability distribution over what comes next, given everything before it.

        So when you ask me a question, I'm not retrieving a stored fact — I'm generating a sequence of tokens that statistically "fit" after your input, based on patterns in training data.

        Here's what's worth sitting with: if I'm just predicting likely next tokens, why does that ever produce *true* answers?
        """),
        ("user", "I think it predicts the next word based on patterns it learned?"),
        ("assistant", """
        That's right — and you've got the core idea.

        Now here's the thing worth pushing on: patterns in text tend to reflect *true* things, because humans mostly write true things.

        But "mostly true" and "always true" are very different — so what do you think happens when I generate text about something that's *rare or underrepresented* in my training data?
        """),
        ("user", "So it doesn't really 'know' facts — it just produces likely text?"),
        ("assistant", """
        Exactly — and that distinction has a name worth knowing: **hallucination**.

        When I generate text about something rare or poorly represented, I produce fluent, confident-sounding output that can be completely fabricated — because fluency is what I'm optimized for, not truth.

        [SOURCE: "On the Dangers of Stochastic Parrots" — dl.acm.org/doi/10.1145/3442188.3445922]

        So here's the uncomfortable follow-up: right now, in this conversation, how would you know if I just hallucinated something?
        """),
    ]

    /// Writes the thread to `store` and returns its id.
    @MainActor @discardableResult
    static func seed(_ store: ChatStore) -> UUID {
        let id = store.createConversation(mode: .socratic)
        let start = Date().addingTimeInterval(-20 * 60)
        for (index, turn) in turns.enumerated() {
            store.append(StoredMessage(id: UUID(), role: turn.0, content: turn.1,
                                       createdAt: start.addingTimeInterval(TimeInterval(index * 40))),
                         to: id)
        }
        return id
    }
}
#endif
