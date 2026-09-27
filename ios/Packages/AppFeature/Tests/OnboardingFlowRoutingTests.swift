import Foundation
import Testing
@testable import AppFeature

@Suite("OnboardingFlow routing")
struct OnboardingFlowRoutingTests {

    @Test("Full mode opens on Meet Merc; gate-only skips straight to the age check")
    func initialStep() {
        #expect(OnboardingFlow.initialStep(for: .full) == .meet)
        #expect(OnboardingFlow.initialStep(for: .gateOnly) == .age)
    }

    @Test("A remembered under-13 answer opens either mode on the under-13 screen")
    func blockedInitialStep() {
        #expect(OnboardingFlow.initialStep(for: .full, ageBlocked: true) == .underThirteen)
        #expect(OnboardingFlow.initialStep(for: .gateOnly, ageBlocked: true) == .underThirteen)
        #expect(OnboardingFlow.initialStep(for: .full, ageBlocked: false) == .meet)
        #expect(OnboardingFlow.initialStep(for: .gateOnly, ageBlocked: false) == .age)
    }

    @Test("The block holds through the cool-off and a clock set back, then lapses")
    func ageBlockCoolOff() {
        let blockedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = blockedAt.timeIntervalSince1970
        #expect(!AgeBlock.isActive(blockedAt: nil, now: blockedAt))
        #expect(!AgeBlock.isActive(blockedAt: 0, now: blockedAt))
        #expect(AgeBlock.isActive(blockedAt: stamp, now: blockedAt))
        #expect(AgeBlock.isActive(blockedAt: stamp, now: blockedAt.addingTimeInterval(AgeBlock.coolOff - 1)))
        #expect(!AgeBlock.isActive(blockedAt: stamp, now: blockedAt.addingTimeInterval(AgeBlock.coolOff)))
        #expect(AgeBlock.isActive(blockedAt: stamp, now: blockedAt.addingTimeInterval(-3600)))
    }

    @Test("The store records the time of the block, never an age")
    func ageBlockStoreRecords() throws {
        let suite = "agebloc-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgeBlockStore(defaults: defaults)
        #expect(!store.isActive())

        let now = Date()
        store.record(now: now)
        #expect(store.isActive(now: now))
        #expect(defaults.dictionaryRepresentation().keys.contains(AgeBlock.storageKey))
        #expect(defaults.double(forKey: AgeBlock.storageKey) == now.timeIntervalSince1970)
    }

    @Test("Age check routes to the disclosure or the terminal screen")
    func afterAge() {
        #expect(OnboardingFlow.step(afterAgeEligible: true) == .disclosure)
        #expect(OnboardingFlow.step(afterAgeEligible: false) == .underThirteen)
    }

    @Test("After the limits ack, full mode shows Your path; gate-only is done")
    func afterLimits() {
        #expect(OnboardingFlow.stepAfterLimits(mode: .full) == .path)
        #expect(OnboardingFlow.stepAfterLimits(mode: .gateOnly) == nil)
    }

    @Test("The under-13 and paused dead ends drop consent, so the reminder guard cancels behind them")
    func deadEndsDropConsent() {
        let dropping = OnboardingFlow.Step.allCases.filter(OnboardingFlow.dropsConsent)
        #expect(dropping == [.underThirteen, .paused])
        // An install that consented in an earlier launch but never finished
        // the full flow reads version 0 again once it reaches a dead end.
        #expect(AppEntryView.reminderReplan(consentVersion: 0, clearedThisLaunch: false) == .cancel)
    }

    @Test("hasSeenOnboarding key is unchanged from 2.2.0")
    func storageKey() {
        #expect(OnboardingFlow.storageKey == "hasSeenOnboarding")
    }

    @Test("Every step has the documented -GateStep spelling")
    func stepSpellings() {
        #expect(OnboardingFlow.Step.allCases.map(\.rawValue) ==
                ["meet", "age", "underThirteen", "disclosure", "paused", "limits", "path"])
    }

    @Test("-GateStep parses a known step and ignores everything else")
    func debugStartStep() {
        #expect(OnboardingFlow.debugStartStep(arguments: ["-GateStep", "paused"]) == .paused)
        #expect(OnboardingFlow.debugStartStep(arguments: ["-UITests", "YES", "-GateStep", "limits"]) == .limits)
        #expect(OnboardingFlow.debugStartStep(arguments: []) == nil)
        #expect(OnboardingFlow.debugStartStep(arguments: ["-GateStep"]) == nil)
        #expect(OnboardingFlow.debugStartStep(arguments: ["-GateStep", "bogus"]) == nil)
    }
}
