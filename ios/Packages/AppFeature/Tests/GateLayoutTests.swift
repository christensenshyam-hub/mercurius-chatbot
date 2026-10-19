import Testing
import SwiftUI
@testable import AppFeature

// AUD-12: at accessibility sizes the gate's headings scroll with the content
// (the CTAs are pinned), and the age wheel keeps a usable height.
@Suite("First-run gate layout")
struct GateLayoutTests {

    @Test("Headings sit above the content up to xxxLarge, and scroll with it at accessibility sizes")
    func headingScrolls() {
        typealias Container = GateStepContainer<EmptyView, EmptyView>
        #expect(!Container.headingScrolls(at: .large))
        #expect(!Container.headingScrolls(at: .xxxLarge))
        #expect(Container.headingScrolls(at: .accessibility1))
        #expect(Container.headingScrolls(at: .accessibility5))
    }

    @Test("A screen can scroll its heading at every size (the disclosure, whose switch is pinned)")
    func headingAlwaysScrolls() {
        typealias Container = GateStepContainer<EmptyView, EmptyView>
        #expect(Container.headingScrolls(at: .large, always: true))
        #expect(Container.headingScrolls(at: .xxxLarge, always: true))
        #expect(!Container.headingScrolls(at: .large, always: false))
    }

    @Test("The age wheel never shrinks below three rows")
    func wheelHeight() {
        #expect(AgeStep.wheelMinHeight >= 120)
    }
}

// AUD-27 / AUD-50: what the disclosure and limits screens say, and where
// the consent switch sits.
@Suite("First-run gate copy")
struct GateCopyTests {

    private var disclosure: String { DisclosureStep.rows.map(\.text).joined(separator: "\n") }

    @Test("The disclosure says how long the server keeps chats, and that deleting the app doesn't delete them")
    func disclosureRetention() {
        #expect(disclosure.contains("90 days"))
        #expect(disclosure.contains("photos for 24 hours"))
        // Names the button as Settings labels it, and ends on a sentence.
        #expect(disclosure.contains("Settings → Delete my data & start over."))
        #expect(disclosure.contains("Deleting the app doesn't delete them."))
        // The rows the screen had before stay, in their order around the new one.
        #expect(DisclosureStep.rows.map(\.symbol)
                == ["paperplane", "clock.arrow.circlepath", "person.crop.circle.badge.questionmark"])
        #expect(Set(DisclosureStep.rows.map(\.symbol)).count == DisclosureStep.rows.count)
    }

    @Test("The agreement sentence on the switch is unchanged")
    func toggleSentence() {
        #expect(DisclosureStep.toggleText
                == "I understand my messages and photos are sent to Anthropic's Claude to generate replies")
    }

    @Test("The limits screen warns against sharing private details, and its count matches its rows")
    func limitsPrivacyRow() {
        let texts = LimitsStep.rows.map(\.text)
        #expect(texts.contains("Don't share your full name, address or anything private."))
        #expect(texts.last == "If you're in crisis, call or text 988, or text HOME to 741741.")
        #expect(LimitsStep.rows.count == 4)
        #expect(LimitsStep.subtitle.hasPrefix("Four things"))
        #expect(Set(LimitsStep.rows.map(\.symbol)).count == LimitsStep.rows.count)
    }

    @Test("Where the switch scrolls out of sight, a visible line says what Agree is waiting for")
    func consentSwitchHint() {
        #expect(!DisclosureStep.showsSwitchHint(agreed: false, at: .large), "the switch is pinned in view")
        #expect(!DisclosureStep.showsSwitchHint(agreed: false, at: .xxxLarge), "the switch is pinned in view")
        #expect(DisclosureStep.showsSwitchHint(agreed: false, at: .accessibility1))
        #expect(DisclosureStep.showsSwitchHint(agreed: false, at: .accessibility5))
        #expect(!DisclosureStep.showsSwitchHint(agreed: true, at: .accessibility5), "nothing left to do")
        #expect(DisclosureStep.switchHint == "Turn on the switch above to continue")
    }

    @Test("At accessibility sizes, a visible line says Continue is waiting for an age")
    func ageWheelHint() {
        #expect(!AgeStep.showsWheelHint(hasPick: false, at: .large))
        #expect(!AgeStep.showsWheelHint(hasPick: false, at: .xxxLarge))
        #expect(AgeStep.showsWheelHint(hasPick: false, at: .accessibility1))
        #expect(AgeStep.showsWheelHint(hasPick: false, at: .accessibility5))
        #expect(!AgeStep.showsWheelHint(hasPick: true, at: .accessibility5))
    }

    @Test("The consent switch is pinned above Agree up to xxxLarge, and scrolls with the rows at accessibility sizes")
    func consentTogglePlacement() {
        #expect(DisclosureStep.pinsConsentToggle(at: .large))
        #expect(DisclosureStep.pinsConsentToggle(at: .xxxLarge))
        #expect(!DisclosureStep.pinsConsentToggle(at: .accessibility1))
        #expect(!DisclosureStep.pinsConsentToggle(at: .accessibility5))
    }
}
