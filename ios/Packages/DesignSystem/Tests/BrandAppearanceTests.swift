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
}
