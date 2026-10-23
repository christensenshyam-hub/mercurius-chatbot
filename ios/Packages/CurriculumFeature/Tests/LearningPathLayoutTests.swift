import Testing
import SwiftUI
@testable import CurriculumFeature

// AUD-47: at accessibility text sizes the path is a straight list whose
// titles wrap, and the node and the list row say the same thing.
@Suite("Learning path layout")
struct LearningPathLayoutTests {

    @Test("The winding path below xxxLarge, the list from xxxLarge up, where winding titles truncated")
    func layoutBySize() {
        let winding: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge]
        let list: [DynamicTypeSize] = [.xxxLarge, .accessibility1, .accessibility2, .accessibility3,
                                       .accessibility4, .accessibility5]
        for size in winding { #expect(LearningPathLayout.forSize(size) == .winding, "\(size)") }
        for size in list { #expect(LearningPathLayout.forSize(size) == .list, "\(size)") }
    }

    @Test("The path opens with the unit's banner on a unit's first lesson, centred otherwise, at the top when done")
    func openingScroll() {
        let rows: [(id: String, isBanner: Bool)] = [
            ("H_u1", true), ("L_1", false), ("L_2", false), ("T_u1", false),
            ("H_u2", true), ("L_5", false), ("L_6", false), ("T_u2", false),
        ]
        #expect(PathOpeningScroll.target(frontierID: "L_1", rows: rows) == .unitBanner(id: "H_u1"),
                "at AX5 the top of the path is its title alone; the banner and the node come first")
        #expect(PathOpeningScroll.target(frontierID: "L_5", rows: rows) == .unitBanner(id: "H_u2"),
                "Unit 2's banner whole, its first node below")
        #expect(PathOpeningScroll.target(frontierID: "L_2", rows: rows) == .centered(id: "L_2"))
        #expect(PathOpeningScroll.target(frontierID: "T_u1", rows: rows) == .centered(id: "T_u1"))
        #expect(PathOpeningScroll.target(frontierID: nil, rows: rows) == .top, "the whole path is done")
        #expect(PathOpeningScroll.target(frontierID: "gone", rows: rows) == .top)
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
