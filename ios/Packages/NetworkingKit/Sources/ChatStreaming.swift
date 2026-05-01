import Foundation

/// The narrow protocol that `ChatViewModel` depends on — only the chat
/// streaming method. Keeping this tiny means tests can supply a stub
/// without implementing the full `APIClient` surface.
///
/// `responseMode` is the length/depth dial — see `ResponseMode`. Defaults
/// to `.concise` so existing call sites that don't care about it stay
/// readable.
public protocol ChatStreaming: Sendable {
    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String,
        responseMode: ResponseMode
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

public extension ChatStreaming {
    /// Default-`responseMode` overload so existing tests / call sites
    /// that don't yet pass it continue to compile. Routes to the
    /// required method with `.concise`.
    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        streamChat(messages: messages, sessionId: sessionId, responseMode: .concise)
    }
}

extension APIClient: ChatStreaming {}
