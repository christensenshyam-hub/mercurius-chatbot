import Testing
import Foundation
@testable import NetworkingKit

@Suite("APIClient status code validation")
struct APIClientValidationTests {

    @Test("2xx passes")
    func successPasses() throws {
        try APIClient.validate(statusCode: 200, data: Data())
        try APIClient.validate(statusCode: 201, data: Data())
        try APIClient.validate(statusCode: 299, data: Data())
    }

    @Test("400 maps to invalidRequest with server reason if present")
    func invalidRequestCarriesReason() {
        let body = #"{"message":"session id invalid"}"#.data(using: .utf8)!
        do {
            try APIClient.validate(statusCode: 400, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .invalidRequest(reason: "session id invalid"))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("401 and 403 both map to unauthorized")
    func authErrors() {
        for code in [401, 403] {
            do {
                try APIClient.validate(statusCode: code, data: Data())
                Issue.record("Expected throw for \(code)")
            } catch let error as APIError {
                #expect(error == .unauthorized)
            } catch {
                Issue.record("Wrong error type")
            }
        }
    }

    @Test("429 without a daily_limit body maps to rateLimited")
    func rateLimit() {
        let bodies = [
            Data(),
            Data(#"{"error":"rate_limited","message":"You're moving fast!","reply":"You're moving fast!"}"#.utf8),
            Data("<html>too many requests</html>".utf8),
        ]
        for body in bodies {
            do {
                try APIClient.validate(statusCode: 429, data: body)
                Issue.record("Expected throw")
            } catch let error as APIError {
                #expect(error == .rateLimited)
            } catch {
                Issue.record("Wrong error type")
            }
        }
    }

    @Test("429 daily_limit maps to quotaExceeded carrying the server's copy and retryAfter")
    func dailyLimit() {
        let copy = "You've used today's chat turns. Mercurius will be ready again tomorrow."
        let body = Data(#"""
        {"error":"daily_limit","scope":"session","message":"\#(copy)","reply":"\#(copy)","retryAfterSec":31337}
        """#.utf8)
        do {
            try APIClient.validate(statusCode: 429, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .quotaExceeded(message: copy, retryAfter: 31337))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("429 daily_limit without retryAfterSec carries nil retryAfter")
    func dailyLimitNoRetryAfter() {
        let body = Data(#"{"error":"daily_limit","scope":"ip","message":"This network has reached today's usage limit."}"#.utf8)
        do {
            try APIClient.validate(statusCode: 429, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .quotaExceeded(message: "This network has reached today's usage limit.", retryAfter: nil))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("429 daily_limit with a quoted retryAfterSec still decodes the body, as a number")
    func dailyLimitStringRetryAfter() {
        let copy = "You've used today's chat turns."
        let body = Data(#"{"error":"daily_limit","scope":"session","message":"\#(copy)","retryAfterSec":"3600"}"#.utf8)
        do {
            try APIClient.validate(statusCode: 429, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .quotaExceeded(message: copy, retryAfter: 3600))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("503 busy with an unparseable retryAfterSec keeps the refusal and its copy, drops the wait")
    func busyUnparseableRetryAfter() {
        let copy = "Mercurius is helping a lot of students right now. Try again in a minute."
        let body = Data(#"{"error":"busy","message":"\#(copy)","retryAfterSec":"a minute"}"#.utf8)
        do {
            try APIClient.validate(statusCode: 503, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .serviceUnavailable(code: "busy", message: copy, retryAfter: nil))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("429 daily_limit with only the legacy `reply` field still surfaces that copy")
    func dailyLimitReplyOnly() {
        let body = Data(#"{"error":"daily_limit","reply":"Too many new sessions from this network today."}"#.utf8)
        do {
            try APIClient.validate(statusCode: 429, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .quotaExceeded(message: "Too many new sessions from this network today.", retryAfter: nil))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("429 daily_limit with no copy at all falls back to calm default text")
    func dailyLimitNoCopy() {
        let body = Data(#"{"error":"daily_limit","scope":"session"}"#.utf8)
        do {
            try APIClient.validate(statusCode: 429, data: body)
            Issue.record("Expected throw")
        } catch APIError.quotaExceeded(let message, let retryAfter) {
            #expect(!message.isEmpty)
            #expect(!message.contains("{"))
            #expect(retryAfter == nil)
        } catch {
            Issue.record("Expected .quotaExceeded, got \(error)")
        }
    }

    @Test("503 with a refusal code maps to serviceUnavailable with code, copy and retryAfter")
    func serviceUnavailableRefusals() {
        let cases: [(code: String, copy: String, retryJSON: String, retry: TimeInterval?)] = [
            ("spend_cap", "Daily usage limit reached — please try again tomorrow.", "", nil),
            ("service_disabled", "Mercurius is temporarily paused — please try again soon.", "", nil),
            ("busy", "Mercurius is helping a lot of students right now. Try again in a minute.", #","retryAfterSec":60"#, 60),
            ("restarting", "Mercurius is restarting — try again in a few seconds.", #","retryAfterSec":5"#, 5),
        ]
        for c in cases {
            let body = Data(#"{"error":"\#(c.code)","message":"\#(c.copy)","reply":"\#(c.copy)"\#(c.retryJSON)}"#.utf8)
            do {
                try APIClient.validate(statusCode: 503, data: body)
                Issue.record("Expected throw for \(c.code)")
            } catch let error as APIError {
                #expect(error == .serviceUnavailable(code: c.code, message: c.copy, retryAfter: c.retry))
            } catch {
                Issue.record("Wrong error type for \(c.code)")
            }
        }
    }

    @Test("503 with an unrecognised code but a human message still maps to serviceUnavailable")
    func serviceUnavailableUnknownCodeWithMessage() {
        let body = Data(#"{"error":"maintenance","message":"Back in ten minutes."}"#.utf8)
        do {
            try APIClient.validate(statusCode: 503, data: body)
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .serviceUnavailable(code: "maintenance", message: "Back in ten minutes.", retryAfter: nil))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("503 without a refusal code or message maps to the generic server error")
    func serverError() {
        let bodies = [
            Data(),
            Data(#"{"error":"boom"}"#.utf8),
            Data("<html>Application failed to respond</html>".utf8),
        ]
        for body in bodies {
            do {
                try APIClient.validate(statusCode: 503, data: body)
                Issue.record("Expected throw")
            } catch let error as APIError {
                #expect(error == .server(status: 503))
            } catch {
                Issue.record("Wrong error type")
            }
        }
    }

    @Test("Other 5xx keep mapping to server error even when the body has a message")
    func nonFiveOhThreeStaysServerError() {
        let body = Data(#"{"error":"server_error","message":"Could not submit the report."}"#.utf8)
        for code in [500, 502, 504] {
            do {
                try APIClient.validate(statusCode: code, data: body)
                Issue.record("Expected throw for \(code)")
            } catch let error as APIError {
                #expect(error == .server(status: code))
            } catch {
                Issue.record("Wrong error type")
            }
        }
    }
}

@Suite("APIClient URL error mapping")
struct APIClientURLErrorTests {

    @Test("No connection maps to offline")
    func noConnection() {
        let err = URLError(.notConnectedToInternet)
        #expect(APIClient.mapURLError(err) == .offline)
    }

    @Test("Cellular data restricted maps to offline")
    func dataNotAllowed() {
        let err = URLError(.dataNotAllowed)
        #expect(APIClient.mapURLError(err) == .offline)
    }

    @Test("The shapes a dead connection actually produces map to offline", arguments: [
        URLError.Code.networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .internationalRoamingOff,
    ])
    func connectionFailuresAreOffline(_ code: URLError.Code) {
        #expect(APIClient.mapURLError(URLError(code)) == .offline)
    }

    @Test("Other URLErrors still fall through to unknown")
    func otherURLErrorsAreUnknown() {
        if case .unknown = APIClient.mapURLError(URLError(.badServerResponse)) {
            // expected
        } else {
            Issue.record("badServerResponse should not be mapped to a connection error")
        }
    }

    @Test("Timed out maps to timeout")
    func timedOut() {
        let err = URLError(.timedOut)
        #expect(APIClient.mapURLError(err) == .timeout)
    }

    @Test("Cancelled maps to cancelled")
    func cancelled() {
        let err = URLError(.cancelled)
        #expect(APIClient.mapURLError(err) == .cancelled)
    }
}

@Suite("APIError user-facing behavior")
struct APIErrorTests {

    @Test("All errors have non-empty user-facing messages")
    func allErrorsHaveMessages() {
        let errors: [APIError] = [
            .offline, .timeout, .invalidRequest(reason: nil), .unauthorized,
            .rateLimited, .server(status: 500),
            .quotaExceeded(message: "q", retryAfter: nil),
            .serviceUnavailable(code: "busy", message: "b", retryAfter: 60),
            .decoding(underlying: "x"), .invalidModelOutput(reason: "y"),
            .cancelled, .unknown(underlying: "z"),
        ]
        for error in errors {
            #expect(!error.userFacingMessage.isEmpty, "empty message for \(error)")
        }
    }

    @Test("quotaExceeded and serviceUnavailable show the server's copy verbatim")
    func refusalsPreferServerCopy() {
        let quota = APIError.quotaExceeded(
            message: "You've used today's chat turns. Mercurius will be ready again tomorrow.",
            retryAfter: 3600
        )
        #expect(quota.userFacingMessage == "You've used today's chat turns. Mercurius will be ready again tomorrow.")

        let paused = APIError.serviceUnavailable(
            code: "service_disabled",
            message: "Mercurius is temporarily paused — please try again soon.",
            retryAfter: nil
        )
        #expect(paused.userFacingMessage == "Mercurius is temporarily paused — please try again soon.")
        // The generic copies must not leak through for refusals.
        #expect(quota.userFacingMessage != APIError.rateLimited.userFacingMessage)
        #expect(paused.userFacingMessage != APIError.server(status: 503).userFacingMessage)
    }

    @Test("Refusal cases are Equatable on every associated value")
    func refusalEquality() {
        #expect(
            APIError.quotaExceeded(message: "a", retryAfter: 1)
                == .quotaExceeded(message: "a", retryAfter: 1)
        )
        #expect(
            APIError.quotaExceeded(message: "a", retryAfter: 1)
                != .quotaExceeded(message: "a", retryAfter: nil)
        )
        #expect(
            APIError.serviceUnavailable(code: "busy", message: "m", retryAfter: 60)
                == .serviceUnavailable(code: "busy", message: "m", retryAfter: 60)
        )
        #expect(
            APIError.serviceUnavailable(code: "busy", message: "m", retryAfter: 60)
                != .serviceUnavailable(code: "restarting", message: "m", retryAfter: 60)
        )
        #expect(APIError.quotaExceeded(message: "m", retryAfter: nil) != .rateLimited)
        #expect(APIError.serviceUnavailable(code: "busy", message: "m", retryAfter: nil) != .server(status: 503))
    }

    @Test("Retryable errors match specification")
    func retryable() {
        #expect(APIError.offline.isRetryable)
        #expect(APIError.timeout.isRetryable)
        #expect(APIError.server(status: 500).isRetryable)
        #expect(APIError.rateLimited.isRetryable)
        #expect(APIError.serviceUnavailable(code: "busy", message: "m", retryAfter: 60).isRetryable)
        #expect(APIError.serviceUnavailable(code: "spend_cap", message: "m", retryAfter: nil).isRetryable)

        #expect(!APIError.invalidRequest(reason: nil).isRetryable)
        #expect(!APIError.unauthorized.isRetryable)
        #expect(!APIError.quotaExceeded(message: "m", retryAfter: 3600).isRetryable)
        #expect(!APIError.quotaExceeded(message: "m", retryAfter: nil).isRetryable)
        #expect(!APIError.decoding(underlying: "x").isRetryable)
        #expect(!APIError.cancelled.isRetryable)
    }
}
