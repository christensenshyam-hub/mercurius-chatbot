import Testing
import Foundation
@testable import NetworkingKit

// AUD-32 over real sockets: URLSession's own metrics, from real TCP and TLS
// on the loopback interface, decide how a timeout is classified. Each case
// waits out a one-second timeout.
//
// - A listener whose accept queue is full drops new SYNs, as a network that
//   swallows our traffic does: the request never connects.
// - A listener that accepts and never answers is a connected server that
//   stalls (over https, the TLS hello is swallowed instead: never connected).
// - A server that sends the stream's headers and a first frame, then goes
//   quiet, is a connection lost mid-reply.

@Suite("APIClient over loopback sockets: timeouts by connection phase")
struct LoopbackNetworkTests {

    private func client(port: UInt16, scheme: String = "http", pathSatisfied: Bool?) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]   // never via a system proxy
        return APIClient(
            environment: APIEnvironment(
                baseURL: URL(string: "\(scheme)://127.0.0.1:\(port)")!,
                requestTimeout: 1,
                streamingTimeout: 1
            ),
            sessionIdentity: SessionIdentity(),
            sessionConfiguration: config,
            pathSatisfied: { pathSatisfied }
        )
    }

    private func quizError(_ client: APIClient) async -> APIError? {
        do {
            _ = try await client.generateQuiz(sessionId: "sid")
            return nil
        } catch {
            return error as? APIError
        }
    }

    private func streamOutcome(_ client: APIClient) async -> (events: [ChatStreamEvent], error: APIError?) {
        var events: [ChatStreamEvent] = []
        do {
            for try await event in client.streamChat(
                messages: [ChatMessageDTO(role: "user", content: "hi")], sessionId: "sid"
            ) {
                events.append(event)
            }
            return (events, nil)
        } catch {
            return (events, error as? APIError)
        }
    }

    @Test("SYNs dropped on a working path: the network, on the JSON route and the stream")
    func dropsSYNs() async throws {
        let server = try LoopbackServer(.dropSYNs)
        defer { server.stop() }
        #expect(await quizError(client(port: server.port, pathSatisfied: true)) == .unreachableOnThisNetwork)
        #expect(await streamOutcome(client(port: server.port, pathSatisfied: true)).error == .unreachableOnThisNetwork)
    }

    @Test("SYNs dropped with no path is offline; with the path unknown it stays a timeout")
    func dropsSYNsPathStates() async throws {
        let server = try LoopbackServer(.dropSYNs)
        defer { server.stop() }
        #expect(await quizError(client(port: server.port, pathSatisfied: false)) == .offline)
        #expect(await quizError(client(port: server.port, pathSatisfied: nil)) == .timeout)
    }

    @Test("Connected but no answer: 'the server may be busy', never 'your network'")
    func connectedSilence() async throws {
        let server = try LoopbackServer(.acceptSilently)
        defer { server.stop() }
        #expect(await quizError(client(port: server.port, pathSatisfied: true)) == .timeout)
        #expect(await streamOutcome(client(port: server.port, pathSatisfied: true)).error == .timeout)
    }

    @Test("TLS hello swallowed: never connected, so the network")
    func tlsSwallowed() async throws {
        let server = try LoopbackServer(.acceptSilently)
        defer { server.stop() }
        #expect(await quizError(client(port: server.port, scheme: "https", pathSatisfied: true)) == .unreachableOnThisNetwork)
    }

    @Test("Headers and a first frame, then silence: the reply so far, then a dropped connection")
    func stallAfterHeaders() async throws {
        let server = try LoopbackServer(.headersThenStall)
        defer { server.stop() }
        let outcome = await streamOutcome(client(port: server.port, pathSatisfied: true))
        #expect(outcome.events == [.delta(text: "Tokens are")])
        #expect(outcome.error == .connectionLost)
    }
}

/// A TCP listener on 127.0.0.1 with one misbehaviour.
private final class LoopbackServer: @unchecked Sendable {
    enum Behaviour {
        /// Accept queue full, never accepting: new SYNs are dropped.
        case dropSYNs
        /// Accept every connection, never read or write.
        case acceptSilently
        /// Answer with event-stream headers and one delta frame, then go quiet.
        case headersThenStall
    }

    struct SocketError: Error { let step: String; let code: Int32 }

    let port: UInt16
    private let listener: Int32
    private let lock = NSLock()
    private var open: [Int32] = []
    private var stopped = false

    init(_ behaviour: Behaviour) throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError(step: "socket", code: errno) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        guard Self.withSockaddr(&address, { bind(fd, $0, $1) }) == 0 else {
            throw SocketError(step: "bind", code: errno)
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        listener = fd
        port = UInt16(bigEndian: address.sin_port)

        switch behaviour {
        case .dropSYNs:
            // A backlog of one, filled by one connection nobody accepts:
            // the kernel drops every SYN after it, without a reset.
            guard listen(fd, 1) == 0 else { throw SocketError(step: "listen", code: errno) }
            let filler = socket(AF_INET, SOCK_STREAM, 0)
            guard Self.withSockaddr(&address, { connect(filler, $0, $1) }) == 0 else {
                throw SocketError(step: "connect filler", code: errno)
            }
            track(filler)
        case .acceptSilently, .headersThenStall:
            guard listen(fd, 16) == 0 else { throw SocketError(step: "listen", code: errno) }
            let answers = behaviour == .headersThenStall
            Thread.detachNewThread { [self] in acceptLoop(answering: answers) }
        }
    }

    private static func withSockaddr(
        _ address: inout sockaddr_in,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32
    ) -> Int32 {
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let fds = open
        open = []
        lock.unlock()
        fds.forEach { close($0) }
        close(listener)
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func track(_ fd: Int32) {
        lock.lock()
        open.append(fd)
        lock.unlock()
    }

    private func acceptLoop(answering: Bool) {
        while !isStopped {
            var poller = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 100) > 0, !isStopped else { continue }
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { continue }
            track(connection)
            if answering { answer(connection) }
        }
    }

    private func answer(_ connection: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        _ = read(connection, &buffer, buffer.count)
        let frame = #"data: {"type":"delta","text":"Tokens are"}"# + "\n\n"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n"
            + String(frame.utf8.count, radix: 16) + "\r\n" + frame + "\r\n"
        let bytes = Array(response.utf8)
        _ = bytes.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
    }
}
