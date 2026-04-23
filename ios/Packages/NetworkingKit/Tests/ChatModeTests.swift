import Testing
import Foundation
@testable import NetworkingKit

@Suite("ChatMode")
struct ChatModeTests {

    @Test("Every case has a non-empty displayName")
    func displayNames() {
        for mode in ChatMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode) has empty displayName")
        }
    }

    @Test("displayName is stable and distinct across modes")
    func displayNamesAreDistinct() {
        let names = ChatMode.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "displayNames collide: \(names)")
    }

    @Test("Every case has a non-empty blurb")
    func blurbs() {
        for mode in ChatMode.allCases {
            #expect(!mode.blurb.isEmpty, "\(mode) has empty blurb")
        }
    }

    @Test("Only .direct requires unlock — that's the Socratic comprehension-test gate")
    func requiresUnlockFlags() {
        #expect(ChatMode.direct.requiresUnlock)
        #expect(!ChatMode.socratic.requiresUnlock)
        #expect(!ChatMode.debate.requiresUnlock)
        #expect(!ChatMode.discussion.requiresUnlock)
    }

    @Test("id equals rawValue — enables Identifiable/ForEach without a manual keyPath")
    func idMatchesRawValue() {
        for mode in ChatMode.allCases {
            #expect(mode.id == mode.rawValue)
        }
    }

    @Test("Codable round-trip preserves every case")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for mode in ChatMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(ChatMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("Raw values match the server wire contract")
    func rawValuesAreTheServerContract() {
        // Pin the strings — the server's `/api/chat` and `/api/mode`
        // endpoints match against these exact values. If someone
        // renames a case, this test fails and prompts them to also
        // update the server side.
        #expect(ChatMode.socratic.rawValue == "socratic")
        #expect(ChatMode.direct.rawValue == "direct")
        #expect(ChatMode.debate.rawValue == "debate")
        #expect(ChatMode.discussion.rawValue == "discussion")
    }

    @Test("allCases covers exactly the 4 modes and their order is stable")
    func allCasesShape() {
        #expect(ChatMode.allCases == [.socratic, .direct, .debate, .discussion])
    }
}
