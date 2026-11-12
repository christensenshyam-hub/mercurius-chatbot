import Foundation

/// Inline Markdown (emphasis, code, links) for the lesson cards' `Text`.
///
/// `Text(_: String)` shows a string verbatim, so a key idea the model wrote as
/// "**Hallucination** is…" printed its asterisks. The cards render through
/// this instead: inline syntax only, whitespace kept, and the text unchanged
/// if it doesn't parse. The same rules as the Mac's `nightInlineMarkdown`.
enum InlineMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// The words without Markdown, for VoiceOver (so it doesn't read "star star").
    static func spoken(_ text: String) -> String {
        String(attributed(text).characters)
    }
}
