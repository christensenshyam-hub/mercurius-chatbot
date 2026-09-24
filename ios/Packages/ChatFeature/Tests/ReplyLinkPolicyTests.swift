import Testing
import Foundation
@testable import ChatFeature

/// `ReplyLinkPolicy` decides which links inside a tutor reply may leave the
/// app. Replies are model output, so only `https` with a real host passes.
@Suite("ReplyLinkPolicy")
struct ReplyLinkPolicyTests {

    private func url(_ s: String) throws -> URL {
        try #require(URL(string: s), "test fixture should parse as a URL: \(s)")
    }

    @Test("https with a host is allowed", arguments: [
        "https://example.com",
        "https://example.com/path?q=1#frag",
        "https://sub.example.org:8443/x",
        "HTTPS://Example.com",   // scheme is case-insensitive
    ])
    func allowsHTTPS(_ s: String) throws {
        #expect(ReplyLinkPolicy.allows(try url(s)))
    }

    @Test("http is rejected (no plaintext hops out of the app)")
    func rejectsHTTP() throws {
        #expect(!ReplyLinkPolicy.allows(try url("http://example.com")))
    }

    @Test("Non-web schemes are rejected", arguments: [
        "mailto:someone@example.com",
        "tel:+15555550100",
        "sms:+15555550100",
        "javascript:alert(1)",
        "mercurius://session",
        "ftp://example.com/file",
        "file:///etc/passwd",
    ])
    func rejectsOtherSchemes(_ s: String) throws {
        #expect(!ReplyLinkPolicy.allows(try url(s)))
    }

    @Test("Scheme-less strings are rejected", arguments: [
        "example.com",
        "example.com/path",
        "/relative/path",
        "www.example.com",
    ])
    func rejectsSchemeless(_ s: String) throws {
        #expect(!ReplyLinkPolicy.allows(try url(s)))
    }

    @Test("https without a host is rejected")
    func rejectsHostlessHTTPS() throws {
        #expect(!ReplyLinkPolicy.allows(try url("https:///path-only")))
        #expect(!ReplyLinkPolicy.allows(try url("https:")))
    }
}
