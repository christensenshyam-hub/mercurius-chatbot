import Testing
import SwiftUI
@testable import DesignSystem

/// Both apps are dark only (docs/ios-night-only/PR.md).
@Suite("One appearance: Night's dark")
struct BrandAppearanceTests {
    @Test("Every scene root applies the dark scheme")
    func dark() {
        #expect(BrandAppearance.colorScheme == .dark)
    }

    @Test("The iPhone's interface tint is the readable indigo, not the fill")
    func tintIsAccentText() {
        // The tab bar's selected item, back and toolbar buttons and text
        // buttons draw in it. The fill indigo as text fails on the canvas
        // (BrandContrastTests.accentFillFailsAsText).
        #expect(BrandAppearance.tint == BrandColor.accentText)
        #expect(BrandAppearance.tint != BrandColor.accent)
    }
}
