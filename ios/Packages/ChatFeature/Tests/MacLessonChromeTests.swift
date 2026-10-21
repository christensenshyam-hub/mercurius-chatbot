import Testing
import Foundation
@testable import ChatFeature
import DesignSystem

/// The lesson's chrome on a Mac: the window's title and subtitle, the way
/// back, and when Escape may take it. Plus the reading size the Mac's
/// replies share with the student's own text.
@Suite("Mac lesson chrome")
struct MacLessonChromeTests {

    @Test("\"UNIT 01\" reads as \"Unit 1\"; anything else is kept, capitalised")
    func unitName() {
        #expect(CurriculumLessonView.unitName("UNIT 01") == "Unit 1")
        #expect(CurriculumLessonView.unitName("UNIT 8") == "Unit 8")
        #expect(CurriculumLessonView.unitName("CURRICULUM") == "Curriculum")
    }

    #if os(macOS)
    @Test("The window's subtitle names the lesson by the path's code, in title case")
    func subtitle() {
        #expect(CurriculumLessonView.macSubtitle(unitLabel: "UNIT 01", lessonNumber: 2, totalInUnit: 4)
            == "Unit 1 · Lesson 1.2")
        #expect(CurriculumLessonView.macSubtitle(unitLabel: "UNIT 03", lessonNumber: 1, totalInUnit: 0)
            == "Unit 3 · Lesson 3.1")
        #expect(CurriculumLessonView.macSubtitle(unitLabel: "CURRICULUM", lessonNumber: 4, totalInUnit: 0)
            == "Curriculum · Lesson 4")
    }

    @Test("Escape leaves a lesson only when nothing would be lost")
    func escapeRule() {
        #expect(CurriculumLessonView.escapeLeaves(isSending: false, draft: "", hasAttachment: false, isCelebrating: false))
        #expect(CurriculumLessonView.escapeLeaves(isSending: false, draft: " \n", hasAttachment: false, isCelebrating: false))
        #expect(!CurriculumLessonView.escapeLeaves(isSending: true, draft: "", hasAttachment: false, isCelebrating: false),
                "not while a reply is coming in")
        #expect(!CurriculumLessonView.escapeLeaves(isSending: false, draft: "Tokens are", hasAttachment: false, isCelebrating: false),
                "not with an answer in the composer")
        #expect(!CurriculumLessonView.escapeLeaves(isSending: false, draft: "", hasAttachment: true, isCelebrating: false),
                "not with a photo waiting to send")
        #expect(!CurriculumLessonView.escapeLeaves(isSending: false, draft: "", hasAttachment: false, isCelebrating: true),
                "the celebration takes Escape itself")
    }

    @Test("Merc's replies and the student's own text share the Mac's reading size")
    func oneReadingSize() {
        #expect(MessageBubbleView.replyBaseSize == MacTypeRamp.reading)
        #expect(MacTypeRamp.reading == MacTypeRamp.body)
    }
    #endif
}
