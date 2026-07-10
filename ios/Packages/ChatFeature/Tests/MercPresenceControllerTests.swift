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
        // Poll, don't fixed-sleep: on a loaded CI runner the settle timer can
        // fire well after the nominal introHold.
        #expect(await poll { c.state == .idle })    // wave settles on its own
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

        // Poll with a deadline rather than fixed sleeps: on a loaded CI
        // runner a fixed 0.18s sleep can overshoot BOTH timer windows, so a
        // mid-countdown assertion races the controller. The doze-in-place
        // window itself is covered by `activityWakesFromSleep`, which pins
        // `sleepToHide` long so the intermediate state can't be missed.
        #expect(await poll { c.state == .sleep })
        #expect(await poll { !c.isVisible })
    }

    /// Wait until `condition` holds or the deadline passes; returns the final
    /// evaluation. Keeps timer-driven assertions robust on slow shared runners.
    private func poll(
        deadline: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: deadline)
        while clock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func activityWakesFromSleep() async throws {
        let c = MercPresenceController()
        c.idleToSleep = 0.08
        c.sleepToHide = 5.0                          // long, so it can't hide before we wake it
        c.chatStarted(greet: false)

        // Poll, don't fixed-sleep: the doze timer can lag on a loaded runner.
        #expect(await poll { c.state == .sleep })    // let it doze off

        c.activity()
        #expect(c.state == .idle)
        #expect(c.isVisible)
    }
}
