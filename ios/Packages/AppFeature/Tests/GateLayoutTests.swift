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

    @Test("The age wheel never shrinks below three rows")
    func wheelHeight() {
        #expect(AgeStep.wheelMinHeight >= 120)
    }
}
