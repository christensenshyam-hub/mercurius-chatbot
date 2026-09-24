import Testing
@testable import ChatFeature
@testable import NetworkingKit

/// The one report alert: its copy comes from the real `ReportOutcome`, and a
/// failure shows the reason `submitReport` built rather than a fixed line.
@Suite("ReportFeedback")
struct ReportFeedbackTests {

    @Test("A sent report confirms the review")
    func sent() {
        let feedback = ReportFeedback(.sent)
        #expect(feedback.title == "Reported")
        #expect(feedback.message == "Thanks — we'll review this response.")
    }

    @Test("A failed report shows the reason it failed", arguments: [
        APIError.offline.userFacingMessage,
        APIError.timeout.userFacingMessage,
        APIError.rateLimited.userFacingMessage,
        APIError.server(status: 500).userFacingMessage,
        "Only Merc's replies can be reported.",
    ])
    func failed(_ reason: String) {
        let feedback = ReportFeedback(.failed(reason))
        #expect(feedback.title == "Couldn't send report")
        #expect(feedback.message == reason)
    }

    @Test("A non-connection failure is never blamed on the connection")
    func rateLimitIsNotAConnectionProblem() {
        let feedback = ReportFeedback(.failed(APIError.rateLimited.userFacingMessage))
        #expect(!feedback.message.lowercased().contains("connection"))
    }

    @Test("Two identical outcomes in a row are still two distinct alerts")
    func repeatedOutcomeIsDistinct() {
        #expect(ReportFeedback(.sent) != ReportFeedback(.sent))
    }
}
