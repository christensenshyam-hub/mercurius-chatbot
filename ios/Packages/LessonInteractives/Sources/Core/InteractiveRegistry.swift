import Foundation

/// Which lesson holds which card: one row per card, at most one card per
/// lesson, none in a Review lesson (`RegistryTests`, and AppFeature's
/// `InteractiveCurriculumTests` checks every lesson id against
/// `Curriculum.swift`). The table is BUILD_PLAN.md §1.2's.
///
/// A card ships dark (`enabled: false`) until its teacher review is signed
/// off in `docs/interactives/<slug>/CONTENT.md`; flipping it is the card's
/// last commit. DEBUG's `-Interactive <slug>` shows a dark card in its
/// lesson anyway (`InteractiveLaunchOptions`).
public enum InteractiveRegistry {
    public static let all: [InteractiveSpec] = [
        // Lesson 1.1's card, shipped before the framework: its views stay in
        // ChatFeature (Tokenizer/, Mac/NightTokenizerCard.swift).
        InteractiveSpec(id: .tokenizer, lessonID: "u1_l1", anchor: .firstExample, wave: 0, enabled: true),

        // Wave 1 (SLATE.md ★): the first teach reply, no guide change.
        InteractiveSpec(id: .citationThatWasnt, lessonID: "u1_l3", anchor: .firstExample, wave: 1, enabled: false),

        InteractiveSpec(id: .deleteTheGenderBox, lessonID: "u3_l1", anchor: .firstExample, wave: 1, enabled: false),

        InteractiveSpec(id: .patchTheReward, lessonID: "u5_l1", anchor: .firstExample, wave: 1, enabled: false),

        InteractiveSpec(id: .doubtDial, lessonID: "u6_l4", anchor: .firstExample, wave: 1, enabled: false),

        // Spoilers: the slate's three, refined (`PageWithASecretContent.spoilers`).
        InteractiveSpec(id: .pageWithASecret, lessonID: "u8_l1", anchor: .firstExample,
                        spoilers: PageWithASecretContent.spoilers, wave: 1, enabled: false),

        // Wave 2: after the guide-line batch (D2) and the placement decision (D1).
        InteractiveSpec(id: .twoTestsOneLine, lessonID: "u2_l2", anchor: .teachReply(2),
                        spoilers: ["Kleinberg", "Chouldechova", "impossib"], wave: 2, enabled: false),

        InteractiveSpec(id: .whosInTheTest, lessonID: "u2_l3", anchor: .firstExample, wave: 2, enabled: false),

        InteractiveSpec(id: .wardOf1000, lessonID: "u3_l2", anchor: .firstReplyMentioning(["sepsis"], fallback: 2),
                        spoilers: ["88%", "12%", "1 in 8"], wave: 2, enabled: false),

        InteractiveSpec(id: .readMyMind, lessonID: "u4_l1", anchor: .firstExample, wave: 2, enabled: false),

        InteractiveSpec(id: .grownFromStatic, lessonID: "u6_l1", anchor: .firstExample, wave: 2, enabled: false),

        InteractiveSpec(id: .predictTheExam, lessonID: "u7_l1", anchor: .firstExample,
                        spoilers: ["17%", "48%", "Bastani"], wave: 2, enabled: false),
    ]

    /// The Review lessons: no card goes in one (map rule 1).
    public static let reviewLessons: Set<String> = [
        "u1_l4", "u2_l4", "u3_l4", "u4_l4", "u5_l4", "u6_l5", "u7_l5", "u8_l5",
    ]

    /// A card's row (every id has one; `RegistryTests`).
    public static func spec(for id: InteractiveID) -> InteractiveSpec? {
        all.first { $0.id == id }
    }

    /// The card lesson `lessonID` shows: its enabled card, or in DEBUG the
    /// card `-Interactive <slug>` forces on, dark or not. Nil for free chat
    /// (no lesson) and lessons without one.
    public static func spec(forLesson lessonID: String?) -> InteractiveSpec? {
        spec(forLesson: lessonID, in: all, forcing: InteractiveLaunchOptions.current.card)
    }

    /// `spec(forLesson:)` over any table, with `forced` shown even when dark
    /// (pure, for the tests).
    public static func spec(forLesson lessonID: String?, in specs: [InteractiveSpec],
                            forcing forced: InteractiveID?) -> InteractiveSpec? {
        guard let lessonID, !lessonID.isEmpty,
              let spec = specs.first(where: { $0.lessonID == lessonID }) else { return nil }
        if spec.enabled { return spec }
        return spec.id == forced ? spec.enabled(true) : nil
    }
}
