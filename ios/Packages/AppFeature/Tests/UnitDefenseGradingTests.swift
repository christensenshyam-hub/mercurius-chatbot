import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature
import NetworkingKit

/// The unit-test grade's wire → curriculum mapping (AUD-02): a crisis answer,
/// on a 200 or a non-2xx, must reach the view model as support, never as a
/// grade or an error caption.
@Suite("Unit-test defense grading")
@MainActor
struct UnitDefenseGradingTests {

    /// `/api/unit-test/grade`'s crisis answer, byte for byte: server.js
    /// CRISIS_GRADE with lib/safetyCore.js CRISIS_COPY.
    private static let serverCrisisPayload = #"{"grade":"—","pass":false,"feedback":"I'm really glad you told me. I'm an AI, so I can't be your support person, but you deserve real support right now.\n\nCall or text 988 — the Suicide & Crisis Lifeline (US, 24/7).\nText HOME to 741741 — Crisis Text Line.\n\nIf you might be in immediate danger, call 911. Please tell a trusted adult too, like a parent or school counselor. Everything else can wait — come back to it whenever you're ready.","crisis":true}"#

    private func decode(_ json: String) throws -> UnitDefenseResult {
        try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
    }

    @Test("The server's 200 crisis answer becomes the support result, with no grade")
    func crisis200() async throws {
        let result = try await UnitDefenseGrading.grade { try decode(Self.serverCrisisPayload) }
        #expect(result == .crisisSupport)
        #expect(result.isCrisis)
        #expect(!result.pass)
        #expect(result.grade.isEmpty)
    }

    @Test("A non-2xx crisis body becomes DefenseGradingError.crisis, not a refusal caption")
    func crisisNon2xx() async {
        let body = Data(#"{"error":"crisis","message":"Call or text 988.","crisis":true}"#.utf8)
        await #expect(throws: DefenseGradingError.crisis) {
            try await UnitDefenseGrading.grade {
                try APIClient.validate(statusCode: 503, data: body)
                return try decode(Self.serverCrisisPayload)
            }
        }
    }

    @Test("A normal grade maps through, with pass derived from the letter")
    func normalGrade() async throws {
        let b = try await UnitDefenseGrading.grade { try decode(#"{"grade":"b","pass":false,"feedback":"Good."}"#) }
        #expect(b == .init(grade: "b", pass: true, feedback: "Good."))
        #expect(!b.isCrisis)

        let c = try await UnitDefenseGrading.grade { try decode(#"{"grade":"C","pass":true,"feedback":"Shallow."}"#) }
        #expect(!c.pass, "a malformed server pass can't mark a C as passed")
    }

    @Test("404, refusals and other errors keep their existing mapping")
    func otherErrors() {
        #expect(UnitDefenseGrading.gradingError(for: .unknown(underlying: "HTTP 404")) == .unavailable)
        #expect(UnitDefenseGrading.gradingError(for: .serviceUnavailable(code: "busy", message: "Busy.", retryAfter: 60))
                == .refused(message: "Busy.", isRetryable: true))
        #expect(UnitDefenseGrading.gradingError(for: .quotaExceeded(message: "Tomorrow.", retryAfter: nil))
                == .refused(message: "Tomorrow.", isRetryable: false))
        #expect(UnitDefenseGrading.gradingError(for: .crisisSupport(message: "988")) == .crisis)
    }

    @Test("A paused or capped server refuses without Retry; the network's allowance keeps it (AUD-30)")
    func refusalRetryRules() {
        #expect(UnitDefenseGrading.gradingError(for: .serviceUnavailable(code: "service_disabled", message: "Paused.", retryAfter: nil))
                == .refused(message: "Paused.", isRetryable: false))
        #expect(UnitDefenseGrading.gradingError(for: .serviceUnavailable(code: "spend_cap", message: "Capped.", retryAfter: nil))
                == .refused(message: "Capped.", isRetryable: false))
        guard case .refused(let message, let retryable) = UnitDefenseGrading.gradingError(
            for: .quotaExceeded(message: "Too many new sessions from this network today.", retryAfter: nil, scope: "ip")
        ) else {
            Issue.record("Expected .refused")
            return
        }
        #expect(retryable)
        #expect(message.contains("cellular"))
    }

    @Test("A school filter's page names the network and leaves the answer free to resend (AUD-32)")
    func blockedNetworkDoesNotLockTheAnswer() async throws {
        #expect(UnitDefenseGrading.gradingError(for: .unreachableOnThisNetwork)
                == .refused(message: APIError.unreachableOnThisNetwork.userFacingMessage, isRetryable: true))

        let unit = try #require(MercuriusCurriculum.units.first)
        let test = try #require(MercuriusCurriculum.unitTest(for: unit.id))
        let model = UnitTestViewModel(unit: unit, test: test) { _ in
            try await UnitDefenseGrading.grade { throw APIError.unreachableOnThisNetwork }
        }
        for question in model.questions { model.select(question.answer, for: question.id) }
        model.submitQuiz()
        model.continueAfterQuiz()
        model.defenseAnswer = "An answer."
        await model.submitDefense()
        #expect(model.defenseError?.contains("network may be blocking Mercurius") == true)
        // Before AUD-32 a block page decoded as `.decoding`, not retryable,
        // and this same answer could not be sent again.
        #expect(model.canSubmitDefense)
    }

    @Test("End to end: the server's crisis payload takes the unit test to support, never a result")
    func viewModelReachesSupport() async throws {
        let unit = try #require(MercuriusCurriculum.units.first)
        let test = try #require(MercuriusCurriculum.unitTest(for: unit.id))
        let model = UnitTestViewModel(unit: unit, test: test) { _ in
            try await UnitDefenseGrading.grade { try decode(Self.serverCrisisPayload) }
        }
        for question in model.questions { model.select(question.answer, for: question.id) }
        model.submitQuiz()
        model.continueAfterQuiz()
        #expect(model.phase == .defense)
        model.defenseAnswer = "An answer."
        await model.submitDefense()
        #expect(model.phase == .support)
        #expect(model.defenseResult == nil)
        #expect(!model.overallPassed)
        #expect(!model.offersRetake)
    }
}
