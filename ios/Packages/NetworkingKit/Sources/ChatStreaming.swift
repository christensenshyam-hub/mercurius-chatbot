import Foundation

/// The narrow protocol that `ChatViewModel` depends on — only the chat
/// streaming method. Keeping this tiny means tests can supply a stub
/// without implementing the full `APIClient` surface.
public protocol ChatStreaming: Sendable {
    func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension APIClient: ChatStreaming {}
