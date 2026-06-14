import Foundation

/// A single earnable badge. Purely descriptive metadata — whether it's *earned*
/// lives in `AchievementStore`. `symbol` is an SF Symbol name.
public struct Achievement: Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String

    public init(id: String, title: String, detail: String, symbol: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

/// The fixed catalog of achievements + the stable string ids used to award them.
/// Ids are referenced from the award call sites (ChatViewModel, QuizViewModel,
/// CurriculumFeature) so there's a single source of truth and no stringly-typed
/// drift. Mirrors (a subset of) the web widget's badge set.
public enum AchievementCatalog {
    public static let firstConversation = "first_conversation"
    public static let criticalThinker = "critical_thinker"
    public static let debater = "debater"
    public static let quizMaster = "quiz_master"
    public static let explorer = "explorer"
    public static let deepDiver = "deep_diver"
    public static let reportCard = "report_card"
    public static let streak3 = "streak_3"
    public static let streak7 = "streak_7"
    public static let streak14 = "streak_14"

    /// Display order = catalog order.
    public static let all: [Achievement] = [
        Achievement(id: firstConversation, title: "First Steps",
                    detail: "Started your first conversation with Mercurius.", symbol: "bubble.left.fill"),
        Achievement(id: criticalThinker, title: "Critical Thinker",
                    detail: "Unlocked Direct Mode by showing real understanding.", symbol: "lock.open.fill"),
        Achievement(id: debater, title: "Debater",
                    detail: "Stepped into Debate Mode and argued your side.", symbol: "person.2.fill"),
        Achievement(id: quizMaster, title: "Quiz Master",
                    detail: "Scored 3 or more on a comprehension quiz.", symbol: "checkmark.seal.fill"),
        Achievement(id: explorer, title: "Explorer",
                    detail: "Started a structured curriculum lesson.", symbol: "map.fill"),
        Achievement(id: deepDiver, title: "Deep Diver",
                    detail: "Sent 20 messages across your conversations.", symbol: "arrow.down.circle.fill"),
        Achievement(id: reportCard, title: "Self-Aware",
                    detail: "Generated a session report card.", symbol: "doc.text.magnifyingglass"),
        Achievement(id: streak3, title: "On a Roll",
                    detail: "Reached a 3-day learning streak.", symbol: "flame.fill"),
        Achievement(id: streak7, title: "Weekly Scholar",
                    detail: "Reached a 7-day learning streak.", symbol: "flame.fill"),
        Achievement(id: streak14, title: "Committed",
                    detail: "Reached a 14-day learning streak.", symbol: "flame.fill"),
    ]

    /// Look up the metadata for an id (nil if unknown).
    public static func achievement(id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    /// The streak-milestone ids earned at or below `streak`. Awarding is
    /// idempotent (the store de-dupes), so it's safe to call every chat.
    public static func streakMilestones(for streak: Int) -> [String] {
        var ids: [String] = []
        if streak >= 3 { ids.append(streak3) }
        if streak >= 7 { ids.append(streak7) }
        if streak >= 14 { ids.append(streak14) }
        return ids
    }
}
