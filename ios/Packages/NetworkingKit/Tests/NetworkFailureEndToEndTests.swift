import Testing
import Foundation
@testable import NetworkingKit

// AUD-32 and AUD-30 through the real APIClient pipeline (StubURLProtocol):
// what a school network or captive portal puts in our place, the server's
// refusals with their reset time, and failures before and during a stream.
//
// An extension of `APIClientEndToEndTests` on purpose: every stubbed test
// shares the static `StubURLProtocol.handler`, so they all belong to that one
// `.serialized` suite.

private func makeClient(pathSatisfied: Bool? = true) -> APIClient {
    APIClient(
        environment: APIEnvironment(
            baseURL: URL(string: "https://stub.mercurius.test")!,
            requestTimeout: 2,
            streamingTimeout: 5
        ),
        sessionIdentity: SessionIdentity(),
        sessionConfiguration: stubbedSessionConfiguration(),
        pathSatisfied: { pathSatisfied }
    )
}

/// Every event until the stream ends, and the error it ended with.
private func collect(
    _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
) async -> (events: [ChatStreamEvent], error: Error?) {
    var events: [ChatStreamEvent] = []
    do {
        for try await event in stream { events.append(event) }
        return (events, nil)
    } catch {
        return (events, error)
    }
}

private func chat(_ client: APIClient) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    client.streamChat(messages: [ChatMessageDTO(role: "user", content: "hi")], sessionId: "sid")
}

/// The classroom-reliability lens's filter stand-in page.
private let blockPage = Data("""
    <html><head><title>Web Page Blocked</title></head><body><h1>This site is blocked by your school</h1></body></html>
    """.utf8)

private let chicagoAtAudit = LocalClock.pinned(utc: "2026-10-18T21:10:57Z", zone: "America/Chicago")

extension APIClientEndToEndTests {

    // MARK: - A page in our place (AUD-32)

    @Test("JSON route: a 200 text/html block page is the network, not 'an unexpected response'")
    func jsonBlockPage() async {
        StubURLProtocol.handler = { _ in .response(status: 200, headers: ["Content-Type": "text/html"], data: blockPage) }
        do {
            _ = try await makeClient().generateQuiz(sessionId: "sid")
            Issue.record("Expected a throw")
        } catch let error as APIError {
            #expect(error == .unreachableOnThisNetwork)
            #expect(error.isRetryable)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("Unit-test grade: a block page leaves the answer free to resubmit (retryable)")
    func gradeBlockPage() async {
        StubURLProtocol.handler = { _ in .response(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], data: blockPage) }
        do {
            _ = try await makeClient().gradeUnitDefense(
                sessionId: "sid", unitId: "unit_1", unitTitle: "U", defensePrompt: "P", answer: "A"
            )
            Issue.record("Expected a throw")
        } catch let error as APIError {
            // Was `.decoding`: not retryable, so the answer was locked.
            #expect(error == .unreachableOnThisNetwork)
            #expect(error.isRetryable)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("JSON route: a 200 page with no Content-Type is caught by its first byte")
    func jsonUntypedPage() async {
        StubURLProtocol.handler = { _ in .response(status: 200, data: Data("<!doctype html><p>Sign in to Wi-Fi</p>".utf8)) }
        await #expect(throws: APIError.unreachableOnThisNetwork) {
            _ = try await makeClient().generateQuiz(sessionId: "sid")
        }
    }

    @Test("Stream: a 200 text/html block page ends with the network error and no events")
    func streamBlockPage() async {
        StubURLProtocol.handler = { _ in .response(status: 200, headers: ["Content-Type": "text/html"], data: blockPage) }
        let (events, error) = await collect(chat(makeClient()))
        #expect(events.isEmpty)
        #expect(error as? APIError == .unreachableOnThisNetwork)
    }

    @Test("Stream: any 2xx that isn't an event stream is a page in our place")
    func streamWrongType() async {
        StubURLProtocol.handler = { _ in
            .response(status: 200, headers: ["Content-Type": "application/json"], data: Data(#"{"reply":"x"}"#.utf8))
        }
        let (events, error) = await collect(chat(makeClient()))
        #expect(events.isEmpty)
        #expect(error as? APIError == .unreachableOnThisNetwork)
    }

    @Test("Stream: an event stream with a charset parameter still streams")
    func streamWithCharset() async {
        StubURLProtocol.handler = { _ in
            .response(
                status: 200,
                headers: ["Content-Type": "text/event-stream; charset=utf-8"],
                data: Data((#"data: {"type":"complete","reply":"ok","mode":"socratic"}"# + "\n\n").utf8)
            )
        }
        let (events, error) = await collect(chat(makeClient()))
        #expect(error == nil)
        #expect(events == [.complete(ChatResponse(reply: "ok", mode: "socratic"))])
    }

    // MARK: - Refusals with the reset time (AUD-30)

    @Test("JSON 429 daily_limit: retryAfterSec becomes a local clock time, no Retry")
    func jsonDailyLimitClockTime() async {
        StubURLProtocol.handler = { _ in
            .response(
                status: 429,
                headers: ["Content-Type": "application/json", "Retry-After": "10143"],
                data: Data(#"{"error":"daily_limit","scope":"session","reply":"You've used today's lesson turns. Mercurius will be ready again tomorrow.","message":"You've used today's lesson turns. Mercurius will be ready again tomorrow.","retryAfterSec":10143}"#.utf8)
            )
        }
        do {
            _ = try await makeClient().generateQuiz(sessionId: "sid")
            Issue.record("Expected a throw")
        } catch let error as APIError {
            #expect(error == .quotaExceeded(
                message: "You've used today's lesson turns. Mercurius will be ready again tomorrow.",
                retryAfter: 10143,
                scope: "session"
            ))
            #expect(normalized(error.userFacingMessage(clock: chicagoAtAudit))
                == "You've used today's lesson turns. Try again after 7:00 PM.")
            #expect(!error.isRetryable)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("JSON 429 daily_limit for the network: cellular and Retry")
    func jsonNetworkDailyLimit() async {
        StubURLProtocol.handler = { _ in
            .response(
                status: 429,
                data: Data(#"{"error":"daily_limit","scope":"ip","reply":"Too many new sessions from this network today.","message":"Too many new sessions from this network today.","retryAfterSec":10143}"#.utf8)
            )
        }
        do {
            _ = try await makeClient().generateQuiz(sessionId: "sid")
            Issue.record("Expected a throw")
        } catch let error as APIError {
            #expect(error.isRetryable)
            #expect(normalized(error.userFacingMessage(clock: chicagoAtAudit))
                == "Too many new sessions from this network today. Switch to cellular data and try again, or come back after 7:00 PM.")
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("Stream: production's daily_limit refusal frame carries the wait the clock time comes from")
    func streamDailyLimitFrame() async {
        // sendRefusal in server.js: a 200 event stream, one error frame, [DONE].
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"error","code":"daily_limit","error":"You've used today's lesson turns. Mercurius will be ready again tomorrow.","retryAfterSec":10143}"# + "\n\n")
                stub.yield("data: [DONE]\n\n")
                stub.finish()
            }
        }
        let (events, error) = await collect(chat(makeClient()))
        #expect(error == nil)
        let refusal = events.first?.serverRefusal
        #expect(refusal?.retryAfter == 10143)
        #expect(refusal?.scope == nil)
        #expect(refusal?.isRetryable == false)
        #expect(refusal.map { normalized($0.studentMessage(clock: chicagoAtAudit)) }
            == "You've used today's lesson turns. Try again after 7:00 PM.")
    }

    @Test("Stream: the network's new-session refusal frame offers Retry and cellular")
    func streamNewSessionsFrame() async {
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"error","code":"daily_limit","error":"Too many new sessions from this network today.","retryAfterSec":10143}"# + "\n\n")
                stub.yield("data: [DONE]\n\n")
                stub.finish()
            }
        }
        let (events, _) = await collect(chat(makeClient()))
        let refusal = events.first?.serverRefusal
        #expect(refusal?.isNetworkScoped == true)
        #expect(refusal?.isRetryable == true)
    }

    @Test("JSON 503 service_disabled: the server's copy, no Retry")
    func jsonServiceDisabled() async {
        StubURLProtocol.handler = { _ in
            .response(
                status: 503,
                headers: ["Content-Type": "application/json"],
                data: Data(#"{"error":"service_disabled","reply":"Mercurius is taking a short break for maintenance. Please try again soon.","message":"Mercurius is temporarily paused — please try again soon."}"#.utf8)
            )
        }
        do {
            _ = try await makeClient().changeMode(to: .socratic, sessionId: "sid")
            Issue.record("Expected a throw")
        } catch let error as APIError {
            #expect(error == .serviceUnavailable(
                code: "service_disabled",
                message: "Mercurius is temporarily paused — please try again soon.",
                retryAfter: nil
            ))
            #expect(error.userFacingMessage == "Mercurius is temporarily paused — please try again soon.")
            #expect(!error.isRetryable)
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("Stream: the service_disabled frame is no-Retry too")
    func streamServiceDisabledFrame() async {
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"error","code":"service_disabled","error":"Mercurius is temporarily paused — please try again soon."}"# + "\n\n")
                stub.yield("data: [DONE]\n\n")
                stub.finish()
            }
        }
        let (events, _) = await collect(chat(makeClient()))
        #expect(events.first?.serverRefusal?.isRetryable == false)
        #expect(events.first?.serverRefusal?.studentMessage() == "Mercurius is temporarily paused — please try again soon.")
    }

    // MARK: - Timeouts and drops

    @Test("A timeout before the first byte with no connection timeline stays 'the server may be busy'")
    func timeoutBeforeFirstByte() async {
        // A stubbed load has no network transaction, so the phase is
        // unknown: never guess "your network" from a bare timeout. The real
        // connect-phase split runs over loopback sockets (LoopbackNetworkTests).
        StubURLProtocol.handler = { _ in .urlError(.timedOut) }
        await #expect(throws: APIError.timeout) {
            _ = try await makeClient(pathSatisfied: true).generateQuiz(sessionId: "sid")
        }
        let (events, error) = await collect(chat(makeClient(pathSatisfied: true)))
        #expect(events.isEmpty)
        #expect(error as? APIError == .timeout)
    }

    @Test("Stream: a drop mid-reply keeps the text that arrived, then ends as a dropped connection")
    func dropMidStream() async {
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"delta","text":"Tokens are"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(5))
                stub.fail(with: .networkConnectionLost)
            }
        }
        let (events, error) = await collect(chat(makeClient()))
        #expect(events == [.delta(text: "Tokens are")])
        #expect(error as? APIError == .connectionLost)
    }

    @Test("Stream: a timeout after the headers is a dropped connection, not a busy server")
    func timeoutMidStream() async {
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(": connected\n\n")
                stub.yield(#"data: {"type":"delta","text":"Tokens are"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(5))
                stub.fail(with: .timedOut)
            }
        }
        let (events, error) = await collect(chat(makeClient()))
        #expect(events == [.delta(text: "Tokens are")])
        #expect(error as? APIError == .connectionLost)
    }
}
