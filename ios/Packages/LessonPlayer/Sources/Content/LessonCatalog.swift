import Foundation

/// Every lesson the player can run, at every content version still bundled.
/// Keep an old version here while any learner may have an unfinished attempt
/// on it (attempts are pinned to their version); see HANDOFF.md.
public enum LessonCatalog {
    public static let all: [LessonContent] = [
        u1_l3_v1,
        b1_l1_v1,
    ]

    public static let library = LessonLibrary(all)
}
