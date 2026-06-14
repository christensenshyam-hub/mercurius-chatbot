import SwiftUI
import DesignSystem
import PersistenceKit
import NetworkingKit

/// The engagement hub — streak, achievements, and leaderboard in one sheet.
/// Presented from the chat header's streak chip. (Named `ProgressHubView` to
/// avoid clashing with SwiftUI's built-in `ProgressView`.)
public struct ProgressHubView: View {
    private let streakStore: StreakStore
    private let achievementStore: AchievementStore
    private let reminderStore: ReminderStore
    private let scheduler: NotificationScheduler
    @State private var leaderboard: LeaderboardViewModel
    private let onDone: () -> Void

    public init(
        streakStore: StreakStore,
        achievementStore: AchievementStore,
        reminderStore: ReminderStore,
        scheduler: NotificationScheduler,
        leaderboard: LeaderboardViewModel,
        onDone: @escaping () -> Void
    ) {
        self.streakStore = streakStore
        self.achievementStore = achievementStore
        self.reminderStore = reminderStore
        self.scheduler = scheduler
        _leaderboard = State(initialValue: leaderboard)
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    StreakHeroView(streakStore: streakStore)
                    AchievementsGalleryView(store: achievementStore)
                    DailyReminderSection(store: reminderStore, scheduler: scheduler)
                    LeaderboardListView(model: leaderboard)
                }
                .padding(BrandSpacing.lg)
            }
            .background(BrandColor.background.ignoresSafeArea())
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .foregroundStyle(BrandColor.accent)
                }
            }
        }
    }
}
