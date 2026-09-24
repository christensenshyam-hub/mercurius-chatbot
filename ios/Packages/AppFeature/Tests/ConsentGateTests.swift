import Testing
@testable import AppFeature

@Suite("ConsentGate")
struct ConsentGateTests {

    @Test("Never-consented (0) needs the gate")
    func neverConsented() {
        #expect(ConsentGate.needsGate(storedVersion: 0))
    }

    @Test("The current version does not need the gate")
    func currentVersionPasses() {
        #expect(ConsentGate.currentVersion == 1)
        #expect(!ConsentGate.needsGate(storedVersion: 1))
    }

    @Test("A newer-than-current stored version does not re-gate")
    func newerVersionPasses() {
        #expect(!ConsentGate.needsGate(storedVersion: 2))
    }

    @Test("Storage key is the UserDefaults key the launch args target")
    func storageKey() {
        #expect(ConsentGate.storageKey == "consentVersion")
    }

    /// The XCUITests can't import AppFeature, so `MercuriusUITests.swift`
    /// hard-codes `"-consentVersion", "1"` as the gate bypass. When this
    /// version is bumped, those launch args must be bumped in lockstep or
    /// every UI test will land on the consent gate.
    @Test("currentVersion is pinned to the UI tests' `-consentVersion 1` launch arg")
    func currentVersionMatchesUITestLaunchArgs() {
        #expect(ConsentGate.currentVersion == 1)
    }
}

@Suite("AgeGate")
struct AgeGateTests {

    @Test("Boundary: 12 is blocked, 13 is eligible")
    func boundary() {
        #expect(AgeGate.minimumAge == 13)
        #expect(!AgeGate.isEligible(age: 12))
        #expect(AgeGate.isEligible(age: 13))
    }

    @Test("Far ends")
    func farEnds() {
        #expect(!AgeGate.isEligible(age: 0))
        #expect(AgeGate.isEligible(age: 18))
        #expect(AgeGate.isEligible(age: 99))
    }

    @Test("Picker choices run 12…18, youngest first, with exactly one blocked row")
    func choices() {
        #expect(AgeGate.choices == [12, 13, 14, 15, 16, 17, 18])
        #expect(AgeGate.choices.filter { !AgeGate.isEligible(age: $0) } == [12])
    }

    @Test("Picker labels: open buckets at both ends, plain numbers between")
    func labels() {
        #expect(AgeGate.label(for: 12) == "12 or younger")
        #expect(AgeGate.label(for: 13) == "13")
        #expect(AgeGate.label(for: 17) == "17")
        #expect(AgeGate.label(for: 18) == "18 or older")
    }
}
