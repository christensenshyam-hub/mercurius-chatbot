import Foundation

/// URLSession data delegate that streams SSE events via an
/// `AsyncThrowingStream` continuation.
///
/// We use a delegate-based approach instead of `URLSession.bytes(for:)`
/// because the latter exhibits a buffering bug over HTTP/2 SSE on
/// iOS 17: chunks arrive at the server but aren't yielded to the
/// client until the connection closes, making streaming appear empty
/// for seconds. The delegate API delivers bytes in `didReceive data:`
/// callbacks as soon as the network layer has them, regardless of
/// HTTP version or chunk framing.
///
/// Every callback arrives on the session's serial delegate queue (the
/// session is made with `delegateQueue: nil`), so the state below needs no
/// lock.
final class SSEDataDelegate: NSObject, URLSessionDataDelegate {
    typealias Continuation = AsyncThrowingStream<ChatStreamEvent, Error>.Continuation

    private let continuation: Continuation
    private let pathSatisfied: @Sendable () -> Bool?
    private var parser = SSEParser()
    private var buffer = Data()
    private var receivedResponse: HTTPURLResponse?
    private var nonSuccessBody = Data()
    /// A 2xx that wasn't an event stream: a page put in our place.
    private var intercepted = false
    /// How far the request got, from the task's metrics (they arrive before
    /// the task completes).
    private var metricsPhase: ConnectionPhase = .unknown

    init(continuation: Continuation, pathSatisfied: @escaping @Sendable () -> Bool?) {
        self.continuation = continuation
        self.pathSatisfied = pathSatisfied
        super.init()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        receivedResponse = response as? HTTPURLResponse
        // /api/chat answers every 2xx — a reply or a refusal frame — as
        // text/event-stream. Anything else is a page a school filter or a
        // captive portal put in our place (often after a redirect). Parsing
        // it would end in "the server closed the connection"; stop here and
        // name the network instead (AUD-32).
        if let http = receivedResponse, (200...299).contains(http.statusCode),
           http.mimeType?.lowercased() != "text/event-stream" {
            intercepted = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        metricsPhase = ConnectionPhase(metrics: metrics)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        // A page in our place is never parsed (its task is being cancelled).
        if intercepted { return }

        // If the response is a non-2xx error, accumulate and translate
        // on completion — don't attempt to parse SSE.
        if let status = receivedResponse?.statusCode, !(200...299).contains(status) {
            nonSuccessBody.append(data)
            if nonSuccessBody.count > 64_000 {
                dataTask.cancel()  // runaway body guard
            }
            return
        }

        buffer.append(data)
        drainBuffer()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer { session.finishTasksAndInvalidate() }

        if intercepted {
            continuation.finish(throwing: APIError.unreachableOnThisNetwork)
            return
        }

        // Non-success response: translate status to APIError.
        if let status = receivedResponse?.statusCode, !(200...299).contains(status) {
            do {
                try APIClient.validate(statusCode: status, data: nonSuccessBody)
            } catch {
                continuation.finish(throwing: error)
                return
            }
        }

        if let urlError = error as? URLError {
            // Headers in hand means the stream had started, whatever the
            // metrics say; otherwise the metrics tell how far it got.
            let phase: ConnectionPhase = receivedResponse != nil ? .receivingResponse : metricsPhase
            continuation.finish(throwing: APIClient.mapURLError(
                urlError, pathSatisfied: pathSatisfied(), phase: phase))
            return
        }
        if let error {
            continuation.finish(throwing: APIError.unknown(underlying: String(describing: error)))
            return
        }

        // Flush any trailing bytes that didn't end with a newline.
        if !buffer.isEmpty {
            drainBuffer(flushTrailing: true)
        }
        continuation.finish()
    }

    // MARK: - SSE framing

    /// Parse complete lines out of the buffer and dispatch events.
    private func drainBuffer(flushTrailing: Bool = false) {
        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)

            // Strip a trailing \r if present (CRLF line endings).
            let trimmed: Data
            if lineData.last == 0x0D {
                trimmed = lineData.subdata(in: 0..<(lineData.count - 1))
            } else {
                trimmed = lineData
            }

            guard let line = String(data: trimmed, encoding: .utf8) else {
                continue  // skip non-UTF8 lines rather than failing the stream
            }

            dispatch(line: line)
        }

        if flushTrailing, !buffer.isEmpty,
           let line = String(data: buffer, encoding: .utf8) {
            dispatch(line: line)
            buffer.removeAll(keepingCapacity: false)
        }
    }

    private func dispatch(line: String) {
        guard let payload = parser.append(line: line) else { return }
        do {
            if let event = try parseChatEvent(from: payload) {
                continuation.yield(event)
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
