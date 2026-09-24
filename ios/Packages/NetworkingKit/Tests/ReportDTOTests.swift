import Testing
import Foundation
@testable import NetworkingKit

@Suite("ReportReason + ReportContext")
struct ReportDTOTests {

    @Test("Raw values match the server's reason enum")
    func rawValues() {
        #expect(ReportReason.wrong.rawValue == "wrong")
        #expect(ReportReason.harmful.rawValue == "harmful")
        #expect(ReportReason.offTopic.rawValue == "off_topic")
        #expect(ReportReason.other.rawValue == "other")
        #expect(ReportReason.allCases.count == 4)
    }

    @Test("Every reason has a distinct, non-empty picker title")
    func titles() {
        let titles = ReportReason.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
        #expect(ReportReason.wrong.title == "Wrong or misleading")
        #expect(ReportReason.harmful.title == "Harmful or inappropriate")
        #expect(ReportReason.offTopic.title == "Off topic")
        #expect(ReportReason.other.title == "Something else")
    }

    @Test("ReportContext omits nil fields and never emits extra keys")
    func contextEncoding() throws {
        let minimal = try JSONEncoder().encode(ReportContext(surface: "chat"))
        let minimalJSON = try #require(try JSONSerialization.jsonObject(with: minimal) as? [String: Any])
        #expect(Set(minimalJSON.keys) == ["surface"])

        let full = try JSONEncoder().encode(
            ReportContext(surface: "lesson", mode: "curriculum", lessonId: "u1-l1", appVersion: "2.3.0")
        )
        let fullJSON = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        #expect(Set(fullJSON.keys) == ["surface", "mode", "lessonId", "appVersion"])
    }

    @Test("ReportContext round-trips and is Equatable")
    func contextRoundTrip() throws {
        let original = ReportContext(surface: "lesson", mode: "curriculum", lessonId: "u1-l1", appVersion: "2.3.0")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReportContext.self, from: data)
        #expect(decoded == original)
        #expect(ReportContext(surface: "chat") != original)
    }

    @Test("ServerRefusalCode recognises exactly the five wire codes")
    func refusalCodes() {
        for code in ["daily_limit", "spend_cap", "service_disabled", "busy", "restarting"] {
            #expect(ServerRefusalCode.isRefusal(code), "\(code) should be a refusal")
        }
        for code in ["rate_limited", "upstream_error", "timeout", "server_error", "", "DAILY_LIMIT"] {
            #expect(!ServerRefusalCode.isRefusal(code), "\(code) should not be a refusal")
        }
        #expect(!ServerRefusalCode.isRefusal(nil))
    }
}
