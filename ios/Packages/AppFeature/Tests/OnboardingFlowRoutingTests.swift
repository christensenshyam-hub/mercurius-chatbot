import Testing
@testable import AppFeature

@Suite("OnboardingFlow routing")
struct OnboardingFlowRoutingTests {

    @Test("Full mode opens on Meet Merc; gate-only skips straight to the age check")
    func initialStep() {
        #expect(OnboardingFlow.initialStep(for: .full) == .meet)
        #expect(OnboardingFlow.initialStep(for: .gateOnly) == .age)
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
