import Testing
import Foundation
@testable import NetworkingKit

@Suite("UnitDefenseResult decoding")
struct UnitDefenseResultTests {

    @Test("Decodes grade, pass, and feedback from the server's JSON")
    func decodesPass() throws {
        let json = #"{"grade":"A","pass":true,"feedback":"Strong reasoning."}"#
        let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
        #expect(result.grade == "A")
        #expect(result.pass == true)
        #expect(result.feedback == "Strong reasoning.")
    }

    @Test("A failing grade decodes with pass=false")
    func decodesFail() throws {
        let json = #"{"grade":"C","pass":false,"feedback":"Too shallow — name a specific tradeoff."}"#
        let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
        #expect(result.grade == "C")
        #expect(result.pass == false)
        #expect(result.feedback.contains("tradeoff"))
    }

    // MARK: - Crisis signal (AUD-02)

    /// `/api/unit-test/grade`'s crisis answer, byte for byte: server.js
    /// CRISIS_GRADE with lib/safetyCore.js CRISIS_COPY.
    static let serverCrisisPayload = #"{"grade":"—","pass":false,"feedback":"I'm really glad you told me. I'm an AI, so I can't be your support person, but you deserve real support right now.\n\nCall or text 988 — the Suicide & Crisis Lifeline (US, 24/7).\nText HOME to 741741 — Crisis Text Line.\n\nIf you might be in immediate danger, call 911. Please tell a trusted adult too, like a parent or school counselor. Everything else can wait — come back to it whenever you're ready.","crisis":true}"#

    @Test("The server's crisis answer decodes with crisis set, no pass, and the resources")
    func decodesServerCrisis() throws {
        let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(Self.serverCrisisPayload.utf8))
        #expect(result.crisis)
        #expect(!result.pass)
        #expect(result.grade == "—")
        #expect(result.feedback.contains("Call or text 988"))
        #expect(result.feedback.contains("Text HOME to 741741"))
    }

    @Test("An old-server payload with no crisis field decodes as a normal grade")
    func oldPayloadHasNoCrisis() throws {
        let json = #"{"grade":"B","pass":true,"feedback":"Good tradeoff named."}"#
        let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
        #expect(!result.crisis)
        #expect(result == UnitDefenseResult(grade: "B", pass: true, feedback: "Good tradeoff named."))
    }

    @Test("crisis: false (or null) is a normal grade")
    func explicitFalseIsNormal() throws {
        for flag in ["false", "null", #""false""#, "0"] {
            let json = #"{"grade":"C","pass":false,"feedback":"Shallow.","crisis":\#(flag)}"#
            let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
            #expect(!result.crisis, "crisis: \(flag)")
            #expect(result.grade == "C")
        }
    }

    @Test("A quoted \"true\" still counts as the crisis signal")
    func quotedTrueIsCrisis() throws {
        let json = #"{"grade":"—","pass":false,"feedback":"Call or text 988.","crisis":"true"}"#
        let result = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
        #expect(result.crisis)
    }

    @Test("The crisis signal outranks the rest of the body: it never passes, and missing fields don't fail the decode")
    func crisisOutranksBody() throws {
        let graded = #"{"grade":"A","pass":true,"feedback":"x","crisis":true}"#
        let a = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(graded.utf8))
        #expect(a.crisis)
        #expect(!a.pass)

        let bare = #"{"crisis":true,"message":"Call or text 988."}"#
        let b = try JSONDecoder().decode(UnitDefenseResult.self, from: Data(bare.utf8))
        #expect(b.crisis)
        #expect(!b.pass)
        #expect(b.grade == "—")
        #expect(b.feedback == "Call or text 988.")
    }

    @Test("Without the crisis signal the grade fields are still required")
    func normalGradeStaysStrict() {
        let json = #"{"grade":"A","feedback":"no pass field"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UnitDefenseResult.self, from: Data(json.utf8))
        }
    }
}
