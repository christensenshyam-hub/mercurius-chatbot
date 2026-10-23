// A tiny, self-contained model of how Night Studio's tokens and chrome are
// meant to reach the app's code, written to the rules CI's toolchain
// (Xcode 16.2 / Swift 6.0.3 / the macOS 15 SDK) imposes. Not part of any
// target: `run.sh` type-checks it with the local compiler for macOS 14
// (arm64 and x86_64) and the iOS 17 simulator, with and without the forced
// material fallback. See ../ARCHITECTURE.md §5.
//
// The rules it shows:
// 1. Tokens are raw sRGB pairs (light, dark, and both again for Increase
//    Contrast) in plain data, so tests read them on any host.
// 2. A SwiftUI `Color` is built from a pair with the platform's dynamic
//    colour (NSColor on the Mac, UIColor on iOS), never `#if DEBUG`.
// 3. Liquid Glass is behind `#if compiler(>=6.2)` AND
//    `if #available(macOS 26.0, iOS 26.0, *)`, with a material fallback in
//    both other places. A compiler older than 6.2 does not parse the inner
//    block at all, so iOS 26 / macOS 26 symbols never reach Swift 6.0.3.
//    `NIGHT_FORCE_MATERIAL` is nested inside, not `&&`-ed onto the compiler
//    check, so the old compiler's skip rule stays simple.
// 4. Reduce Transparency wins over both: an opaque lit surface.
// 5. Trig on CGFloat goes through Double explicitly (Swift 6.0 rejected a
//    mixed `sin` in a1754ef that 6.3 accepts).
// 6. No trailing comma in an argument list (Swift 6.1+ syntax).

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum NightProbePalette {
    struct Pair: Equatable, Sendable {
        let light: UInt32
        let dark: UInt32
        let lightHighContrast: UInt32
        let darkHighContrast: UInt32
    }

    static let surface = Pair(light: 0xFFFFFF, dark: 0x121641,
                              lightHighContrast: 0xFFFFFF, darkHighContrast: 0x0A0C2A)
    static let ink3 = Pair(light: 0x5A6286, dark: 0x8E96C4,
                           lightHighContrast: 0x3A4166, darkHighContrast: 0xC4C9EE)

    /// DEBUG launch override, because the harness must not flip the Mac's
    /// own Increase Contrast setting (a system setting).
    static let forcesIncreasedContrast: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-NightIncreaseContrast")
        #else
        return false
        #endif
    }()

    static func pick(_ pair: Pair, dark: Bool, highContrast: Bool) -> UInt32 {
        switch (dark, highContrast) {
        case (false, false): return pair.light
        case (true, false): return pair.dark
        case (false, true): return pair.lightHighContrast
        case (true, true): return pair.darkHighContrast
        }
    }

    static func color(_ pair: Pair) -> Color {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua,
                                                    .accessibilityHighContrastAqua,
                                                    .accessibilityHighContrastDarkAqua])
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            // The system flag too: a window forced to .darkAqua by
            // `.preferredColorScheme` may not carry the high-contrast name.
            let highContrast = forcesIncreasedContrast
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                || match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
            return nsColor(pick(pair, dark: dark, highContrast: highContrast))
        })
        #elseif canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let highContrast = forcesIncreasedContrast || traits.accessibilityContrast == .high
            return uiColor(pick(pair, dark: dark, highContrast: highContrast))
        })
        #else
        return Color(red: 1, green: 1, blue: 1)
        #endif
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
    #endif

    #if canImport(UIKit)
    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
    #endif
}

extension View {
    /// Floating chrome (the composer, the lesson's check tray): Liquid Glass
    /// on macOS 26 / iOS 26 when built by Swift 6.2+; a thin material on
    /// macOS 14–15, iOS 17–25 and anything CI's Xcode 16.2 builds; an opaque
    /// lit surface under Reduce Transparency.
    @ViewBuilder
    func nightProbeChrome<S: Shape>(in shape: S, reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            self.background(NightProbePalette.color(NightProbePalette.surface), in: shape)
        } else {
            #if compiler(>=6.2)
            #if NIGHT_FORCE_MATERIAL
            self.background(.ultraThinMaterial, in: shape)
            #else
            if #available(macOS 26.0, iOS 26.0, *) {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.background(.ultraThinMaterial, in: shape)
            }
            #endif
            #else
            self.background(.ultraThinMaterial, in: shape)
            #endif
        }
    }
}

struct NightProbeComposer: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let angle: CGFloat

    var body: some View {
        Text("Your answer…")
            .foregroundStyle(NightProbePalette.color(NightProbePalette.ink3))
            .padding(12)
            // Rule 5: the CGFloat goes through Double for `sin`, and back.
            .offset(y: CGFloat(sin(Double(angle))) * 2)
            .nightProbeChrome(in: Capsule(), reduceTransparency: reduceTransparency)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.6 : 0.1), lineWidth: 1))
            .animation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.28), value: angle)
            .accessibilityLabel("Your answer")
    }
}
