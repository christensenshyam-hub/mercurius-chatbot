import SwiftUI
import DesignSystem
import MarkdownUI

/// The ONE styling stack for tutor-reply markdown — used by both the lesson
/// bubble and the free-chat bubble so the two paths can't drift (they did
/// once: fenced code silently lost its mono face in one of them).
///
/// Covers every block the tutor actually emits: paragraphs (airy Lexend
/// rhythm), inline + fenced code (explicit mono — the variant-based fallback
/// is unreliable on custom families), bulleted/numbered lists (spaced rows
/// with accent markers — the "Duolingo rows" of the presentation redesign),
/// small headings (rounded ramp), and blockquotes (accent bar + tinted card).
struct ReplyMarkdownStyling: ViewModifier {
    let face: BrandReadingFace
    let bodySize: CGFloat
    /// Fenced-code background: `surfaceElevated` inside the white lesson card,
    /// plain `surface` on the flat free-chat bubble.
    let codeBlockBackground: Color

    func body(content: Content) -> some View {
        content
            .markdownTextStyle {
                FontFamily(face.markdownFamily)
                ForegroundColor(BrandColor.assistantBubbleText)
                FontSize(bodySize)
            }
            .markdownTextStyle(\.code) {
                FontFamily(.system(.monospaced))
                FontSize(.em(0.94))
            }
            // Airy reading rhythm (chosen with the Lexend face): looser line
            // spacing and a fuller gap between paragraphs.
            .markdownBlockStyle(\.paragraph) { config in
                config.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.30))
                    .markdownMargin(top: .zero, bottom: .em(1.2))
            }
            .markdownBlockStyle(\.codeBlock) { config in
                config.label
                    // Re-apply the mono text style this block override
                    // otherwise drops (fenced code used to render in the
                    // body face — pre-existing bug).
                    .markdownTextStyle {
                        FontFamily(.system(.monospaced))
                        FontSize(.em(0.94))
                    }
                    .padding(BrandSpacing.md)
                    .background(codeBlockBackground, in: RoundedRectangle(cornerRadius: BrandRadius.md))
            }
            // Lists as spaced rows: each item breathes like a mini-paragraph
            // instead of a packed text column.
            .markdownBlockStyle(\.listItem) { config in
                config.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.30))
                    .markdownMargin(top: .em(0.35), bottom: .em(0.35))
            }
            .markdownBlockStyle(\.bulletedListMarker) { _ in
                Circle()
                    .fill(BrandColor.accent)
                    .frame(width: 6, height: 6)
                    .frame(minWidth: 14, alignment: .trailing)
                    // Optically align the dot with the first text line across
                    // Dynamic Type sizes: half the line height minus half the
                    // dot, biased up a touch for the rounded face.
                    .padding(.top, bodySize * 0.42)
            }
            .markdownBlockStyle(\.numberedListMarker) { config in
                Text("\(config.itemNumber).")
                    .font(.system(size: bodySize * 0.9, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.accent)
                    .frame(minWidth: 14, alignment: .trailing)
            }
            // Small headings in the rounded (gamified) ramp — replies only
            // ever use ##/### level headings, and only rarely.
            .markdownBlockStyle(\.heading2) { config in
                config.label
                    .markdownTextStyle {
                        FontFamily(.system(.rounded))
                        FontWeight(.bold)
                        FontSize(.em(1.2))
                    }
                    .markdownMargin(top: .em(1.2), bottom: .em(0.5))
            }
            .markdownBlockStyle(\.heading3) { config in
                config.label
                    .markdownTextStyle {
                        FontFamily(.system(.rounded))
                        FontWeight(.bold)
                        FontSize(.em(1.05))
                    }
                    .markdownMargin(top: .em(1.0), bottom: .em(0.4))
            }
            .markdownBlockStyle(\.blockquote) { config in
                HStack(alignment: .top, spacing: BrandSpacing.sm) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(BrandColor.accent.opacity(0.55))
                        .frame(width: 3)
                    config.label
                        .markdownTextStyle { ForegroundColor(BrandColor.textSecondary) }
                        .padding(.vertical, BrandSpacing.xs)
                }
                .padding(.horizontal, BrandSpacing.sm)
                .background(
                    BrandColor.accent.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: BrandRadius.sm, style: .continuous)
                )
                .markdownMargin(top: .em(0.4), bottom: .em(1.0))
            }
    }
}

extension View {
    /// Apply the shared tutor-reply markdown styling. See `ReplyMarkdownStyling`.
    func replyMarkdownStyling(
        face: BrandReadingFace,
        bodySize: CGFloat,
        codeBlockBackground: Color
    ) -> some View {
        modifier(ReplyMarkdownStyling(face: face, bodySize: bodySize, codeBlockBackground: codeBlockBackground))
    }
}
