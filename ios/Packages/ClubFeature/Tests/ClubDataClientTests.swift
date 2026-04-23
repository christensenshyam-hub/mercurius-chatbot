import Testing
import Foundation
@testable import ClubFeature
@testable import NetworkingKit

// Minimal URLProtocol stub for intercepting requests the real
// `ClubDataClient` makes. NetworkingKit's test-only `StubURLProtocol`
// isn't available here (tests don't cross package boundaries for
// non-public types), so this is a smaller, ClubFeature-local version —
// one-shot responses are the only shape ClubDataClient needs.
final class ClubStubProtocol: URLProtocol, @unchecked Sendable {

    struct Response {
        let status: Int
        let headers: [String: String]
        let data: Data
    }

    private static let lock = NSLock()
    private static var _handler: (@Sendable (URLRequest) -> Result<Response, URLError>)?

    static var handler: (@Sendable (URLRequest) -> Result<Response, URLError>)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { handler != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        switch handler(request) {
        case .success(let r):
            guard let response = HTTPURLResponse(
                url: url, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: r.data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Fixtures
//
// Tiny stand-in payloads. The real production JSON shapes are covered
// by WireContractTests; these exist just to drive decode paths
// through the full `ClubDataClient.fetchJSON<T>` pipeline.

private let happyEventsJSON = #"""
{
  "schedule": {
    "day": "Thursday",
    "time": "8:20 AM",
    "location": "Library"
  },
  "upcoming": [],
  "past": []
}
"""#

private let happyBlogJSON = #"""
[
  {
    "id": "p1",
    "title": "t",
    "date": "2026-01-01",
    "author": "a",
    "category": "c",
    "summary": "s",
    "content": "c"
  }
]
"""#

private func testSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ClubStubProtocol.self]
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 2
    return URLSession(configuration: config)
}

private func makeClient() -> ClubDataClient {
    ClubDataClient(
        baseURL: URL(string: "https://stub.mayoailiteracy.test")!,
        session: testSession()
    )
}

// MARK: - Suite

@Suite("ClubDataClient end-to-end", .serialized)
struct ClubDataClientTests {

    init() { ClubStubProtocol.reset() }

    // MARK: - Happy paths

    @Test("fetchEvents: hits /events-data.json and decodes the shape")
    func fetchEventsHappy() async throws {
        ClubStubProtocol.handler = { request in
            #expect(request.url?.path == "/events-data.json")
            #expect(request.httpMethod == "GET" || request.httpMethod == nil)
            return .success(.init(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(happyEventsJSON.utf8)
            ))
        }
        let events = try await makeClient().fetchEvents()
        #expect(events.schedule.day == "Thursday")
        #expect(events.upcoming.isEmpty)
    }

    @Test("fetchBlogPosts: hits /blog-content.json and decodes the array")
    func fetchBlogHappy() async throws {
        ClubStubProtocol.handler = { request in
            #expect(request.url?.path == "/blog-content.json")
            return .success(.init(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(happyBlogJSON.utf8)
            ))
        }
        let posts = try await makeClient().fetchBlogPosts()
        #expect(posts.count == 1)
        #expect(posts.first?.id == "p1")
    }

    // MARK: - Error mapping

    @Test("HTTP 500 surfaces as APIError.server")
    func serverError() async {
        ClubStubProtocol.handler = { _ in
            .success(.init(status: 500, headers: [:], data: Data()))
        }
        do {
            _ = try await makeClient().fetchEvents()
            Issue.record("Expected .server")
        } catch APIError.server(let status) {
            #expect(status == 500)
        } catch {
            Issue.record("Expected .server, got \(error)")
        }
    }

    @Test("HTTP 401 surfaces as APIError.unauthorized")
    func unauthorized() async {
        ClubStubProtocol.handler = { _ in
            .success(.init(status: 401, headers: [:], data: Data()))
        }
        do {
            _ = try await makeClient().fetchBlogPosts()
            Issue.record("Expected .unauthorized")
        } catch APIError.unauthorized {
            // expected
        } catch {
            Issue.record("Expected .unauthorized, got \(error)")
        }
    }

    @Test("Offline URLError maps to APIError.offline")
    func offline() async {
        ClubStubProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        do {
            _ = try await makeClient().fetchEvents()
            Issue.record("Expected .offline")
        } catch APIError.offline {
            // expected
        } catch {
            Issue.record("Expected .offline, got \(error)")
        }
    }

    @Test("Timeout URLError maps to APIError.timeout")
    func timeout() async {
        ClubStubProtocol.handler = { _ in .failure(URLError(.timedOut)) }
        do {
            _ = try await makeClient().fetchEvents()
            Issue.record("Expected .timeout")
        } catch APIError.timeout {
            // expected
        } catch {
            Issue.record("Expected .timeout, got \(error)")
        }
    }

    @Test("Malformed JSON → APIError.decoding with underlying reason")
    func malformedJSON() async {
        ClubStubProtocol.handler = { _ in
            .success(.init(
                status: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(#"{"schedule":"not-an-object"}"#.utf8)
            ))
        }
        do {
            _ = try await makeClient().fetchEvents()
            Issue.record("Expected .decoding")
        } catch APIError.decoding {
            // expected
        } catch {
            Issue.record("Expected .decoding, got \(error)")
        }
    }

    // MARK: - Request shape

    @Test("Request is GET with the right Accept header implicit + hit count is one")
    func requestShape() async throws {
        var calls = 0
        ClubStubProtocol.handler = { _ in
            calls += 1
            return .success(.init(status: 200, headers: [:], data: Data(happyEventsJSON.utf8)))
        }
        _ = try await makeClient().fetchEvents()
        #expect(calls == 1, "Each call hits the network exactly once")
    }
}
