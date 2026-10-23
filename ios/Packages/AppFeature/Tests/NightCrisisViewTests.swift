#if os(macOS)
import Foundation
import Testing

/// The crisis view stays calm and unbranded on the Mac (ARCHITECTURE.md
/// §2.5 rule 5, SPEC.md §5.9): palette only. Night reaches it only through
/// the colour tokens. Its own source carries no Night decoration, its close
/// button keeps the pre-Night look (`brandButtonClassic`), and every Mac
/// host draws it on a flat canvas. A source scan, so a stray edit fails here
/// rather than on a student's worst day. Reads the repo's own files, so it
/// runs when the package is built inside the repo (CI and local).
@Suite("The crisis view carries no Night decoration")
struct NightCrisisViewTests {
    private static let packages = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // AppFeature
        .deletingLastPathComponent()   // Packages

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: packages.appendingPathComponent(path), encoding: .utf8)
    }

    /// Code only: comments may name what the view leaves out.
    private static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Night's decoration and Merc: none of these may appear in the view.
    static let decoration = [
        "NightCanvas", "nightLit", "nightWash", "NightMercLamp", "MercMascot", "Merc(",
        "Gradient", "nightFont", "NightType", "NightStarField", "NightHeroSurface", "nightChrome",
        "glassEffect", "NightPrimaryButton", "NightSecondaryButton", ".animation(", "withAnimation",
    ]

    @Test("CrisisSupportView and MacCrisisNumbers use no Night decoration, no Merc, no gradient, no motion")
    func noDecoration() throws {
        let view = Self.code(try Self.source("DesignSystem/Sources/CrisisSupportView.swift"))
        #expect(view.contains("struct CrisisSupportView"))
        #expect(view.contains("struct MacCrisisNumbers"))
        for word in Self.decoration {
            #expect(!view.contains(word), "CrisisSupportView.swift uses \(word)")
        }
    }

    @Test("Its close button keeps the pre-Night look")
    func classicButton() throws {
        let view = Self.code(try Self.source("DesignSystem/Sources/CrisisSupportView.swift"))
        #expect(view.contains(".environment(\\.brandButtonClassic, true)"))
        let button = Self.code(try Self.source("DesignSystem/Sources/BrandButton.swift"))
        #expect(button.contains("brandButtonClassic"), "BrandButton must still read the flag")
    }

    @Test("Every Mac host draws it on a flat canvas")
    func flatHosts() throws {
        let quiz = Self.code(try Self.source("ChatFeature/Sources/Mac/NightQuizSheet.swift"))
        #expect(quiz.contains("NightCanvas(pools: model.phase == .support ? .flat"))
        let unitTest = Self.code(try Self.source("CurriculumFeature/Sources/UnitTestView.swift"))
        #expect(unitTest.contains("NightCanvas(pools: model.phase == .support ? .flat"))
        // The unit check's support branch is the view itself, nothing around it.
        let content = Self.code(try Self.source("CurriculumFeature/Sources/Mac/NightUnitTest.swift"))
        let support = try #require(content.range(of: "private var supportPhase: some View {"))
        let body = content[support.upperBound...].prefix(160)
        #expect(body.contains("CrisisSupportView(closeTitle: \"Back to your path\", onClose: onExit)"))
        for word in Self.decoration {
            #expect(!body.contains(word), "the unit check's support branch uses \(word)")
        }
    }
}
#endif
