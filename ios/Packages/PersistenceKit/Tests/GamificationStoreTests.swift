import Testing
import Foundation
import NetworkingKit
@testable import PersistenceKit

private func freshDefaults(_ tag: String) -> UserDefaults {
    UserDefaults(suiteName: "test-\(tag)-\(UUID().uuidString)")!
}

/// Stub that records calls so we can assert the store never reaches the network
/// when the client gate is off, and applies server state correctly when it's on.
private final class StubProgressionProvider: ProgressionProviding, @unchecked Sendable {
    var state: ProgressionState
    var event: ProgressionEventResult
    /// When set, `progression(sessionId:)` throws it — to exercise the failure path.
    var error: Error?
    private(set) var progressionCalls = 0
    private(set) var eventCalls = 0

    init(
        state: ProgressionState = ProgressionState(
            enabled: true, xp: 140, level: 2, levelProgress: 0.42,
            xpToNext: 60, streak: 3, longestStreak: 5,
            recentXpEvents: [ProgressionXpEvent(amount: 14, reason: "POSITION_REVISION", sourceType: nil, at: 1)]
        ),
        event: ProgressionEventResult = ProgressionEventResult(
            enabled: true, status: "awarded", awarded: 14, leveledUp: false,
            reason: "POSITION_REVISION", xp: 154, level: 2, levelProgress: 0.5, xpToNext: 46, streak: 3
        )
    ) {
        self.state = state
        self.event = event
    }

    func progression(sessionId: String) async throws -> ProgressionState {
        progressionCalls += 1
        if let error { throw error }
        return state
    }

    func recordProgressionEvent(
        sessionId: String, reason: ProgressionReason,
        sourceType: String?, sourceId: String?, sessionRef: String?
    ) async throws -> ProgressionEventResult {
        eventCalls += 1
        return event
    }
}

@MainActor
@Suite("GamificationStore (standby)")
struct GamificationStoreTests {
    @Test("client gate OFF: refresh is inert and makes no provider call")
    func flagOffInert() async {
        let provider = StubProgressionProvider()
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: false)
        await store.refresh(using: provider, sessionId: "abc")
        #expect(store.enabled == false)
        #expect(provider.progressionCalls == 0)
        #expect(store.xp == 0)
        #expect(store.loadPhase == .idle)  // flag off → never even attempts a load
    }

    @Test("client gate OFF: recordEvent is inert (no network, no nudge)")
    func recordOffInert() async {
        let provider = StubProgressionProvider()
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: false)
        await store.recordEvent(using: provider, sessionId: "abc", reason: .moduleCompleted, sourceId: "m1")
        #expect(provider.eventCalls == 0)
        #expect(store.lastNudge == nil)
    }

    @Test("client gate ON: refresh applies the snapshot + factual recent credits")
    func refreshApplies() async {
        let provider = StubProgressionProvider()
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: true)
        await store.refresh(using: provider, sessionId: "abc")
        #expect(provider.progressionCalls == 1)
        #expect(store.enabled == true)
        #expect(store.xp == 140)
        #expect(store.level == 2)
        #expect(store.streak == 3)
        #expect(abs(store.levelProgress - 0.42) < 0.0001)
        #expect(store.recentCredits.count == 1)
        #expect(store.recentCredits.first?.label == "Revised your position")
        // A plain refresh never raises a nudge.
        #expect(store.lastNudge == nil)
        #expect(store.loadPhase == .loaded)
    }

    @Test("refresh failure disables and records a .failed phase (APIError message)")
    func refreshFailure() async {
        let provider = StubProgressionProvider()
        provider.error = APIError.offline
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: true)
        await store.refresh(using: provider, sessionId: "abc")
        #expect(store.enabled == false)
        var isFailed = false
        if case .failed = store.loadPhase { isFailed = true }
        #expect(isFailed)
    }

    @Test("client gate ON but server disabled: store stays disabled")
    func serverDisabled() async {
        let provider = StubProgressionProvider(state: ProgressionState(enabled: false))
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: true)
        await store.refresh(using: provider, sessionId: "abc")
        #expect(store.enabled == false)
    }

    @Test("recordEvent surfaces a factual nudge + credit when nudges on")
    func nudgeOnAward() async {
        let provider = StubProgressionProvider()
        let store = GamificationStore(defaults: freshDefaults("gam"), clientEnabled: true)
        await store.recordEvent(using: provider, sessionId: "abc", reason: .positionRevision)
        #expect(provider.eventCalls == 1)
        #expect(store.lastNudge?.label == "Revised your position")  // the MOVE, not "correct"
        #expect(store.lastNudge?.xp == 14)
        #expect(store.xp == 154)
        #expect(store.recentCredits.first?.label == "Revised your position")
        store.dismissNudge()
        #expect(store.lastNudge == nil)
    }

    @Test("recordEvent honors the nudges-off preference (credit logged, no nudge)")
    func nudgePrefOff() async {
        let defaults = freshDefaults("gam")
        GamificationFlag.setNudgesEnabled(false, defaults)
        let provider = StubProgressionProvider()
        let store = GamificationStore(defaults: defaults, clientEnabled: true)
        await store.recordEvent(using: provider, sessionId: "abc", reason: .selfCorrection)
        #expect(store.xp == 154)                       // XP still updates
        #expect(store.lastNudge == nil)                // but no nudge pops
        #expect(store.recentCredits.isEmpty == false)  // the credit is still logged
    }
}
