import Testing
import Foundation
@testable import NetworkingKit

@Suite("ProgressionXpEvent decoding")
struct ProgressionDecodingTests {

    @Test("Decodes `at` as a JSON number (SQLite serves BIGINT as a number)")
    func decodesNumericAt() throws {
        let json = #"{"amount":14,"reason":"POSITION_REVISION","sourceType":"chat","at":1751234567890}"#
        let event = try JSONDecoder().decode(ProgressionXpEvent.self, from: Data(json.utf8))
        #expect(event.amount == 14)
        #expect(event.reason == "POSITION_REVISION")
        #expect(event.at == 1_751_234_567_890)
    }

    @Test("Decodes `at` as a JSON string (node-postgres returns int8 columns as strings)")
    func decodesStringAt() throws {
        let json = #"{"amount":10,"reason":"DAILY_RETURN","at":"1751234567890"}"#
        let event = try JSONDecoder().decode(ProgressionXpEvent.self, from: Data(json.utf8))
        #expect(event.at == 1_751_234_567_890)
    }

    @Test("A missing or malformed `at` degrades to nil instead of failing the decode")
    func degradedAt() throws {
        let missing = #"{"amount":5,"reason":"DAILY_RETURN"}"#
        #expect(try JSONDecoder().decode(ProgressionXpEvent.self, from: Data(missing.utf8)).at == nil)

        let malformed = #"{"amount":5,"reason":"DAILY_RETURN","at":"not-a-number"}"#
        #expect(try JSONDecoder().decode(ProgressionXpEvent.self, from: Data(malformed.utf8)).at == nil)
    }

    @Test("A full ProgressionState with string `at` events decodes (the production-Postgres shape)")
    func fullStateWithStringAt() throws {
        let json = #"""
        {"enabled":true,"xp":120,"level":2,"levelProgress":0.4,"xpToNext":80,"streak":3,
         "longestStreak":5,
         "recentXpEvents":[{"amount":14,"reason":"POSITION_REVISION","sourceType":"chat","at":"1751234567890"}]}
        """#
        let state = try JSONDecoder().decode(ProgressionState.self, from: Data(json.utf8))
        #expect(state.enabled)
        #expect(state.recentXpEvents?.first?.at == 1_751_234_567_890)
    }
}
