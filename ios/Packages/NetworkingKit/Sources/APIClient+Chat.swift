import Foundation

extension APIClient {
    /// Stream a chat response from the server.
    ///
    /// Returns an `AsyncThrowingStream` that yields `ChatStreamEvent`s as
    /// they arrive. The stream:
    /// - emits zero or more `.delta` events as text chunks arrive,
    /// - emits exactly one `.complete` event when the server finishes,
    /// - or emits one `.streamError` if the server reports a recoverable
    ///   error mid-stream,
    /// - or throws `APIError` if the transport fails.
    ///
    /// The stream is cancellable: if the consuming task is cancelled,
    /// the underlying URLSession request is cancelled too.
    ///
    /// - Parameters:
    ///   - messages: full conversation history to send (incl. the new
    ///     user message as the last item).
    ///   - sessionId: the current device's session identifier.
    public func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStream(
                        messages: messages,
                        sessionId: sessionId,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: APIError.cancelled)
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch let error as URLError {
                    continuation.finish(throwing: Self.mapURLError(error))
                } catch {
                    continuation.finish(throwing: APIError.unknown(underlying: String(describing: error)))
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStream(
        messages: [ChatMessageDTO],
        sessionId: String,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        let url = environmentBaseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = streamingTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-trace-id")

        let body = ChatRequestBody(messages: messages, sessionId: sessionId)
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(underlying: "Non-HTTP response")
        }

        // If the server returned a non-200 response, it's JSON (not SSE).
        // Read the full body, then translate to an APIError.
        if !(200...299).contains(http.statusCode) {
            let data = try await Self.drain(bytes: bytes)
            try APIClient.validate(statusCode: http.statusCode, data: data)
            return  // unreachable — validate threw
        }

        var parser = SSEParser()
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }

            guard let payload = parser.append(line: line) else { continue }
            if let event = try parseChatEvent(from: payload) {
                continuation.yield(event)
            }
        }
    }

    private static func drain(bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 64_000 { break }  // defend against runaway bodies
        }
        return data
    }
}
