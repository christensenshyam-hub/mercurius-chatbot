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
    /// The UNSCALED body size (17). MarkdownUI scales its theme's font size
    /// for Dynamic Type itself (`Markdown` wraps it in its own
    /// `@ScaledMetric(relativeTo: .body)`), so handing it an already-scaled
    /// size scaled the reply twice: ~1.35x too big at xxxLarge, ~1.65x at
    /// AX1 and ~3x at AX5, breaking words mid-word.
    let baseSize: CGFloat
    /// The Dynamic-Type-scaled body size, for the pieces drawn outside
    /// MarkdownUI's text (list markers), which use fixed-size fonts.
    let scaledSize: CGFloat
    /// Fenced-code background: `surfaceElevated` inside the white lesson card,
    /// plain `surface` on the flat free-chat bubble.
    let codeBlockBackground: Color

    func body(content: Content) -> some View {
        content
            // Replies are model output. A `![](url)` in one must never become
            // a request to an arbitrary host, and a link only leaves the app
            // when `ReplyLinkPolicy` allows it — everything else is dropped.
            .markdownImageProvider(NoNetworkImageProvider())
            .markdownInlineImageProvider(NoNetworkInlineImageProvider())
            .environment(\.openURL, OpenURLAction { url in
                ReplyLinkPolicy.allows(url) ? .systemAction : .discarded
            })
            .markdownTextStyle {
                FontFamily(face.markdownFamily)
                ForegroundColor(BrandColor.assistantBubbleText)
                FontSize(baseSize)
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
                    .padding(.top, scaledSize * 0.42)
            }
            .markdownBlockStyle(\.numberedListMarker) { config in
                Text("\(config.itemNumber).")
                    .font(.system(size: scaledSize * 0.9, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.accentText)
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

/// Block images (`![alt](url)` on their own line) render nothing.
private struct NoNetworkImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }
}

/// Inline images never load. MarkdownUI treats a throwing provider as "no
/// image for that source" and still renders the surrounding text.
private struct NoNetworkInlineImageProvider: InlineImageProvider {
    struct Blocked: Error {}

    func image(with url: URL, label: String) async throws -> Image {
        throw Blocked()
    }
}

extension View {
    /// Apply the shared tutor-reply markdown styling. See `ReplyMarkdownStyling`.
    /// - Parameters:
    ///   - baseSize: the unscaled body size; MarkdownUI applies Dynamic Type.
    ///   - scaledSize: the same size already scaled, for the list markers.
    func replyMarkdownStyling(
        face: BrandReadingFace,
        baseSize: CGFloat,
        scaledSize: CGFloat,
        codeBlockBackground: Color
    ) -> some View {
        modifier(ReplyMarkdownStyling(face: face, baseSize: baseSize, scaledSize: scaledSize,
                                      codeBlockBackground: codeBlockBackground))
    }
}

#if os(macOS)
/// Night Studio's reading text on the Mac (SPEC.md §5.3.3): Merc's reply as
/// type on the page, not in a bubble. Lexend 15 on a line spacing of 5, in
/// `ink`; links in `accentText`; Lexend SemiBold for headings and bold (the
/// bundle has no bold or black Lexend); lists with lumen markers; quotes on a
/// lumen bar; code in SF Mono on `surfaceRaised`; a thematic break as a
/// hairline. The same no-network image providers and link policy as every
/// reply.
struct NightReplyMarkdownStyling: ViewModifier {
    /// The text colour: `ink`, or `ink2` for an example's own text.
    var color: Color = Night.ink

    func body(content: Content) -> some View {
        let face = BrandFont.readingFace.markdownFamily
        return content
            .markdownImageProvider(NoNetworkImageProvider())
            .markdownInlineImageProvider(NoNetworkInlineImageProvider())
            .environment(\.openURL, OpenURLAction { url in
                ReplyLinkPolicy.allows(url) ? .systemAction : .discarded
            })
            .markdownTextStyle {
                FontFamily(face)
                ForegroundColor(color)
                FontSize(NightType.Role.body.size)
            }
            .markdownTextStyle(\.strong) { FontWeight(.semibold) }
            .markdownTextStyle(\.link) { ForegroundColor(Night.accentText) }
            .markdownTextStyle(\.code) {
                FontFamily(.system(.monospaced))
                FontSize(.em(0.93))
                BackgroundColor(Night.surfaceRaised)
            }
            .markdownBlockStyle(\.paragraph) { config in
                config.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.33))
                    .markdownMargin(top: .zero, bottom: .em(0.95))
            }
            .markdownBlockStyle(\.codeBlock) { config in
                config.label
                    .markdownTextStyle {
                        FontFamily(.system(.monospaced))
                        FontSize(.em(0.93))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Night.surfaceRaised, in: RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
                    .markdownMargin(top: .zero, bottom: .em(0.95))
            }
            .markdownBlockStyle(\.listItem) { config in
                config.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.33))
                    .markdownMargin(top: .em(0.3), bottom: .em(0.3))
            }
            .markdownBlockStyle(\.bulletedListMarker) { _ in
                Circle()
                    .fill(Night.accent)
                    .frame(width: 6, height: 6)
                    .frame(minWidth: 16, alignment: .trailing)
                    .padding(.top, 8)
            }
            .markdownBlockStyle(\.numberedListMarker) { config in
                Text("\(config.itemNumber).")
                    .font(NightType.lexend(14, semibold: true))
                    .monospacedDigit()
                    .foregroundStyle(Night.accentText)
                    .frame(minWidth: 18, alignment: .trailing)
            }
            .markdownBlockStyle(\.heading2) { config in
                config.label
                    .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.2)) }
                    .markdownMargin(top: .em(1.1), bottom: .em(0.5))
            }
            .markdownBlockStyle(\.heading3) { config in
                config.label
                    .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.07)) }
                    .markdownMargin(top: .em(1.0), bottom: .em(0.4))
            }
            .markdownBlockStyle(\.blockquote) { config in
                HStack(alignment: .top, spacing: 12) {
                    Capsule()
                        .fill(Night.lumen.opacity(0.6))
                        .frame(width: 3)
                    config.label
                        .markdownTextStyle { ForegroundColor(Night.ink2) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: .em(0.3), bottom: .em(0.95))
            }
            .markdownBlockStyle(\.thematicBreak) {
                Rectangle()
                    .fill(Night.hairline)
                    .frame(height: 1)
                    .markdownMargin(top: .em(0.6), bottom: .em(1.4))
            }
    }
}

extension View {
    /// Night's reading text for a reply's Markdown (Mac).
    func nightReplyMarkdown(color: Color = Night.ink) -> some View {
        modifier(NightReplyMarkdownStyling(color: color))
    }
}
#endif
