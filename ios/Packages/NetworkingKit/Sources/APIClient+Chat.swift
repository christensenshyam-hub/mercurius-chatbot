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
    /// Implementation notes:
    /// - We use a `URLSessionDataDelegate` (not `URLSession.bytes(for:)`)
    ///   because the latter has a documented buffering issue over HTTP/2
    ///   SSE on iOS 17 that can delay events by seconds or drop them
    ///   entirely.
    /// - Each call creates a dedicated `URLSession` with our delegate,
    ///   which is invalidated when the task completes. That's the
    ///   supported pattern for per-request delegates.
    public func streamChat(
        messages: [ChatMessageDTO],
        sessionId: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try Self.buildChatRequest(
                    baseURL: environmentBaseURL,
                    timeout: streamingTimeout,
                    messages: messages,
                    sessionId: sessionId
                )
            } catch {
                continuation.finish(throwing: error)
                return
            }

            let delegate = SSEDataDelegate(continuation: continuation)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = streamingTimeout
            config.timeoutIntervalForResource = streamingTimeout * 2
            config.waitsForConnectivity = false
            // Disable response caching — SSE responses should never be
            // cached, and cache lookups can delay delivery.
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            // Carry over any custom URLProtocol classes from the main
            // session configuration. This is how the test suite plumbs a
            // `StubURLProtocol` into the streaming path — set it once on
            // the APIClient's init and it reaches every URLSession the
            // client spins up, including this ephemeral one.
            if let customProtocols = urlSession.configuration.protocolClasses,
               !customProtocols.isEmpty {
                config.protocolClasses = customProtocols + (config.protocolClasses ?? [])
            }

            let session = URLSession(
                configuration: config,
                delegate: delegate,
                delegateQueue: nil
            )

            let task = session.dataTask(with: request)
            task.resume()

            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    // MARK: - Request construction

    private static func buildChatRequest(
        baseURL: URL,
        timeout: TimeInterval,
        messages: [ChatMessageDTO],
        sessionId: String
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-trace-id")

        struct Body: Encodable {
            let messages: [ChatMessageDTO]
            let sessionId: String
        }
        do {
            request.httpBody = try JSONEncoder().encode(Body(messages: messages, sessionId: sessionId))
        } catch {
            throw APIError.invalidRequest(reason: "Failed to encode chat body")
        }
        return request
    }
}
