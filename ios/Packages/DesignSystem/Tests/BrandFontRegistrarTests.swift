import CoreText
import Testing
@testable import DesignSystem

// The bundled reading fonts must register and resolve by FAMILY NAME —
// `Font.custom` falls back to SF silently on a wrong name, so these tests are
// the only tripwire against shipping an unresolved face.
@Suite("BrandFontRegistrar")
struct BrandFontRegistrarTests {

    @Test("registration succeeds for the bundled faces")
    func registers() {
        #expect(BrandFontRegistrar.registerReadingFonts())
    }

    @Test("bundled family names resolve via CoreText")
    func familiesResolve() {
        BrandFontRegistrar.registerReadingFonts()
        for family in ["Lexend", "Atkinson Hyperlegible"] {
            let font = CTFontCreateWithName(family as CFString, 16, nil)
            let resolved = CTFontCopyFamilyName(font) as String
            #expect(
                resolved == family,
                "expected \(family), resolved \(resolved) — wrong family name would silently fall back to SF"
            )
        }
    }
}
