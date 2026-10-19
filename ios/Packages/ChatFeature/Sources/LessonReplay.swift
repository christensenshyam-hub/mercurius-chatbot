#if DEBUG
import Foundation
import NetworkingKit

/// DEBUG `-LessonReplay`: a lesson whose replies are the first three turns
/// of a real recorded Unit 1, Lesson 1 session
/// (docs/evals/pacing-demo-capture-lesson1.json, run 2 — the same session the
/// marketing demo replays), streamed in small chunks at a realistic pace. It
/// lets the lesson screen's layout and scrolling be screenshotted without a
/// network call or a model bill.
///
/// - `-LessonReplayCut`: the first reply drops mid-stream (connection lost),
///   to show a cut-off reply.
/// - `-LessonReplayFailEmpty`: the first reply fails before any text, to show
///   a failure with nothing streamed.
/// - `-LessonReplaySlow`: stream four times slower, to catch it mid-reply.
/// - `-LessonReplayShort`: only each reply's opening paragraphs, so a whole
///   turn (and a cut-off reply's captions) fits on one screen.
/// - `-LessonReplayNetwork <scenario>`: no replies; every request goes
///   through the real `APIClient` and gets a failure production or a school
///   network sends (see `NetworkScenario`).
enum LessonReplay {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-LessonReplay")
    }

    @MainActor
    static func makeModel() -> ChatViewModel {
        let args = ProcessInfo.processInfo.arguments
        let replay = LessonReplayClient(
            cutFirstReply: args.contains("-LessonReplayCut"),
            failFirstReplyEmpty: args.contains("-LessonReplayFailEmpty"),
            short: args.contains("-LessonReplayShort"),
            chunkDelay: .milliseconds(args.contains("-LessonReplaySlow") ? 200 : 50)
        )
        let model = ChatViewModel(
            chatClient: NetworkScenario.requested.map { $0.makeClient() as ChatStreaming } ?? replay,
            modeClient: LessonReplayModeClient(),
            sessionIdProvider: { "debug-lesson-replay" },
            store: nil,
            hydrateOnInit: false
        )
        model.awaitsLessonStart = true
        return model
    }

    /// Recorded replies, verbatim (blocks_v1 markup included).
    static let replies: [String] = [
        #"""
        Here's a wild fact to kick us off:

        The sentence "I went to the bank" contains one word that could mean a riverbank or a financial institution — and an LLM has to figure out which one *without* looking it up anywhere.

        How does it do that? It starts by breaking your words into pieces.

        ---

        **Tokenization** is the first thing that happens the moment you hit send.

        Your prompt doesn't enter the model as words — it gets sliced into chunks called *tokens*, which are then converted into numbers.

        [EX]GPT-4 uses a vocabulary of roughly 100,000 tokens. The word "unbelievable" might become three tokens: "un", "believ", "able". A short word like "cat" is one token. An emoji might be several.[/EX]

        [KEY]Tokenization converts your text into a sequence of numbers — that's the only form an LLM can actually process.[/KEY]

        Those numbers then get mapped into a high-dimensional mathematical space where words with similar meanings end up *near* each other — so "bank" (financial) clusters near "loan" and "deposit," while "bank" (river) clusters near "shore" and "water." That's how the model starts resolving ambiguity before it even generates a word.

        ---

        [Q]
        What is a token in the context of an LLM?
        A) A full sentence the model reads at once
        B) A chunk of text converted into a number the model can process
        C) A copy of a word stored in the model's memory
        ANS: B
        [/Q]
        """#,
        #"""
        Exactly right — and you've already got the key insight that trips most people up: the model never "reads" words the way you do. It's all numbers from the start.

        Now, once your prompt is tokenized, what does the model actually *do* with those numbers?

        ---

        This is where **next-token prediction** comes in.

        The model's entire job — at every single step — is to answer one question: *given everything before this point, what token is most likely to come next?*

        It does this over and over, one token at a time, until it finishes its response.

        [EX]Feed a model the tokens for "The cat sat on the ___" and it will assign high probability to "mat", "floor", "couch" — and near-zero probability to "democracy" or "seventeen." It picks from the high-probability options and moves on to predicting the *next* next token.[/EX]

        [KEY]An LLM generates responses by repeatedly predicting the single most probable next token — it is never "looking up" a stored answer.[/KEY]

        This is why AI can sound fluent and confident even when it's wrong: it's optimizing for *what sounds likely to come next*, not for *what is true*.

        ---

        [Q]
        Why can an LLM sound confident but still be factually wrong?
        A) It hasn't been trained on enough data yet
        B) It predicts what text is plausible, not what is true
        C) It looks up answers too quickly to check them
        ANS: B
        [/Q]
        """#,
        #"""
        Close instinct — but that's actually the most common misconception about LLMs, so let's fix it.

        The model isn't looking anything up at all. There's no database, no search, no retrieval happening. It generates each token purely from patterns compressed during training — like a very sophisticated autocomplete.

        Think of it this way: when you finish someone's sentence because you've heard that kind of sentence a thousand times, you're not checking a fact — you're pattern-matching. That's exactly what the model does, at massive scale.

        So confidence comes from *plausibility*, not accuracy. A token sequence that sounds authoritative was probably common in training data — which means the model learned to produce it fluently, whether or not it's true.

        ---

        Now let's put both concepts together — tokenization and next-token prediction — and see if you can apply them.

        Here's your exercise:

        ---

        **Exercise**

        Look at this sentence:

        *"The surgeon picked up her ___."*

        Your job has two parts:

        **Part 1:** Predict which words an LLM would assign *high* probability to as the next token, and which it would assign *low* probability to. Give at least two examples of each.

        **Part 2:** Explain *why* the model assigns those probabilities — what about tokenization and next-token prediction explains the pattern you see?

        Take your best shot — there's no single right answer here, just good reasoning.
        """#,
    ]
}

/// Streams `LessonReplay.replies` — the Nth reply for a request that already
/// carries N of Merc's turns.
private struct LessonReplayClient: ChatStreaming {
    let cutFirstReply: Bool
    let failFirstReplyEmpty: Bool
    var short = false
    let chunkDelay: Duration

    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String,
        responseMode: ResponseMode,
        imageId: String?
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let turn = messages.filter { $0.role == "assistant" }.count
        let recorded = LessonReplay.replies[min(turn, LessonReplay.replies.count - 1)]
        let reply = short
            ? recorded.components(separatedBy: "\n\n").prefix(2).joined(separator: "\n\n")
            : recorded
        let isFirst = turn == 0
        let cut = cutFirstReply && isFirst
        let failEmpty = failFirstReplyEmpty && isFirst
        let delay = chunkDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(700))   // time to first token
                if failEmpty {
                    continuation.finish(throwing: APIError.connectionLost)
                    return
                }
                let words = reply.split(separator: " ", omittingEmptySubsequences: false)
                let stop = cut ? words.count * 3 / 5 : words.count
                var index = 0
                while index < stop {
                    if Task.isCancelled { return }
                    let end = min(index + 4, stop)
                    var chunk = words[index..<end].joined(separator: " ")
                    if end < words.count { chunk += " " }
                    continuation.yield(.delta(text: chunk))
                    index = end
                    try? await Task.sleep(for: delay)
                }
                if cut {
                    continuation.finish(throwing: APIError.connectionLost)
                    return
                }
                continuation.yield(.complete(ChatResponse(reply: reply, mode: "socratic")))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct LessonReplayModeClient: ModeChanging {
    func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange {
        throw APIError.unknown(underlying: "The lesson replay never changes mode.")
    }
}
#endif
