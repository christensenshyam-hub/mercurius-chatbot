import Testing
@testable import ChatFeature

/// `ChatViewModel.sanitize(streamErrorMessage:)` is the last line of
/// defense between an upstream error body and the user. These tests
/// pin the three branches so a regression that lets raw JSON or
/// billing strings leak to the UI fails CI loudly.
@Suite("ChatViewModel.sanitize(streamErrorMessage:)")
@MainActor
struct ChatViewModelErrorSanitizeTests {

    // MARK: - Branch 1: known billing / quota signatures

    @Test("Anthropic 'credit balance' is replaced with a service-down message")
    func creditBalanceMessage() {
        let raw = #"400 {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011CaPW6Zy-FYzpbnCrs3aLPJ"}"#
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out.contains("Mercurius can't reach the AI"))
        #expect(!out.contains("credit balance"))
        #expect(!out.contains("Anthropic"))
        #expect(!out.contains("{"))
    }

    @Test("`invalid_request_error` alone (without 'credit balance') still triggers the service-down branch")
    func invalidRequestError() {
        let raw = #"{"type":"error","error":{"type":"invalid_request_error","message":"upstream bad"}}"#
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out.contains("Mercurius can't reach the AI"))
    }

    @Test("Stripe-style 'billing' references are caught too")
    func billingKeyword() {
        let raw = "402 — billing required"
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out.contains("Mercurius can't reach the AI"))
    }

    // MARK: - Branch 2: anything that looks like raw JSON

    @Test("Bare JSON object body is replaced with a generic message")
    func bareJSONObject() {
        let raw = #"{"foo":"bar"}"#
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out == "Mercurius can't reach the AI right now. Please try again.")
    }

    @Test("Status-code-prefixed JSON is replaced with a generic message")
    func statusPrefixedJSON() {
        let raw = #"500 {"err":"boom"}"#
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out == "Mercurius can't reach the AI right now. Please try again.")
    }

    @Test("JSON array bodies are also blocked from leaking")
    func bareJSONArray() {
        let raw = #"[{"err":"x"}]"#
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out == "Mercurius can't reach the AI right now. Please try again.")
    }

    // MARK: - Branch 3: trust user-readable text

    @Test("Plain `rate limit` text passes through unchanged")
    func rateLimitPassesThrough() {
        let raw = "rate limit exceeded"
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out == "rate limit exceeded")
    }

    @Test("`upstream_timeout` passes through (server-supplied human string)")
    func upstreamTimeoutPassesThrough() {
        let raw = "upstream_timeout"
        let out = ChatViewModel.sanitize(streamErrorMessage: raw)
        #expect(out == "upstream_timeout")
    }

    @Test("Empty / whitespace-only message becomes a generic fallback")
    func emptyBecomesFallback() {
        #expect(ChatViewModel.sanitize(streamErrorMessage: "") == "Something went wrong. Try again.")
        #expect(ChatViewModel.sanitize(streamErrorMessage: "   \n  ") == "Something went wrong. Try again.")
    }
}
