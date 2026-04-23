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
final class SSEDataDelegate: NSObject, URLSessionDataDelegate {
    typealias Continuation = AsyncThrowingStream<ChatStreamEvent, Error>.Continuation

    private let continuation: Continuation
    private var parser = SSEParser()
    private var buffer = Data()
    private var receivedResponse: HTTPURLResponse?
    private var nonSuccessBody = Data()

    init(continuation: Continuation) {
        self.continuation = continuation
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
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
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
            continuation.finish(throwing: APIClient.mapURLError(urlError))
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
