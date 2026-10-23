import Foundation

/// The honest-copy register (docs/mac-night-studio/SPEC.md §6, the same as
/// AppFeature's `NightCopyTests`): no line promises a notebook, a save, a
/// time, a hint or a verification the app doesn't have. Shared by the Mac's
/// reply copy tests and Lesson 1.1's interactive on both platforms.
enum HonestCopy {
    static let banned: [String] = [
        "notebook", "saved to", "\\bsaved\\b", "rest day", #"part \d+ of \d+"#, #"beat \d"#,
        #"\b\d+\s?min\b"#, #"\bminutes?\b"#, "previewable", "pinned", "give me a hint", "hint",
        "never reset", "verified",
    ]
}
