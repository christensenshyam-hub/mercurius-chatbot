import SwiftUI

/// The Mercurius logo. Two styles:
/// - `.full`: the hero logo with the "Mercurius AI / AI LITERACY TUTOR"
///   wordmark, used on splash and empty states.
/// - `.mark`: just the crown/helmet illustration in a circle, sized for
///   headers and small surfaces.
///
/// Why `.full` is a composite (icon image + SwiftUI wordmark) instead
/// of a single PNG: the wordmark needs to read in both light and dark
/// modes. A baked-in dark navy wordmark sits on top of `BrandColor.background`
/// fine in light mode but vanishes in dark mode. Splitting into an icon
/// image plus `Text` styled with adaptive `BrandColor` lets the wordmark
/// recolor automatically — no baked wordmark PNG to maintain.
///
/// The icon is the winged-Mercury emblem on a TRANSPARENT background (no
/// backing plate) — the same artwork in both modes, with only the figure
/// recolored so it reads on either background: `LogoIcon` (light mode) has a
/// navy figure; `LogoIconDark` (dark mode) has a white figure. The gradient
/// wing/hat/ring/sparkle are shared. `FullLogoView` selects between them via
/// `colorScheme`; the layout geometry is identical in both modes.
///
/// The `.mark` style is a pure SwiftUI composition (no asset) so it
/// scales perfectly at any size.
public struct BrandLogo: View {
    public enum Style {
        case full
        case mark
    }

    public let style: Style
    public let size: CGFloat

    public init(style: Style = .full, size: CGFloat = 180) {
        self.style = style
        self.size = size
    }

    public var body: some View {
        switch style {
        case .full:
            FullLogoView(size: size)
        case .mark:
            MarkView(size: size)
        }
    }
}

// MARK: - Full logo (icon image + adaptive wordmark)

/// `size` is the bounding box width — the icon scales to that width and
/// the wordmark sits below in fixed-scale typography (so it respects
/// Dynamic Type). The composition is a hair taller than `size` because
/// the icon is < 1:1 aspect after cropping, plus the two text rows.
private struct FullLogoView: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: max(8, size * 0.05)) {
            iconLayer
                .frame(width: iconWidth, height: iconWidth * iconAspect)

            wordmark
            tutorLabel
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mercurius AI — AI literacy tutor")
    }

    private var isDark: Bool { colorScheme == .dark }

    /// The two emblems are normalized onto an identical 980×980 transparent
    /// square (same emblem height, centered) so the logo never changes size or
    /// position between modes — hence a 1:1 aspect.
    private var iconAspect: CGFloat { 1.0 }

    /// The emblem floats (no backing plate), so it fills the bounding width.
    private var iconWidth: CGFloat { size }

    /// The winged-Mercury emblem on a TRANSPARENT background — the same artwork,
    /// with only the figure recolored per mode so it reads on either background:
    /// `LogoIcon` (light mode) has a navy figure; `LogoIconDark` (dark mode) has
    /// a white figure. The gradient wing/hat/ring/sparkle are shared. `LogoHero`
    /// and the pure-SwiftUI `MarkView` remain fallbacks for SPM/preview contexts.
    @ViewBuilder
    private var iconLayer: some View {
        if let uiImage = (isDark ? platformImage(named: "LogoIconDark") : nil)
            ?? platformImage(named: "LogoIcon")
            ?? platformImage(named: "LogoHero") {
            Image(sharedImage: uiImage)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            MarkView(size: size * 0.5)
                .accessibilityHidden(true)
        }
    }

    /// "Mercurius AI" — serif, two-tone. "AI" in the brand accent so
    /// the wordmark keeps its distinctive split coloring without
    /// needing a baked-in PNG.
    private var wordmark: some View {
        HStack(spacing: 6) {
            Text("Mercurius")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(BrandColor.text)
            Text("AI")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColor.accent, BrandColor.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// "AI LITERACY TUTOR" with the original underline ornaments,
    /// using `BrandColor.textSecondary` so it adapts to light/dark.
    private var tutorLabel: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(BrandColor.accent.opacity(0.55))
                .frame(width: 24, height: 1)

            Text("AI LITERACY TUTOR")
                .font(.system(.caption2, design: .default, weight: .medium))
                .tracking(2)
                .foregroundStyle(BrandColor.textSecondary)

            Capsule()
                .fill(BrandColor.accent.opacity(0.55))
                .frame(width: 24, height: 1)
        }
    }
}

// MARK: - Mark (pure SwiftUI)

private struct MarkView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Gradient ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [BrandColor.accent, BrandColor.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.5, size * 0.04)
                )
                .frame(width: size, height: size)

            // Monogram inside
            Text("MⅠ")
                .font(.system(size: size * 0.34, weight: .bold, design: .default))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BrandColor.accent, BrandColor.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Cross-platform image lookup

#if canImport(UIKit)
import UIKit

private func platformImage(named name: String) -> UIImage? {
    UIImage(named: name)
}

private extension Image {
    init(sharedImage: UIImage) {
        self = Image(uiImage: sharedImage)
    }
}
#else
// macOS test host — image assets don't exist. Return nil so callers
// fall back to the SwiftUI mark.
private func platformImage(named name: String) -> Any? { nil }

private extension Image {
    init(sharedImage: Any) {
        self = Image(systemName: "circle")
    }
}
#endif
