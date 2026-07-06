import Testing
import Foundation
import DesignSystem
@testable import ChatFeature

// Unit tests for `MercPresenceController` — the ephemeral Merc state machine.
// Synchronous transitions are asserted directly; the idle→sleep→hide timer is
// exercised with tiny durations.

@MainActor
struct MercPresenceControllerTests {

    @Test func startsHiddenAndIdle() {
        let c = MercPresenceController()
        #expect(c.isVisible == false)
        #expect(c.state == .idle)
    }

    @Test func greetingPopsInWithWave() {
        let c = MercPresenceController()
        c.chatStarted(greet: true)
        #expect(c.isVisible)
        #expect(c.state == .wave)
    }

    @Test func resumedThreadAppearsIdleWithoutWave() {
        let c = MercPresenceController()
        c.chatStarted(greet: false)
        #expect(c.isVisible)
        #expect(c.state == .idle)
    }

    @Test func greetingHappensOnlyOnce() async throws {
        let c = MercPresenceController()
        c.introHold = 0.03
        c.chatStarted(greet: true)
        #expect(c.state == .wave)
        try await Task.sleep(for: .seconds(0.07))   // wave settles to idle on its own
        #expect(c.state == .idle)
        c.chatStarted(greet: true)                  // a second start must not re-wave
        #expect(c.state == .idle)
    }

    @Test func thinkingWhileStreaming() {
        let c = MercPresenceController()
        c.thinkingBegan()
        #expect(c.isVisible)
        #expect(c.state == .thinking)
    }

    @Test func chatStartDoesNotOverrideThinking() {
        let c = MercPresenceController()
        c.thinkingBegan()
        c.chatStarted(greet: true)   // a resumed-while-streaming race must not stomp thinking
        #expect(c.state == .thinking)
    }

    @Test func firstMessageWaveSurvivesThinkingSignal() {
        // Real first-send order: the messages 0→2 edge greets first, then the
        // streaming phase arrives. The entrance wave must not be stomped.
        let c = MercPresenceController()
        c.chatStarted(greet: true)
        #expect(c.state == .wave)
        c.thinkingBegan()            // phase → .sending, same transaction
        #expect(c.state == .wave)    // wave plays out; thinking deferred until it settles
    }

    @Test func activityDuringThinkingDoesNotDoze() async throws {
        let c = MercPresenceController()
        c.idleToSleep = 0.05
        c.sleepToHide = 0.05
        c.thinkingBegan()            // assistant streaming
        c.activity()                 // a racing message/draft bump mid-stream
        try await Task.sleep(for: .seconds(0.15))   // past idle→sleep
        #expect(c.state == .thinking) // must NOT have dozed off mid-response
        #expect(c.isVisible)
    }

    @Test func successfulReplyNods() {
        let c = MercPresenceController()
        c.thinkingBegan()
        c.thinkingEnded(positive: true)
        #expect(c.state == .happy)
    }

    @Test func failedOrEmptyReplySettlesToIdle() {
        let c = MercPresenceController()
        c.thinkingBegan()
        c.thinkingEnded(positive: false)
        #expect(c.state == .idle)
    }

    @Test func celebrateFlashes() {
        let c = MercPresenceController()
        c.celebrate()
        #expect(c.isVisible)
        #expect(c.state == .celebrate)
    }

    @Test func resetHidesAndClears() {
        let c = MercPresenceController()
        c.chatStarted(greet: true)
        c.reset()
        #expect(c.isVisible == false)
        #expect(c.state == .idle)
    }

    @Test func goesToSleepThenFadesOut() async throws {
        let c = MercPresenceController()
        c.idleToSleep = 0.10
        c.sleepToHide = 0.10
        c.chatStarted(greet: false)
        #expect(c.isVisible)

        try await Task.sleep(for: .seconds(0.18))   // past idle→sleep, mid hide-countdown
        #expect(c.state == .sleep)
        #expect(c.isVisible)

        try await Task.sleep(for: .seconds(0.18))   // past sleep→hide
        #expect(c.isVisible == false)
    }

    @Test func activityWakesFromSleep() async throws {
        let c = MercPresenceController()
        c.idleToSleep = 0.08
        c.sleepToHide = 5.0                          // long, so it can't hide before we wake it
        c.chatStarted(greet: false)

        try await Task.sleep(for: .seconds(0.14))    // let it doze off
        #expect(c.state == .sleep)

        c.activity()
        #expect(c.state == .idle)
        #expect(c.isVisible)
    }
}
