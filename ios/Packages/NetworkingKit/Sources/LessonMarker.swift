import Foundation

/// Bracketed control tokens a lesson reply can carry on its final line.
///
/// Two backends exist in the wild:
/// - The **current** server strips `[LESSON_COMPLETE]` itself and signals a pass
///   via the `lessonComplete` flag on the `complete` event.
/// - The **legacy / production** server emits `[TEST_PASSED]` / `[TEST_FAILED]`
///   *inline* in the reply text and sends no flag.
///
/// So the client defends on both fronts: it (a) removes these tokens from
/// anything it shows or persists — a stray `[TEST_PASSED]` must never surface as
/// transcript text — and (b) treats a *pass* token as a completion fallback, so
/// a lesson still advances even when the server omits the flag.
public enum LessonMarker {
    /// Pass tokens — their presence in a lesson reply means "lesson complete".
    /// `[TEST_FAILED]` is deliberately absent: a failed attempt must not advance.
    static let passTokens = ["[LESSON_COMPLETE]", "[TEST_PASSED]"]

    /// Every control token to scrub from displayed / persisted text.
    static let allTokens = ["[LESSON_COMPLETE]", "[TEST_PASSED]", "[TEST_FAILED]"]

    /// True if a pass token appears **on a line by itself** — matching the
    /// server's contract that the marker is emitted on its own line (see
    /// lib/lessonOutcome.js's end-anchoring). A token merely quoted mid-sentence
    /// (a lesson explaining the markers, or echoing a student who typed one) is
    /// NOT a completion signal, so it can't silently advance the lesson. Used as
    /// a client-side fallback when the server omits the `lessonComplete` flag.
    public static func indicatesCompletion(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            passTokens.contains(line.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Removes every control token from `text` **without** trimming — for the
    /// in-flight streaming path, where trailing whitespace between deltas is
    /// still meaningful.
    public static func removingMarkers(_ text: String) -> String {
        var out = text
        for token in allTokens { out = out.replacingOccurrences(of: token, with: "") }
        return out
    }

    /// Removes every control token and trims surrounding whitespace — for the
    /// final, persisted reply. May return empty if the reply was *only* a
    /// marker; callers substitute a short confirmation rather than ever showing
    /// the raw token or a blank.
    public static func cleaned(_ text: String) -> String {
        removingMarkers(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
