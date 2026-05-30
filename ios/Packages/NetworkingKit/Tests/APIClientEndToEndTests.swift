import Testing
import Foundation
@testable import NetworkingKit

// End-to-end tests for the real `APIClient` against a `StubURLProtocol`.
//
// Distinct from the existing `APIClientTests` (which unit-test pure
// helpers like `validate(statusCode:)`): these tests drive actual
// URLSession round-trips through the full pipeline. Every call exercises
// request building, headers, JSON encoding, URLSession dispatch, the
// HTTPURLResponse → `APIError` mapping, and either one-shot decoding or
// SSE framing via `URLSessionDataDelegate` + `SSEParser`.
//
// These are the tests that would have caught the iOS 17 HTTP/2 SSE
// buffering bug — they drive real bytes through the streaming path.
//
// URLProtocol handler state is shared across tests, so the suite is
// `.serialized`. Each test resets the handler in setUp via a helper.

// MARK: - Fixtures

private let testSessionId = "sess_abcdef1234567890"

private let uploadResponseJSON = #"""
{
  "id": "abc123_TOKEN-xyz",
  "url": "/api/images/abc123_TOKEN-xyz",
  "contentType": "image/jpeg",
  "fileName": "photo.jpg",
  "size": 12345,
  "createdAt": "2026-05-30T12:00:00.000Z"
}
"""#

/// Build an APIClient pointed at a fake base URL, with URLSession
/// pinned to `StubURLProtocol`. Session identity is irrelevant to
/// these tests — the server would normally read it, but our stub
/// just inspects the URL + body.
private func makeTestAPIClient() -> APIClient {
    let env = APIEnvironment(
        baseURL: URL(string: "https://stub.mercurius.test")!,
        requestTimeout: 2,
        streamingTimeout: 5
    )
    return APIClient(
        environment: env,
        sessionIdentity: SessionIdentity(),
        sessionConfiguration: stubbedSessionConfiguration()
    )
}

// MARK: - End-to-end tests
//
// All end-to-end tests share the same static `StubURLProtocol.handler`,
// so they must run one at a time. `.serialized` only guarantees
// serialization _within_ a suite — two `.serialized` suites still run
// in parallel with each other and step on each other's handler state.
// Merged into a single suite so the whole batch runs serially.

@Suite("APIClient end-to-end", .serialized)
struct APIClientEndToEndTests {

    init() { StubURLProtocol.reset() }

    @Test("checkHealth: 200 with {\"status\":\"ok\"} → true")
    func healthOK() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/health")
            #expect(request.httpMethod == "GET")
            return .response(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(#"{"status":"ok","timestamp":"2026-04-22T00:00:00Z"}"#.utf8)
            )
        }

        let client = makeTestAPIClient()
        let ok = await client.checkHealth()
        #expect(ok)
    }

    @Test("checkHealth: 500 → false (not a crash)")
    func healthServerError() async {
        StubURLProtocol.handler = { _ in
            .response(status: 500, data: Data(#"{"error":"boom"}"#.utf8))
        }
        let client = makeTestAPIClient()
        #expect(await client.checkHealth() == false)
    }

    @Test("checkHealth: transport error → false")
    func healthTransportError() async {
        StubURLProtocol.handler = { _ in .urlError(.notConnectedToInternet) }
        let client = makeTestAPIClient()
        #expect(await client.checkHealth() == false)
    }

    @Test("generateQuiz: happy path decodes the full server shape")
    func quizHappyPath() async throws {
        let quizJSON = #"""
        {
          "title": "Ethics Check-in",
          "questions": [
            {
              "q": "What is the alignment problem?",
              "options": ["A) Code bugs", "B) Value misalignment", "C) Hardware failures", "D) Slow training"],
              "answer": "B",
              "explanation": "The alignment problem is about AI behavior diverging from human values."
            },
            {
              "q": "What are 'emergent' capabilities?",
              "options": ["A) Bugs", "B) Abilities not explicitly programmed", "C) API features", "D) Training artifacts"],
              "answer": "B",
              "explanation": "Emergent capabilities appear at scale without explicit training."
            }
          ]
        }
        """#
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/quiz")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return .response(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(quizJSON.utf8)
            )
        }

        let client = makeTestAPIClient()
        let quiz = try await client.generateQuiz(sessionId: testSessionId)
        #expect(quiz.title == "Ethics Check-in")
        #expect(quiz.questions.count == 2)
        #expect(quiz.questions[0].answer == "B")
    }

    @Test("generateQuiz: 401 surfaces as APIError.unauthorized")
    func quizUnauthorized() async {
        StubURLProtocol.handler = { _ in
            .response(status: 401, data: Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let client = makeTestAPIClient()
        do {
            _ = try await client.generateQuiz(sessionId: testSessionId)
            Issue.record("Expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            Issue.record("Expected .unauthorized, got \(error)")
        }
    }

    @Test("generateQuiz: 429 surfaces as APIError.rateLimited")
    func quizRateLimited() async {
        StubURLProtocol.handler = { _ in .response(status: 429, data: Data()) }
        let client = makeTestAPIClient()
        do {
            _ = try await client.generateQuiz(sessionId: testSessionId)
            Issue.record("Expected APIError.rateLimited")
        } catch APIError.rateLimited {
            // expected
        } catch {
            Issue.record("Expected .rateLimited, got \(error)")
        }
    }

    @Test("generateQuiz: malformed JSON body → APIError.decoding")
    func quizBadJSON() async {
        StubURLProtocol.handler = { _ in
            .response(status: 200, data: Data(#"{"title":"Test","questions":"not-an-array"}"#.utf8))
        }
        let client = makeTestAPIClient()
        do {
            _ = try await client.generateQuiz(sessionId: testSessionId)
            Issue.record("Expected decoding error")
        } catch APIError.decoding {
            // expected
        } catch {
            Issue.record("Expected .decoding, got \(error)")
        }
    }

    @Test("generateReportCard: happy path decodes the report card")
    func reportCardHappyPath() async throws {
        let json = #"""
        {
          "overallGrade": "B+",
          "summary": "Great progress on critical thinking.",
          "strengths": ["asking good follow-ups", "citing sources"],
          "areasToRevisit": ["alignment basics"],
          "conceptsCovered": ["LLMs", "bias", "alignment"],
          "criticalThinkingScore": 78,
          "curiosityScore": 85,
          "misconceptionsAddressed": ["AI understands like humans"],
          "nextSessionSuggestion": "Try debate mode"
        }
        """#
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/report-card")
            return .response(status: 200, data: Data(json.utf8))
        }
        let client = makeTestAPIClient()
        let report = try await client.generateReportCard(sessionId: testSessionId)
        #expect(report.overallGrade == "B+")
        #expect(report.criticalThinkingScore == 78)
        #expect(report.strengths.count == 2)
    }

    @Test("Transport-level timeout surfaces as APIError.timeout")
    func transportTimeout() async {
        StubURLProtocol.handler = { _ in .urlError(.timedOut) }
        let client = makeTestAPIClient()
        do {
            _ = try await client.generateQuiz(sessionId: testSessionId)
            Issue.record("Expected timeout")
        } catch APIError.timeout {
            // expected
        } catch {
            Issue.record("Expected .timeout, got \(error)")
        }
    }

    @Test("Offline surfaces as APIError.offline")
    func offline() async {
        StubURLProtocol.handler = { _ in .urlError(.notConnectedToInternet) }
        let client = makeTestAPIClient()
        do {
            _ = try await client.generateQuiz(sessionId: testSessionId)
            Issue.record("Expected offline")
        } catch APIError.offline {
            // expected
        } catch {
            Issue.record("Expected .offline, got \(error)")
        }
    }

    // MARK: - Image upload (APIClient+Images)
    //
    // Live in this suite (not a separate one) on purpose: they share the static
    // `StubURLProtocol.handler`, and two `.serialized` suites would still run in
    // parallel and stomp each other's handler — the trap documented above.

    @Test("uploadImage: 201 decodes the full stored-image descriptor")
    func uploadHappyPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/images")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            return .response(status: 201, headers: ["Content-Type": "application/json"], data: Data(uploadResponseJSON.utf8))
        }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD", fileName: "photo.jpg")
        let response = try await client.uploadImage(input, sessionId: testSessionId)

        #expect(response.id == "abc123_TOKEN-xyz")
        #expect(response.url == "/api/images/abc123_TOKEN-xyz")
        #expect(response.contentType == "image/jpeg")
        #expect(response.fileName == "photo.jpg")
        #expect(response.size == 12345)
        #expect(response.createdAt == "2026-05-30T12:00:00.000Z")
    }

    @Test("uploadImage: request body carries sessionId + contentType + data + fileName")
    func uploadBodyShape() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.bodyData()
            return .response(status: 201, data: Data(uploadResponseJSON.utf8))
        }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/png", base64Data: "QUJD", fileName: "p.png")
        _ = try await client.uploadImage(input, sessionId: "sess-99")

        struct Body: Decodable {
            let sessionId: String
            let contentType: String
            let data: String
            let fileName: String?
        }
        let decoded = try JSONDecoder().decode(Body.self, from: #require(capturedBody))
        #expect(decoded.sessionId == "sess-99")
        #expect(decoded.contentType == "image/png")
        #expect(decoded.data == "QUJD")
        #expect(decoded.fileName == "p.png")
    }

    @Test("uploadImage: nil fileName is omitted from the JSON body (not null)")
    func uploadOmitsNilFileName() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.bodyData()
            return .response(status: 201, data: Data(uploadResponseJSON.utf8))
        }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD", fileName: nil)
        _ = try await client.uploadImage(input, sessionId: "sess-1")

        // The backend's Zod `.optional()` accepts undefined but rejects null,
        // so the key must be ABSENT.
        let json = try JSONSerialization.jsonObject(with: #require(capturedBody)) as? [String: Any]
        #expect(json?["fileName"] == nil)
        #expect(json?.keys.contains("fileName") == false)
    }

    @Test("uploadImage: 400 surfaces as APIError.invalidRequest")
    func uploadRejectedPayload() async {
        StubURLProtocol.handler = { _ in
            .response(status: 400, data: Data(#"{"error":"image_invalid_type","message":"Unsupported image type."}"#.utf8))
        }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD")
        do {
            _ = try await client.uploadImage(input, sessionId: testSessionId)
            Issue.record("Expected APIError.invalidRequest")
        } catch APIError.invalidRequest {
            // expected
        } catch {
            Issue.record("Expected .invalidRequest, got \(error)")
        }
    }

    @Test("uploadImage: 500 storage failure surfaces as APIError.server")
    func uploadStorageFailure() async {
        StubURLProtocol.handler = { _ in .response(status: 500, data: Data(#"{"error":"storage_error"}"#.utf8)) }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD")
        do {
            _ = try await client.uploadImage(input, sessionId: testSessionId)
            Issue.record("Expected APIError.server")
        } catch APIError.server(let status) {
            #expect(status == 500)
        } catch {
            Issue.record("Expected .server, got \(error)")
        }
    }

    @Test("uploadImage: offline surfaces as APIError.offline")
    func uploadOffline() async {
        StubURLProtocol.handler = { _ in .urlError(.notConnectedToInternet) }
        let client = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD")
        do {
            _ = try await client.uploadImage(input, sessionId: testSessionId)
            Issue.record("Expected APIError.offline")
        } catch APIError.offline {
            // expected
        } catch {
            Issue.record("Expected .offline, got \(error)")
        }
    }

    @Test("imageURL(for:) resolves the relative url against the base URL")
    func resolvesImageURL() {
        let client = makeTestAPIClient()
        let response = APIClient.ImageUploadResponse(
            id: "x", url: "/api/images/x", contentType: "image/jpeg",
            fileName: nil, size: 1, createdAt: "2026-05-30T12:00:00.000Z"
        )
        #expect(client.imageURL(for: response)?.absoluteString == "https://stub.mercurius.test/api/images/x")
    }

    @Test("APIClient satisfies ImageUploading and uploads through the protocol")
    func uploadsThroughProtocol() async throws {
        StubURLProtocol.handler = { _ in .response(status: 201, data: Data(uploadResponseJSON.utf8)) }
        let uploader: ImageUploading = makeTestAPIClient()
        let input = APIClient.ImageUploadInput(contentType: "image/jpeg", base64Data: "QUJD")
        let response = try await uploader.uploadImage(input, sessionId: testSessionId)
        #expect(response.id == "abc123_TOKEN-xyz")
    }

    // MARK: - Streaming helpers

    /// Collect every event from the stream until it finishes, or throw.
    private func drain(
        _ stream: AsyncThrowingStream<ChatStreamEvent, Error>
    ) async throws -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    @Test("Stream: delta, delta, complete — all events delivered in order")
    func streamingHappyPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/api/chat")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")

            return .stream { stub in
                stub.yield(#"data: {"type":"delta","text":"Hi"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(5))
                stub.yield(#"data: {"type":"delta","text":" there!"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(5))
                stub.yield(
                    #"""
                    data: {"type":"complete","reply":"Hi there!","sessionId":"sid","mode":"socratic","unlocked":false,"streak":1,"difficulty":1}


                    """#
                )
                stub.finish()
            }
        }

        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [ChatMessageDTO(role: "user", content: "hello")],
            sessionId: "sid"
        )
        let events = try await drain(stream)

        #expect(events.count == 3)
        guard case let .delta(text: t1) = events[0] else {
            Issue.record("Expected .delta, got \(events[0])"); return
        }
        #expect(t1 == "Hi")
        guard case let .delta(text: t2) = events[1] else {
            Issue.record("Expected .delta, got \(events[1])"); return
        }
        #expect(t2 == " there!")
        guard case let .complete(response) = events[2] else {
            Issue.record("Expected .complete, got \(events[2])"); return
        }
        #expect(response.reply == "Hi there!")
        #expect(response.mode == "socratic")
    }

    @Test("Stream: 401 before bytes → stream throws APIError.unauthorized")
    func streamingUnauthorized() async {
        StubURLProtocol.handler = { _ in
            .response(status: 401, data: Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [ChatMessageDTO(role: "user", content: "hi")],
            sessionId: "sid"
        )
        do {
            for try await _ in stream {
                Issue.record("Stream should error before yielding any events")
            }
            Issue.record("Expected throw on iteration")
        } catch APIError.unauthorized {
            // expected
        } catch {
            Issue.record("Expected .unauthorized, got \(error)")
        }
    }

    @Test("Stream: 429 → stream throws APIError.rateLimited")
    func streamingRateLimited() async {
        StubURLProtocol.handler = { _ in .response(status: 429, data: Data()) }
        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [ChatMessageDTO(role: "user", content: "hi")],
            sessionId: "sid"
        )
        do {
            for try await _ in stream {}
            Issue.record("Expected .rateLimited")
        } catch APIError.rateLimited {
            // expected
        } catch {
            Issue.record("Expected .rateLimited, got \(error)")
        }
    }

    @Test("Stream: mid-stream error event surfaces as .streamError")
    func streamingServerErrorEvent() async throws {
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"delta","text":"part"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(5))
                stub.yield(#"data: {"type":"error","error":"upstream_timeout"}"# + "\n\n")
                stub.finish()
            }
        }
        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [ChatMessageDTO(role: "user", content: "hi")],
            sessionId: "sid"
        )
        let events = try await drain(stream)
        #expect(events.count == 2)
        guard case let .streamError(message) = events[1] else {
            Issue.record("Expected .streamError, got \(events[1])"); return
        }
        #expect(message == "upstream_timeout")
    }

    @Test("Stream: SSE chunks split mid-line are reassembled correctly")
    func streamingSplitLines() async throws {
        // Network layers can deliver bytes in arbitrary chunks, including
        // mid-JSON. The SSEDataDelegate buffers until it sees a newline.
        // This test verifies that works end-to-end.
        StubURLProtocol.handler = { _ in
            .stream { stub in
                stub.yield(#"data: {"type":"delta","te"#)
                try? await Task.sleep(for: .milliseconds(3))
                stub.yield(#"xt":"split"}"# + "\n\n")
                try? await Task.sleep(for: .milliseconds(3))
                stub.yield(
                    #"""
                    data: {"type":"complete","reply":"split","sessionId":"sid","mode":"socratic","unlocked":false}


                    """#
                )
                stub.finish()
            }
        }
        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [ChatMessageDTO(role: "user", content: "hi")],
            sessionId: "sid"
        )
        let events = try await drain(stream)
        #expect(events.count == 2)
        guard case let .delta(text) = events[0] else {
            Issue.record("Expected .delta"); return
        }
        #expect(text == "split")
    }

    @Test("Stream: POST body carries messages + sessionId as JSON")
    func streamingPostBodyShape() async throws {
        var capturedBody: Data?
        StubURLProtocol.handler = { request in
            capturedBody = request.bodyData()
            return .stream { stub in
                stub.yield(
                    #"""
                    data: {"type":"complete","reply":"ok","sessionId":"sid","mode":"socratic","unlocked":false}


                    """#
                )
                stub.finish()
            }
        }
        let client = makeTestAPIClient()
        let stream = client.streamChat(
            messages: [
                ChatMessageDTO(role: "user", content: "first"),
                ChatMessageDTO(role: "assistant", content: "reply"),
                ChatMessageDTO(role: "user", content: "second"),
            ],
            sessionId: "sess-42"
        )
        _ = try await drain(stream)

        // Decode the captured body and verify its shape.
        struct Body: Decodable {
            let messages: [ChatMessageDTO]
            let sessionId: String
        }
        guard let data = capturedBody else {
            Issue.record("No body captured"); return
        }
        let decoded = try JSONDecoder().decode(Body.self, from: data)
        #expect(decoded.sessionId == "sess-42")
        #expect(decoded.messages.count == 3)
        #expect(decoded.messages[0].role == "user")
        #expect(decoded.messages[0].content == "first")
        #expect(decoded.messages[2].content == "second")
    }
}
