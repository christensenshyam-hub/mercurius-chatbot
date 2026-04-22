import SwiftUI

/// The Mercurius logo. Two styles:
/// - `.full`: the hero logo with the "Mercurius AI / AI Literacy Tutor"
///   text, used on splash and empty states.
/// - `.mark`: just the crown/helmet illustration in a circle, sized for
///   headers and small surfaces.
///
/// The mark is a SwiftUI composition (no image asset) so it scales
/// perfectly at any size. The full logo is backed by the `LogoHero`
/// image in the app target's asset catalog; the package checks at
/// runtime whether it's available and falls back cleanly if not.
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

// MARK: - Full logo (uses image asset)

private struct FullLogoView: View {
    let size: CGFloat

    var body: some View {
        // The app's Assets.xcassets contains `LogoHero`. We look it up
        // by name; if missing, fall back to the mark so the UI always
        // renders something.
        if let uiImage = platformImage(named: "LogoHero") {
            Image(sharedImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            MarkView(size: size * 0.6)
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
