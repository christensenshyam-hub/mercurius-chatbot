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
    /// Standby gamification (quiet progress). Optional + defaults to nil so
    /// existing callers are unaffected; the Progress card renders only when a
    /// store is passed AND it reports `enabled` (server flag on). Off by default.
    private let gamificationStore: GamificationStore?
    private let onDone: () -> Void

    public init(
        streakStore: StreakStore,
        achievementStore: AchievementStore,
        reminderStore: ReminderStore,
        scheduler: NotificationScheduler,
        leaderboard: LeaderboardViewModel,
        gamificationStore: GamificationStore? = nil,
        onDone: @escaping () -> Void
    ) {
        self.streakStore = streakStore
        self.achievementStore = achievementStore
        self.reminderStore = reminderStore
        self.scheduler = scheduler
        _leaderboard = State(initialValue: leaderboard)
        self.gamificationStore = gamificationStore
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.xl) {
                    // Streak hero leads the profile.
                    StreakHeroView(streakStore: streakStore)

                    // XP / level surface — present only when explicitly enabled
                    // (client + server flags). Off by default, so the profile
                    // shows streak + achievements + leaderboard with no holes.
                    if let gamificationStore, gamificationStore.enabled {
                        section("Your XP") {
                            ProgressCard(store: gamificationStore)
                            RecentCreditsView(store: gamificationStore)
                        }
                    }

                    // These three already render their own section header, so
                    // they're shown bare (wrapping them in section() would double
                    // the title).
                    AchievementsGalleryView(store: achievementStore)
                    LeaderboardListView(model: leaderboard)
                    DailyReminderSection(store: reminderStore, scheduler: scheduler)
                }
                .padding(BrandSpacing.lg)
            }
            .background(BrandColor.background.ignoresSafeArea())
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .font(BrandFont.roundedBodyEmphasized)
                        .foregroundStyle(BrandColor.accent)
                }
            }
        }
    }

    /// A titled group — a rounded section header above its content, the
    /// Duolingo-profile rhythm. Reuses the existing sub-views unchanged.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text(title)
                .font(BrandFont.roundedHeadline)
                .foregroundStyle(BrandColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
