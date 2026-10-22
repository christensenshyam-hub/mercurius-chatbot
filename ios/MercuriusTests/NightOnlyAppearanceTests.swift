import Testing
import SwiftUI
import UIKit
import DesignSystem

/// The iPhone is dark only and wears Night Studio's palette, the Mac's
/// (docs/ios-night-only/PR.md). These run in the app on the simulator, so
/// they check what iOS actually resolves; `BrandContrastTests` (DesignSystem,
/// `swift test`) checks the same values' contrast on the macOS host.
@Suite("The iPhone is dark only, in Night Studio's palette")
@MainActor
struct NightOnlyAppearanceTests {

    @Test("Info.plist locks the app to Dark: the launch, alerts, the keyboard and the system's sheets")
    func infoPlistIsDark() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String == "Dark")
    }

    @Test("Every scene root applies the dark scheme")
    func schemeIsDark() {
        #expect(BrandAppearance.colorScheme == .dark)
    }

    /// `color` resolved for a trait collection, as 0xRRGGBB.
    static func hex(_ color: Color, style: UIUserInterfaceStyle,
                    contrast: UIAccessibilityContrast = .normal) -> UInt32 {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(accessibilityContrast: contrast),
        ])
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ c: CGFloat) -> UInt32 { UInt32(max(0, min(255, (c * 255).rounded()))) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }

    /// Each token: Night's dark value, and its value under Increase Contrast.
    static let tokens: [(String, Color, UInt32, UInt32)] = [
        ("background", BrandColor.background, 0x0B0E2E, 0x05071A),
        ("surface", BrandColor.surface, 0x121641, 0x0E1238),
        ("surfaceElevated", BrandColor.surfaceElevated, 0x1A1F52, 0x161B4A),
        ("border", BrandColor.border, 0x2E3258, 0x6E7188),
        ("text", BrandColor.text, 0xF1F2FF, 0xFFFFFF),
        ("textSecondary", BrandColor.textSecondary, 0xB7BDE2, 0xDDE0F7),
        ("accentText", BrandColor.accentText, 0xA5B4FC, 0xC7D2FE),
        ("successText", BrandColor.successText, 0x6EE7A8, 0xA7F3D0),
        ("errorText", BrandColor.errorText, 0xFCA5A5, 0xFECACA),
    ]

    @Test("BrandColor resolves to Night's dark values, in a light trait as in a dark one")
    func resolvesToNightDark() {
        for (name, color, dark, _) in Self.tokens {
            #expect(Self.hex(color, style: .light) == dark, "\(name), light trait")
            #expect(Self.hex(color, style: .dark) == dark, "\(name), dark trait")
            #expect(Self.hex(color, style: .unspecified) == dark, "\(name), unspecified trait")
        }
    }

    @Test("Under Increase Contrast, BrandColor resolves to Night's increased-contrast dark values")
    func increasedContrast() {
        for (name, color, _, darkHC) in Self.tokens {
            #expect(Self.hex(color, style: .dark, contrast: .high) == darkHC, "\(name)")
            #expect(Self.hex(color, style: .light, contrast: .high) == darkHC, "\(name), light trait")
        }
    }

    @Test("The interface tint (the tab bar's selected item, back and text buttons) is Night's readable indigo")
    func interfaceTint() {
        for style in [UIUserInterfaceStyle.light, .dark, .unspecified] {
            #expect(Self.hex(BrandAppearance.tint, style: style) == 0xA5B4FC, "\(style.rawValue)")
            #expect(Self.hex(BrandAppearance.tint, style: style, contrast: .high) == 0xC7D2FE,
                    "\(style.rawValue), Increase Contrast")
        }
    }

    @Test("The fixed brand hues stay fixed")
    func fixedHues() {
        #expect(Self.hex(BrandColor.accent, style: .dark) == 0x6366F1)
        #expect(Self.hex(BrandColor.success, style: .dark) == 0x22C55E)
        #expect(Self.hex(BrandColor.error, style: .dark) == 0xEF4444)
        #expect(Self.hex(BrandColor.mercViolet, style: .light) == 0x7C3AED)
    }
}
