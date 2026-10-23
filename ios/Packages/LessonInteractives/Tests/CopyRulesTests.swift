import Foundation
import Testing
@testable import LessonInteractives

@Suite("Interactives: the copy rules")
struct CopyRulesTests {

    @Test("The frame's own words keep the register")
    func shellCopy() {
        let found = InteractiveCopyRules.violations(in: InteractiveShellCopy.everyLine, card: nil)
        #expect(found.isEmpty, "\(found)")
    }

    @Test("The register catches times, saves, hints and verification")
    func catches() {
        for line in ["Takes 90 seconds", "about 5 min", "a few minutes", "Saved to your notebook", "Give me a hint",
                     "These are verified sources", "Pinned for later"] {
            #expect(!InteractiveCopyRules.violations(in: [line], card: nil).isEmpty, "\(line)")
        }
    }

    @Test("Intent words are banned outside a card's prediction lines")
    func intent() {
        let prompt = "At which step did the model decide to make it up?"
        let refutation = "No step decided to make it up."
        let claim = "The model decided to lie."
        #expect(InteractiveCopyRules.violations(in: [prompt], card: .citationThatWasnt).isEmpty)
        #expect(!InteractiveCopyRules.violations(in: [refutation, claim], card: .citationThatWasnt).isEmpty)
        #expect(InteractiveCopyRules.violations(in: [refutation], card: .citationThatWasnt,
                                                predictionLines: [refutation]).isEmpty)
        for line in ["The boat cheats.", "It knows the answer.", "It wants points.", "The agent believes the page.",
                     "It tricks you.", "A lazy model", "It lies."] {
            #expect(!InteractiveCopyRules.violations(in: [line], card: .patchTheReward).isEmpty, "\(line)")
        }
        // The student's own belief isn't the model's intent.
        #expect(InteractiveCopyRules.violations(in: ["Believe everything", "Doubt most"], card: .doubtDial).isEmpty)
    }

    @Test("Exceptions are per card and listed in one place")
    func exceptions() {
        let line = "Students with hints scored higher in practice."
        #expect(InteractiveCopyRules.violations(in: [line], card: .predictTheExam).isEmpty)
        #expect(!InteractiveCopyRules.violations(in: [line], card: .doubtDial).isEmpty)
        #expect(Set(InteractiveCopyRules.exceptions.keys) == [.predictTheExam])
        #expect(InteractiveCopyRules.exceptions.values.allSatisfy { $0.values.allSatisfy { !$0.isEmpty } },
                "every exception says why")
    }

    @Test("Labels say what their kind requires")
    func labels() {
        let example = InteractiveLabel(.example, "Example, written for this lesson. Every name in it is invented.")
        let run = InteractiveLabel(.example, "An example run we wrote, not a live agent.")
        let toy = InteractiveLabel(.toy, "A toy we built, not the real game.")
        let madeUp = InteractiveLabel(.madeUp, "A made-up feed.")
        let ours = InteractiveLabel(.ourArithmetic, "Scaled to 1,000 stays: our arithmetic.")
        let bad = InteractiveLabel(.toy, "Amazon's real scorer.")
        for label in [example, run, toy, madeUp, ours] { #expect(label.isWellFormed, "\(label.text)") }
        #expect(!bad.isWellFormed)
        #expect(InteractiveCopyRules.missingLabels([.toy, .madeUp], in: [toy, madeUp]).isEmpty)
        #expect(InteractiveCopyRules.missingLabels([.toy, .ourArithmetic], in: [toy, bad]) == [.ourArithmetic])
    }
}
