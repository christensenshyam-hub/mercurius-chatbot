import Testing
import SwiftUI
@testable import DesignSystem

/// The Mac's one type ramp (`MacTypeRamp`): nothing a student reads is set
/// in the Mac's 10 pt footnote, and the body sits between the Mac's UI text
/// and the iPhone's reading text.
@Suite("Mac type ramp")
struct MacTypeRampTests {
    @Test("Body is 15 pt, captions at least 12, headings above body")
    func ramp() {
        #expect(MacTypeRamp.body == 15)
        #expect(MacTypeRamp.caption >= 12)
        #expect(MacTypeRamp.subheading > MacTypeRamp.body)
        #expect(MacTypeRamp.title > MacTypeRamp.subheading)
        #expect(MacTypeRamp.largeTitle > MacTypeRamp.title)
        #expect(MacTypeRamp.reading == MacTypeRamp.body, "replies and the student's text read as one scale")
    }

    @Test("The reading column fits about 80 characters of 15 pt body; the gate's about 75")
    func columns() {
        // SF at 15 pt averages about 7.2 pt a character.
        #expect((MacLayout.readableWidth - 32) / 7.2 <= 85)
        #expect((MacLayout.gateWidth - 48) / 7.2 <= 80)
        #expect(MacLayout.replyMeasure < MacLayout.readableWidth)
    }
}
