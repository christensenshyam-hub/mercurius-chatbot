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

    @Test("429 maps to rateLimited")
    func rateLimit() {
        do {
            try APIClient.validate(statusCode: 429, data: Data())
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .rateLimited)
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("5xx maps to server error with status preserved")
    func serverError() {
        do {
            try APIClient.validate(statusCode: 503, data: Data())
            Issue.record("Expected throw")
        } catch let error as APIError {
            #expect(error == .server(status: 503))
        } catch {
            Issue.record("Wrong error type")
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
            .decoding(underlying: "x"), .invalidModelOutput(reason: "y"),
            .cancelled, .unknown(underlying: "z"),
        ]
        for error in errors {
            #expect(!error.userFacingMessage.isEmpty, "empty message for \(error)")
        }
    }

    @Test("Retryable errors match specification")
    func retryable() {
        #expect(APIError.offline.isRetryable)
        #expect(APIError.timeout.isRetryable)
        #expect(APIError.server(status: 500).isRetryable)
        #expect(APIError.rateLimited.isRetryable)

        #expect(!APIError.invalidRequest(reason: nil).isRetryable)
        #expect(!APIError.unauthorized.isRetryable)
        #expect(!APIError.decoding(underlying: "x").isRetryable)
        #expect(!APIError.cancelled.isRetryable)
    }
}
