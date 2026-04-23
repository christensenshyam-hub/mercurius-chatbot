import Testing
import SwiftUI
@testable import DesignSystem

/// These tests verify the BrandFont scale is wired up as distinct values.
///
/// We can't introspect `Font` to assert the underlying text style directly —
/// SwiftUI intentionally makes it opaque — but `Font` is `Hashable`, so we
/// can at least guarantee each role resolves to a distinct font instance.
/// The practical guarantee this test provides: if a future refactor
/// accidentally collapses two BrandFont values onto the same underlying
/// `Font` (e.g. body and bodyEmphasized silently losing their weight
/// override), this test fails.
@Suite("BrandFont scale")
struct BrandFontTests {

    @Test("All BrandFont values are distinct")
    func allDistinct() {
        let all: [Font] = [
            BrandFont.largeTitle,
            BrandFont.title,
            BrandFont.subheading,
            BrandFont.body,
            BrandFont.bodyEmphasized,
            BrandFont.caption,
            BrandFont.mono,
        ]
        #expect(Set(all).count == all.count)
    }

    @Test("bodyEmphasized differs from body (weight override preserved)")
    func bodyWeightOverridePreserved() {
        #expect(BrandFont.body != BrandFont.bodyEmphasized)
    }

    @Test("mono differs from caption (design override preserved)")
    func monoDesignOverridePreserved() {
        #expect(BrandFont.caption != BrandFont.mono)
    }

    @Test("largeTitle, title, and subheading are all distinct")
    func headingScaleDistinct() {
        #expect(BrandFont.largeTitle != BrandFont.title)
        #expect(BrandFont.title != BrandFont.subheading)
        #expect(BrandFont.largeTitle != BrandFont.subheading)
    }
}
