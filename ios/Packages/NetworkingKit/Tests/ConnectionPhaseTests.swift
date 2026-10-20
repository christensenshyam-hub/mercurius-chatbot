import Testing
import Foundation
@testable import NetworkingKit

// AUD-32: a timeout is classified by how far the request got. A network
// that never let us connect is named as the network; a connected request
// with no headers keeps "the server may be busy" (that can be a real server
// stall: headers only go out after the database and the gate); a timeout
// after the headers is a dropped connection.

@Suite("ConnectionPhase from a transaction's timeline")
struct ConnectionPhaseTimelineTests {

    @Test("No connect or TLS end: still connecting")
    func neverConnected() {
        #expect(ConnectionTimeline().phase == .connecting)
        // TCP up but the TLS hello swallowed.
        #expect(ConnectionTimeline(connectEnded: true).phase == .connecting)
    }

    @Test("TCP + TLS done, or plain TCP for http: awaiting the response")
    func connected() {
        #expect(ConnectionTimeline(connectEnded: true, secureConnectionEnded: true).phase == .awaitingResponse)
        #expect(ConnectionTimeline(isSecure: false, connectEnded: true).phase == .awaitingResponse)
    }

    @Test("A reused connection or a request on its way counts as connected")
    func reusedOrRequestStarted() {
        // A reused connection has no connect dates of its own.
        #expect(ConnectionTimeline(isReusedConnection: true).phase == .awaitingResponse)
        #expect(ConnectionTimeline(requestStarted: true).phase == .awaitingResponse)
    }

    @Test("Response headers in: receiving")
    func receiving() {
        #expect(ConnectionTimeline(connectEnded: true, secureConnectionEnded: true,
                                   requestStarted: true, responseStarted: true).phase == .receivingResponse)
    }

    @Test("Not a network load (a stub, a cache): unknown")
    func notNetwork() {
        #expect(ConnectionTimeline(isNetworkLoad: false).phase == .unknown)
        #expect(ConnectionTimeline(isNetworkLoad: false, responseStarted: true).phase == .unknown)
    }
}

@Suite("APIClient URL error mapping by connection phase")
struct APIClientPhaseMappingTests {

    private let timedOut = URLError(.timedOut)

    @Test("A timeout that never connected, on a working path, is the network")
    func neverConnectedOnline() {
        let error = APIClient.mapURLError(timedOut, pathSatisfied: true, phase: .connecting)
        #expect(error == .unreachableOnThisNetwork)
        #expect(error.isRetryable)
        #expect(error.userFacingMessage.contains("network may be blocking Mercurius"))
        #expect(error.userFacingMessage.contains(NetworkSwitchAdvice.current.tryAnotherNetwork))
    }

    @Test("A timeout that never connected with no network path is offline")
    func neverConnectedOffline() {
        #expect(APIClient.mapURLError(timedOut, pathSatisfied: false, phase: .connecting) == .offline)
    }

    @Test("A timeout that never connected with the path unknown stays a timeout")
    func neverConnectedUnknownPath() {
        #expect(APIClient.mapURLError(timedOut, pathSatisfied: nil, phase: .connecting) == .timeout)
    }

    @Test("Connected but no headers keeps 'the server may be busy', whatever the path")
    func serverStall() {
        for path in [true, false, nil] as [Bool?] {
            #expect(APIClient.mapURLError(timedOut, pathSatisfied: path, phase: .awaitingResponse) == .timeout)
        }
    }

    @Test("A timeout after the headers is a dropped connection")
    func afterHeaders() {
        let error = APIClient.mapURLError(timedOut, pathSatisfied: true, phase: .receivingResponse)
        #expect(error == .connectionLost)
        #expect(error.isRetryable)
    }

    @Test("With no phase to read, a timeout stays a timeout (the old mapping)")
    func unknownPhase() {
        #expect(APIClient.mapURLError(timedOut) == .timeout)
        #expect(APIClient.mapURLError(timedOut, pathSatisfied: true) == .timeout)
    }

    @Test("Other codes ignore the phase")
    func otherCodes() {
        #expect(APIClient.mapURLError(URLError(.networkConnectionLost), pathSatisfied: true, phase: .connecting) == .connectionLost)
        #expect(APIClient.mapURLError(URLError(.notConnectedToInternet), pathSatisfied: true, phase: .connecting) == .offline)
        #expect(APIClient.mapURLError(URLError(.cannotFindHost), pathSatisfied: true, phase: .receivingResponse) == .unreachableOnThisNetwork)
        #expect(APIClient.mapURLError(URLError(.cancelled), pathSatisfied: true, phase: .connecting) == .cancelled)
    }
}

@Suite("APIClient: a 2xx page that isn't ours")
struct InterceptedPageTests {

    private func response(_ status: Int, _ contentType: String?) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://mercurius.test/api/quiz")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: contentType.map { ["Content-Type": $0] } ?? [:]
        )!
    }

    @Test("A 2xx HTML page is a block or sign-in page", arguments: [
        "text/html", "text/html; charset=utf-8", "TEXT/HTML", "application/xhtml+xml",
    ])
    func htmlByType(contentType: String) {
        #expect(APIClient.isInterceptedPage(response(200, contentType), data: Data("<html></html>".utf8)))
    }

    @Test("A 2xx body that starts like markup is one too, whatever its type says")
    func htmlBySniff() {
        #expect(APIClient.isInterceptedPage(response(200, nil), data: Data("\n  <!DOCTYPE html><html>".utf8)))
        #expect(APIClient.isInterceptedPage(response(200, "text/plain"), data: Data("<html>".utf8)))
        #expect(APIClient.isInterceptedPage(response(200, "application/json"), data: Data("\u{FEFF}<html>".utf8)))
    }

    @Test("Our JSON, an empty body and non-2xx statuses are not")
    func notIntercepted() {
        #expect(!APIClient.isInterceptedPage(response(200, "application/json; charset=utf-8"), data: Data(#"{"ok":true}"#.utf8)))
        #expect(!APIClient.isInterceptedPage(response(200, nil), data: Data(#"  [1,2]"#.utf8)))
        #expect(!APIClient.isInterceptedPage(response(204, nil), data: Data()))
        // A non-2xx page is `validate`'s to classify.
        #expect(!APIClient.isInterceptedPage(response(403, "text/html"), data: Data("<html>".utf8)))
    }
}
