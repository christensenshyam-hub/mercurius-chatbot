import Foundation

/// A URLProtocol subclass that intercepts HTTP requests and returns
/// canned responses — used end-to-end against the real `APIClient`
/// in tests. Covers the whole network path: URL construction, headers,
/// JSON body encoding, response decoding, status-code → `APIError`
/// mapping, and SSE framing via `SSEDataDelegate`.
///
/// Registration pattern — per-session, not global:
/// ```
/// let config: URLSessionConfiguration = .ephemeral
/// config.protocolClasses = [StubURLProtocol.self]
/// let client = APIClient(sessionConfiguration: config, ...)
/// ```
///
/// The `APIClient+Chat` streaming path copies `protocolClasses` from
/// the main session configuration so the stub intercepts streaming
/// requests too.
///
/// Tests set `StubURLProtocol.handler` to a closure that inspects the
/// incoming request and returns a `Mode`. The handler is static
/// (URLProtocol instances are constructed by URLSession), so suites
/// that use it must be `.serialized` to avoid test interleaving
/// stomping on each other's handler state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    enum Mode {
        /// One-shot HTTP response with a complete body.
        case response(status: Int, headers: [String: String] = [:], data: Data)

        /// Transport-level URLError (e.g. timeout, notConnected).
        case urlError(URLError.Code)

        /// Streaming response. Handler is called with the protocol
        /// instance and drives it by calling `yield(_:)` repeatedly
        /// and then `finish()` (or `fail(with:)`). The closure runs
        /// on a detached Task — use `try? await Task.sleep(...)` to
        /// interleave chunks.
        case stream((StubURLProtocol) async -> Void)
    }

    // Shared handler state. Reset between tests via `reset()`.
    private static let handlerLock = NSLock()
    private static var _handler: (@Sendable (URLRequest) -> Mode)?

    /// Thread-safe handler accessor.
    static var handler: (@Sendable (URLRequest) -> Mode)? {
        get {
            handlerLock.lock(); defer { handlerLock.unlock() }
            return _handler
        }
        set {
            handlerLock.lock(); defer { handlerLock.unlock() }
            _handler = newValue
        }
    }

    static func reset() { handler = nil }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        // Only claim requests while a handler is configured — otherwise
        // let the default HTTP protocol take them (prevents "unknown
        // protocol" errors in unrelated tests that share the process).
        handler != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        switch handler(request) {
        case let .response(status, headers, data):
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        case let .urlError(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))

        case let .stream(driver):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            // Hand control to the driver. Detached Task so URLSession's
            // internal loading queue doesn't block.
            Task { [weak self] in
                guard let self else { return }
                await driver(self)
            }
        }
    }

    override func stopLoading() {
        // URLSession calls this on cancel. No in-flight resources to
        // clean up — our writes are pure callbacks to the session.
    }

    // MARK: - Streaming helpers (called from Mode.stream drivers)

    func yield(_ data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    /// Convenience: yield a UTF-8 string. Caller is responsible for
    /// including any SSE framing (`"data: ...\n\n"`).
    func yield(_ text: String) {
        yield(Data(text.utf8))
    }

    func finish() {
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail(with code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
}

// MARK: - Request body extraction
//
// URLSession sometimes converts `httpBody` to `httpBodyStream` before
// dispatching to URLProtocol. Handlers call this to get the body
// consistently either way.

extension URLRequest {
    /// Returns the request's body as `Data`, whether it was set as
    /// `httpBody` directly or converted to `httpBodyStream` by
    /// URLSession. Returns empty data if neither is set.
    func bodyData() -> Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Session factory

/// Produce a URLSessionConfiguration that routes everything through
/// `StubURLProtocol`. Use for `APIClient.init(sessionConfiguration:)`.
func stubbedSessionConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    // Fast fails in tests; real clients use longer timeouts.
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 2
    return config
}
