import SwiftUI
import DesignSystem

/// "Get your certificate": shown on the result of the check (or lesson)
/// that just completed a course — the moment the eighth unit is mastered.
/// The button opens the name sheet.
public struct CertificateReadyCard: View {
    private let kind: CertificateKind
    private let name: String
    private let compact: Bool
    private let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `compact` (iPhone): a small preview beside the words, as the Mac's
    /// card always has it, for the lesson-complete sheet, which also holds
    /// the headline, "Try this today" and the way on.
    public init(kind: CertificateKind, name: String, compact: Bool = false, onOpen: @escaping () -> Void) {
        self.kind = kind
        self.name = name
        self.compact = compact
        self.onOpen = onOpen
    }

    public var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 14) {
            NightEyebrow(CertificateReadyCopy.eyebrow, systemImage: "rosette")
            HStack(alignment: .center, spacing: 18) {
                CertificatePreview(kind: kind, name: name, date: nil, shadow: false)
                    .frame(width: 168)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(CertificateReadyCopy.headline(kind))
                        .nightFont(.title2)
                        .foregroundStyle(Night.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CertificateReadyCopy.detail(kind))
                        .nightFont(.callout)
                        .foregroundStyle(Night.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    NightSecondaryButton(CertificateReadyCopy.button, systemImage: "rosette", action: onOpen)
                        .help("Add your name, then print or save your certificate")
                        .padding(.top, 4)
                }
            }
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .accessibilityElement(children: .contain)
        #else
        VStack(spacing: BrandSpacing.md) {
            if compact {
                // Beside the words, or above them at the largest text sizes.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: BrandSpacing.md))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: BrandSpacing.md))
                layout {
                    preview.frame(width: 112)
                    words(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                preview.frame(maxWidth: 280)
                words(.center)
            }
            BrandButton(CertificateReadyCopy.button, style: .secondary, action: onOpen)
                .accessibilityHint("Add your name, then print or save your certificate")
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
            .strokeBorder(BrandColor.accent.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("certificate.ready")
        #endif
    }

    #if !os(macOS)
    private var preview: some View {
        CertificatePreview(kind: kind, name: name, date: nil)
            .accessibilityHidden(true)
    }

    private func words(_ alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .leading ? .leading : .center
        return VStack(alignment: alignment, spacing: BrandSpacing.xs) {
            Text(CertificateReadyCopy.headline(kind))
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(CertificateReadyCopy.detail(kind))
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif
}

public enum CertificateReadyCopy {
    public static let eyebrow = "Course complete"
    public static let button = "Get Your Certificate"

    public static func headline(_ kind: CertificateKind) -> String {
        switch kind {
        case .deepDive: return "You finished the AI Literacy Course"
        case .basics: return "You finished AI Basics"
        }
    }

    public static func detail(_ kind: CertificateKind) -> String {
        switch kind {
        case .deepDive: return "All eight unit checks passed. Your certificate is ready to print."
        case .basics: return "Every lesson done. Your certificate is ready to print."
        }
    }
}
