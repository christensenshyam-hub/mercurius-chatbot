#if DEBUG
import CoreText
import DesignSystem
import MarkdownUI
import SwiftUI

/// DEBUG-only: the same realistic tutor reply rendered in every reading-face
/// candidate, as REAL assistant bubbles, so the winner is picked from
/// simulator screenshots rather than imagination. Reached via the
/// `-ReplyFontGallery` launch argument (RootView).
///
/// Mechanism: MarkdownUI's keypath-less `.markdownTextStyle` merges into the
/// environment and propagates to descendants, so each section injects a
/// `FontFamily` from OUTSIDE the untouched production `MessageBubbleView`.
public struct ReplyFontGalleryView: View {
    public init() {}

    /// Realistic tutor reply: bold phrase, list, two short paragraphs, and a
    /// small code fence (to eyeball what code should look like per face).
    static let sampleReply = """
    A **hallucination** is when a model produces a confident-sounding \
    statement that isn't grounded in fact. It happens because the model \
    predicts likely words — it doesn't check a database of truths.

    Three quick tells:
    - A very specific claim with no source
    - Details that shift when you re-ask
    - Confidence that doesn't change with difficulty

    Try asking the same question twice, phrased differently. Does the \
    answer hold steady?

    ```
    prompt → tokens → next-token prediction
    ```
    """

    private struct Candidate: Identifiable {
        let id = UUID()
        let label: String
        let face: BrandReadingFace
        var airy: Bool = false
        var lessonToo: Bool = false
    }

    private static let candidates: [Candidate] = [
        .init(label: "SF (current)", face: .system(.default), lessonToo: true),
        .init(label: "SF Rounded", face: .system(.rounded), lessonToo: true),
        .init(label: "New York (serif)", face: .system(.serif), lessonToo: true),
        .init(label: "Lexend", face: .custom("Lexend"), lessonToo: true),
        .init(label: "Atkinson Hyperlegible", face: .custom("Atkinson Hyperlegible"), lessonToo: true),
        .init(label: "SF — airy spacing", face: .system(.default), airy: true),
        .init(label: "Lexend — airy spacing", face: .custom("Lexend"), airy: true),
    ]

    public var body: some View {
        ScrollView {
            galleryContent
        }
        .background(BrandColor.background.ignoresSafeArea())
        .onAppear {
            BrandFontRegistrar.registerReadingFonts()
            // `-ReplyFontGalleryExport`: render the FULL gallery (taller than
            // any screen) to PNGs in Documents so tooling can pull complete
            // light/dark/accessibility captures without scrolling.
            if ProcessInfo.processInfo.arguments.contains("-ReplyFontGalleryExport") {
                Self.exportCaptures()
            }
        }
    }

    private var galleryContent: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xl) {
            Text("Reply typography — candidates")
                .font(BrandFont.title)
                .padding(.top, BrandSpacing.lg)

            ForEach(Self.candidates) { candidate in
                section(for: candidate)
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.bottom, BrandSpacing.xxl)
    }

    @MainActor
    private static func exportCaptures() {
        #if os(iOS)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // One PNG per candidate per scheme — a single full-gallery bitmap is
        // ~9000pt tall and ImageRenderer fails silently at that size.
        let gallery = ReplyFontGalleryView()
        var written = 0
        for (idx, candidate) in candidates.enumerated() {
            for (suffix, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                let content = gallery.section(for: candidate)
                    .padding(BrandSpacing.lg)
                    .frame(width: 393)
                    .background(BrandColor.background)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let name = String(format: "font-%02d-%@-%@.png", idx, candidate.label
                    .lowercased().replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""), suffix)
                if let image = renderer.uiImage, let data = image.pngData() {
                    do {
                        try data.write(to: docs.appendingPathComponent(name))
                        written += 1
                    } catch {
                        print("ReplyFontGallery export write failed: \(name) — \(error)")
                    }
                } else {
                    print("ReplyFontGallery export render failed: \(name)")
                }
            }
        }
        print("ReplyFontGallery export complete: \(written) files → \(docs.path)")
        #endif
    }

    @ViewBuilder
    private func section(for candidate: Candidate) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.label)
                    .font(BrandFont.subheading)
                Text(availability(of: candidate.face))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }

            styled(candidate: candidate) {
                MessageBubbleView(
                    message: ChatMessage(role: .assistant, content: Self.sampleReply)
                )
            }

            if candidate.lessonToo {
                styled(candidate: candidate) {
                    MessageBubbleView(
                        message: ChatMessage(
                            role: .assistant,
                            content: "Nice thinking. [CHECK]In one sentence: why can't the model just look the answer up?[/CHECK]"
                        ),
                        lessonStyle: true
                    )
                }
            }
        }
    }

    /// Wrap a bubble with the candidate's family via the environment override
    /// (the production bubbles pin their own family now, so the old
    /// outside-in Markdown injection would lose to it). NOTE: since the airy
    /// paragraph treatment shipped as the production default, every candidate
    /// renders with it — the two "airy" rows remain as labels of the adopted
    /// look rather than a contrast.
    @ViewBuilder
    private func styled(candidate: Candidate, @ViewBuilder content: () -> some View) -> some View {
        content()
            .environment(\.readingFaceOverride, candidate.face)
    }

    /// Sanity string: proves custom families actually resolved (Font.custom
    /// falls back to SF silently on a wrong name — this label catches it).
    private func availability(of face: BrandReadingFace) -> String {
        switch face {
        case .system(let design):
            return "system design: \(String(describing: design))"
        case .custom(let name):
            // CoreText round-trip: an unresolved family comes back as a
            // substituted font whose family name won't match.
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            let resolved = (CTFontCopyFamilyName(font) as String) == name
            return resolved ? "custom family registered ✓" : "NOT RESOLVED — falls back to SF ✗"
        }
    }
}
#endif
