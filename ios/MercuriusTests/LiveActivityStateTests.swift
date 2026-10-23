import Foundation
import Testing
import MercuriusActivity

/// ActivityKit persists a running activity's `ContentState` as JSON and
/// decodes it again in the widget extension. AUD-37 added the weekly frame as
/// optional fields, so a card started by an earlier build must still decode.
/// (`ContentState` is iOS-only, so this lives in the simulator test target.)
@Suite("Live Activity content state")
struct LiveActivityStateTests {
    typealias State = LearningActivityAttributes.ContentState

    @Test("A state written before AUD-37 (no week fields) still decodes, with no week and no countdown")
    func decodesLegacyState() throws {
        let legacy = """
        {"phase":"active","lessonsDone":0,"lessonsTotal":4,"progress":0,"streakCount":0,
         "level":2,"lessonsToLevel":4,"deadline":800000000,"lastUpdated":799990000}
        """
        let state = try JSONDecoder().decode(State.self, from: Data(legacy.utf8))
        #expect(state.phase == .active)
        #expect(state.lessonsToLevel == 4)
        #expect(state.weekDone == nil)
        #expect(state.weekGoal == nil)
        #expect(state.streakAtRisk == nil)
    }

    @Test("The weekly frame round-trips")
    func roundTrips() throws {
        let state = State(
            phase: .active, lessonsDone: 1, lessonsTotal: 4, progress: 0.25,
            streakCount: 3, level: 2, lessonsToLevel: 3,
            deadline: Date(timeIntervalSince1970: 1_800_000_000),
            lastUpdated: Date(timeIntervalSince1970: 1_799_990_000),
            weekDone: 1, weekGoal: 2, streakAtRisk: true
        )
        let decoded = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        #expect(decoded.weekDone == 1)
        #expect(decoded.weekGoal == 2)
        #expect(decoded.streakAtRisk == true)
    }
}
