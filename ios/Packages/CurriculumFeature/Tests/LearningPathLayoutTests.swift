import Testing
import SwiftUI
@testable import CurriculumFeature

// AUD-47: at accessibility text sizes the path is a straight list whose
// titles wrap, and the node and the list row say the same thing.
@Suite("Learning path layout")
struct LearningPathLayoutTests {

    @Test("The winding path up to xxxLarge, the list at every accessibility size")
    func layoutBySize() {
        let standard: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
        let accessibility: [DynamicTypeSize] = [.accessibility1, .accessibility2, .accessibility3,
                                                .accessibility4, .accessibility5]
        for size in standard { #expect(LearningPathLayout.forSize(size) == .winding, "\(size)") }
        for size in accessibility { #expect(LearningPathLayout.forSize(size) == .list, "\(size)") }
    }

    @Test("Each lesson status keeps its words and glyph")
    func lessonPresentation() {
        #expect(PathStopPresentation.lesson(.completed).statusText == "Completed")
        #expect(PathStopPresentation.lesson(.current).statusText == "Start now")
        #expect(PathStopPresentation.lesson(.inProgress).statusText == "In progress")
        #expect(PathStopPresentation.lesson(.locked).statusText == "Locked")
        #expect(PathStopPresentation.lesson(.available).statusText == nil)
        #expect(PathStopPresentation.lesson(.completed).systemImage == "checkmark")
        #expect(PathStopPresentation.lesson(.locked).systemImage == "lock.fill")
    }

    @Test("Each unit-test status keeps its words and glyph")
    func unitTestPresentation() {
        #expect(PathStopPresentation.unitTest(.completed).statusText == "Mastered")
        #expect(PathStopPresentation.unitTest(.current).statusText == "Take the test")
        #expect(PathStopPresentation.unitTest(.locked).statusText == "Finish the unit first")
        #expect(PathStopPresentation.unitTest(.available).statusText == "Ready")
        #expect(PathStopPresentation.unitTest(.completed).systemImage == "checkmark.seal.fill")
    }

    @Test("Status lines use the text tones: done green, active indigo, the rest secondary")
    func tones() {
        #expect(PathStopPresentation.lesson(.completed).tone == .done)
        #expect(PathStopPresentation.lesson(.current).tone == .active)
        #expect(PathStopPresentation.lesson(.inProgress).tone == .active)
        #expect(PathStopPresentation.lesson(.locked).tone == .muted)
        #expect(PathStopPresentation.unitTest(.completed).tone == .done)
        #expect(PathStopPresentation.unitTest(.available).tone == .active)
        #expect(PathStopPresentation.unitTest(.locked).tone == .muted)
    }

    @Test("VoiceOver reads the full title and status, whatever the layout")
    func labels() {
        #expect(PathStopPresentation.lessonLabel(number: 2, title: "Training data and where knowledge comes from",
                                                 status: .locked)
                == "Lesson 2: Training data and where knowledge comes from. Locked.")
        #expect(PathStopPresentation.lessonLabel(number: 1, title: "What happens when you type a prompt",
                                                 status: .available)
                == "Lesson 1: What happens when you type a prompt. Available.")
        #expect(PathStopPresentation.unitTestLabel(unitNumber: "01", status: .current)
                == "Unit 01 cumulative test. Take the test.")
    }
}
