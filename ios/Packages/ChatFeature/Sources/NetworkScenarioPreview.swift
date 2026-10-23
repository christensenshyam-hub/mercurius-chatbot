#if DEBUG
import Foundation
import NetworkingKit

/// DEBUG `-LessonReplay -LessonReplayNetwork <scenario>`: the lesson's
/// requests go through the real `APIClient` (status and Content-Type checks,
/// SSE parsing, refusal copy, Retry rule), but a local `URLProtocol` answers
/// them with what production or a school network sends, so each failure can
/// be screenshotted with no network call. The refusal frames are the
/// server's exact ones (`sendRefusal` in server.js, copy from
/// lib/quotas.js), with today's wait to UTC midnight as `retryAfterSec`.
enum NetworkScenario: String, CaseIterable {
    /// A school filter's 200 text/html block page in place of the stream.
    case blockPage = "block-page"
    /// The student's daily lesson turns are used up.
    case dailyLimit = "daily-limit"
    /// The network's new-session cap (no `scope` in the frame, as today).
    case newSessions = "new-sessions"
    /// The kill switch.
    case paused
    /// The dollar budget.
    case spendCap = "spend-cap"
    /// The in-flight cap: a moment, so Retry stays.
    case busy

    static var requested: NetworkScenario? {
        UserDefaults.standard.string(forKey: "LessonReplayNetwork").flatMap(Self.init(rawValue:))
    }

    /// A real `APIClient` whose every request this scenario answers.
    func makeClient() -> APIClient {
        NetworkScenarioProtocol.scenario = self
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkScenarioProtocol.self]
        return APIClient(environment: .production, sessionConfiguration: config)
    }

    /// Status, headers and body, as the wire carries them.
    var response: (status: Int, contentType: String, body: String) {
        switch self {
        case .blockPage:
            return (200, "text/html", Self.blockPageHTML)
        case .dailyLimit:
            return Self.refusalFrame(code: "daily_limit",
                                     message: "You've used today's lesson turns. Mercurius will be ready again tomorrow.",
                                     retryAfterSec: Self.secondsUntilUTCMidnight())
        case .newSessions:
            return Self.refusalFrame(code: "daily_limit",
                                     message: "Too many new sessions from this network today.",
                                     retryAfterSec: Self.secondsUntilUTCMidnight())
        case .paused:
            return Self.refusalFrame(code: "service_disabled",
                                     message: "Mercurius is temporarily paused — please try again soon.",
                                     retryAfterSec: nil)
        case .spendCap:
            return Self.refusalFrame(code: "spend_cap",
                                     message: "Daily usage limit reached — please try again tomorrow.",
                                     retryAfterSec: nil)
        case .busy:
            return Self.refusalFrame(code: "busy",
                                     message: "Mercurius is helping a lot of students right now. Try again in a minute.",
                                     retryAfterSec: 60)
        }
    }

    private static func refusalFrame(code: String, message: String, retryAfterSec: Int?) -> (Int, String, String) {
        var frame: [String: Any] = ["type": "error", "code": code, "error": message]
        if let retryAfterSec { frame["retryAfterSec"] = retryAfterSec }
        let json = (try? JSONSerialization.data(withJSONObject: frame)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return (200, "text/event-stream", "data: \(json)\n\ndata: [DONE]\n\n")
    }

    /// lib/quotas.js `secondsUntilUtcMidnight`.
    private static func secondsUntilUTCMidnight(now: Date = Date()) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let next = utc.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        return max(1, Int(next.timeIntervalSince(now).rounded(.up)))
    }

    /// The classroom-reliability lens's filter stand-in page.
    private static let blockPageHTML = """
        <html><head><title>Web Page Blocked</title></head><body><h1>This site is blocked by your school</h1>\
        <p>Category: Uncategorized / Web hosting</p></body></html>
        """
}

/// Answers every request with `scenario`'s response.
final class NetworkScenarioProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var scenario: NetworkScenario = .blockPage
    /// About a reply's time to first byte, so the thinking state shows.
    nonisolated(unsafe) static var delay: TimeInterval = 0.8

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, contentType, body) = Self.scenario.response
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // The stream delegate cancels a 2xx that isn't an event stream.
            guard !isStopped else { return }
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private let lock = NSLock()
    private var stopped = false
    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
#endif
