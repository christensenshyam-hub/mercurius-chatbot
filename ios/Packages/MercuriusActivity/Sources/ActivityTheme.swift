import SwiftUI

/// The handoff's three visual directions — Aurora / Eclipse / Dawn — as one
/// theme struct over an identical layout and data model. **Aurora ships** (the
/// vivid, mascot-forward direction); swapping direction is changing
/// `ActivityTheme.current`, never a second widget.
///
/// Token values come straight from the handoff's token tables. Live Activity
/// views resolve light/dark via `@Environment(\.colorScheme)`, so each token
/// carries both appearances.
public struct ActivityTheme: Sendable {

    public struct Duo: Sendable {
        public let light: Color
        public let dark: Color
        public func resolved(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? dark : light
        }
    }

    /// Panel gradient stops (135° linear in the mockups).
    public let panelLight: [Color]
    public let panelDark: [Color]
    /// Explicit stop locations (nil = evenly spaced). Aurora's mid-stop sits
    /// at 55% light / 58% dark per the token table — not the even 50% that
    /// `LinearGradient(colors:)` would give.
    public let panelLightStops: [CGFloat]?
    public let panelDarkStops: [CGFloat]?
    public let text: Duo
    public let sub: Duo
    public let ringTrack: Duo
    /// Lock-card ring fill. Aurora is solid white; Eclipse/Dawn are gradients.
    public let ringFillLight: [Color]
    public let ringFillDark: [Color]
    public let accent: Duo
    /// Hairline border (nil alpha = none in that appearance).
    public let border: Duo
    /// Dynamic Island ring gradient (the DI is always dark).
    public let diRing: [Color]

    // Shared tokens (all directions).
    public static let flameGradient = [Color(hex: 0xFFC24B), Color(hex: 0xFF6A3D)]
    public static let goldGradient = [Color(hex: 0xF6C468), Color(hex: 0xEE8C39)]
    public static let success = Color(hex: 0x30D158)
    public static let amber = Color(hex: 0xF2A93B)
    /// Error-state ring/bar fill override.
    public static let errorFillLight = Color(hex: 0xD9D6E6)
    public static let errorFillDark = Color.white.opacity(0.22)

    /// The direction being shipped.
    public static let current = ActivityTheme.aurora

    // MARK: - Aurora (vivid, mascot-forward) — the shipped direction

    public static let aurora = ActivityTheme(
        panelLight: [Color(hex: 0x6E5CF1), Color(hex: 0x9A54DE), Color(hex: 0xB44FCF)],
        panelDark: [Color(hex: 0x3C2F92), Color(hex: 0x5B2C8A), Color(hex: 0x732F86)],
        panelLightStops: [0, 0.55, 1],
        panelDarkStops: [0, 0.58, 1],
        text: Duo(light: .white, dark: .white),
        sub: Duo(light: .white.opacity(0.84), dark: .white.opacity(0.80)),
        ringTrack: Duo(light: .white.opacity(0.30), dark: .white.opacity(0.28)),
        ringFillLight: [.white],
        ringFillDark: [.white],
        accent: Duo(light: Color(hex: 0xFFE38A), dark: Color(hex: 0xFFDD73)),
        border: Duo(light: .clear, dark: .white.opacity(0.10)),
        diRing: [Color(hex: 0x9E8CFF), Color(hex: 0xC58CFF)]
    )

    // MARK: - Eclipse (focused, adaptive — ring is hero)

    public static let eclipse = ActivityTheme(
        panelLight: [Color.white],
        panelDark: [Color(hex: 0x191834), Color(hex: 0x131129)],
        panelLightStops: nil,
        panelDarkStops: nil,
        text: Duo(light: Color(hex: 0x171633), dark: Color(hex: 0xF4F3FF)),
        sub: Duo(light: Color(hex: 0x6E6B86), dark: Color(hex: 0xF4F3FF).opacity(0.60)),
        ringTrack: Duo(light: Color(hex: 0xEAE7F7), dark: .white.opacity(0.13)),
        ringFillLight: [Color(hex: 0x5A54E8), Color(hex: 0xA24BE0)],
        ringFillDark: [Color(hex: 0x8E86FF), Color(hex: 0xC08CFF)],
        accent: Duo(light: Color(hex: 0x5A54E8), dark: Color(hex: 0xABA3FF)),
        border: Duo(light: Color(hex: 0x171633).opacity(0.06), dark: .white.opacity(0.08)),
        diRing: [Color(hex: 0x6E8CFF), Color(hex: 0xA98CFF)]
    )

    // MARK: - Dawn (warm, minimal, type-led; linear bar instead of ring)

    public static let dawn = ActivityTheme(
        panelLight: [Color(hex: 0xFDFAF4), Color(hex: 0xF6EEE0)],
        panelDark: [Color(hex: 0x241B2B), Color(hex: 0x1A1420)],
        panelLightStops: nil,
        panelDarkStops: nil,
        text: Duo(light: Color(hex: 0x2C2340), dark: Color(hex: 0xFBF3E8)),
        sub: Duo(light: Color(hex: 0x8B7F70), dark: Color(hex: 0xFBF3E8).opacity(0.62)),
        ringTrack: Duo(light: Color(hex: 0xECDFCB), dark: .white.opacity(0.12)),
        ringFillLight: goldGradient,
        ringFillDark: goldGradient,
        accent: Duo(light: Color(hex: 0xD9791B), dark: Color(hex: 0xF6C468)),
        border: Duo(light: Color(hex: 0x2C2340).opacity(0.06), dark: Color(hex: 0xF6C468).opacity(0.14)),
        diRing: [Color(hex: 0xF6C468), Color(hex: 0xEE9B3C)]
    )

    // MARK: - Resolved helpers

    public func panel(_ scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark ? panelDark : panelLight
        let stops = scheme == .dark ? panelDarkStops : panelLightStops
        if let stops, stops.count == colors.count {
            return LinearGradient(
                stops: zip(colors, stops).map { Gradient.Stop(color: $0.0, location: $0.1) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public func ringFill(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark ? ringFillDark : ringFillLight,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var diRingGradient: LinearGradient {
        LinearGradient(colors: diRing, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var flame: LinearGradient {
        LinearGradient(colors: flameGradient, startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// Hex convenience mirroring DesignSystem's internal helper (kept local so
    /// the widget extension doesn't rely on non-public API).
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
