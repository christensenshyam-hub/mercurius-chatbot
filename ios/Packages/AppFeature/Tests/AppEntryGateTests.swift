import Testing
@testable import AppFeature

@Suite("AppEntryView gate decision")
struct AppEntryGateTests {

    @Test("Fresh install: no consent, no onboarding → gate")
    func freshInstall() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: false, clearedThisLaunch: false))
    }

    @Test("Pre-2.3.0 install: onboarding done but consent never recorded → gate")
    func preConsentInstall() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: false))
    }

    @Test("Current consent and onboarding done → no gate")
    func consented() {
        #expect(!AppEntryView.showsGate(consentVersion: 1, hasSeenOnboarding: true, clearedThisLaunch: false))
    }

    @Test("Consent without onboarding still runs the full flow")
    func consentedButNeverOnboarded() {
        #expect(AppEntryView.showsGate(consentVersion: 1, hasSeenOnboarding: false, clearedThisLaunch: false))
    }

    @Test("Completing the flow in this launch clears the gate even if the stored flags read stale")
    func clearedThisLaunchWins() {
        // The UI tests pin `-consentVersion 0` through the argument domain,
        // which shadows the flow's own write for the whole process.
        #expect(!AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: false, clearedThisLaunch: true))
        #expect(!AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: true))
    }

    @Test("Withdrawing consent (version reset, flag cleared) re-gates")
    func withdrawal() {
        #expect(AppEntryView.showsGate(consentVersion: 0, hasSeenOnboarding: true, clearedThisLaunch: false))
    }
}
