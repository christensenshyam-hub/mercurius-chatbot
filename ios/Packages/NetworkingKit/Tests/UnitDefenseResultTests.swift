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
}
