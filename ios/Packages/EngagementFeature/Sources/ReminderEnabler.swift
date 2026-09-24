import Foundation
import PersistenceKit

/// The one path for turning a reminder on — shared by the Progress hub's
/// switches, onboarding, and the Home opt-in — the one path for turning them
/// all off, plus the one mapping from the stores to
/// `NotificationScheduler.refresh`, so every re-plan reads the same state the
/// same way.
public enum ReminderEnabler {
    public enum Kind: Hashable, Sendable {
        /// The Wednesday + Sunday nudges.
        case weekly
        /// The daily streak reminder.
        case daily
    }

    /// Ask for notification permission and, if granted, turn on `kind` — only
    /// the reminder the student chose — then re-plan. Returns whether
    /// permission was granted; on denial the stored preferences are left as
    /// they were.
    @MainActor
    public static func enable(
        _ kind: Kind,
        store: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore?,
        nextLessonId: String? = nil
    ) async -> Bool {
        guard await scheduler.requestPermission() else { return false }
        switch kind {
        case .weekly: store.weeklyEnabled = true
        case .daily: store.enabled = true
        }
        refresh(store: store, scheduler: scheduler, streakStore: streakStore, nextLessonId: nextLessonId)
        return true
    }

    /// Turn every reminder off and cancel everything pending, daily and
    /// weekly. Both preferences are stored as false rather than removed, so no
    /// later re-plan can read them back as anything else.
    @MainActor
    public static func disableAll(store: ReminderStore, scheduler: NotificationScheduler) {
        store.enabled = false
        store.weeklyEnabled = false
        scheduler.cancel()
    }

    /// Re-plan every reminder from the stored preferences. The daily reminder
    /// only defends a streak the server confirmed recently (`isCurrentFresh`);
    /// a stale cached number is treated as no streak.
    @MainActor
    public static func refresh(
        store: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore?,
        nextLessonId: String? = nil
    ) {
        let fresh = streakStore?.isCurrentFresh == true
        scheduler.refresh(
            enabled: store.enabled,
            hour: store.hour,
            minute: store.minute,
            streak: fresh ? streakStore?.current : nil,
            streakDay: fresh ? streakStore?.lastConfirmedDay : nil,
            chattedToday: streakStore?.confirmedToday ?? false,
            weeklyEnabled: store.weeklyEnabled,
            nextLessonId: nextLessonId
        )
    }
}
