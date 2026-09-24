import Foundation
import PersistenceKit

/// The one path for turning reminders on — shared by the Progress hub's
/// switches, onboarding, and the Home opt-in — plus the one mapping from the
/// stores to `NotificationScheduler.refresh`, so every re-plan reads the same
/// state the same way.
public enum ReminderEnabler {
    public enum Kind: Hashable, Sendable {
        /// The Wednesday + Sunday nudges.
        case weekly
        /// The daily streak reminder.
        case daily
    }

    /// Ask for notification permission and, if granted, turn on both the
    /// weekly nudges and the daily streak reminder, then re-plan. Returns
    /// whether permission was granted; on denial the stored preferences are
    /// left as they were.
    @MainActor
    public static func enable(
        store: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore,
        nextLessonId: String? = nil
    ) async -> Bool {
        await enable([.weekly, .daily], store: store, scheduler: scheduler,
                     streakStore: streakStore, nextLessonId: nextLessonId)
    }

    /// Ask for notification permission and, if granted, turn on `kinds`,
    /// then re-plan. Returns whether permission was granted; on denial the
    /// stored preferences are left as they were.
    @MainActor
    public static func enable(
        _ kinds: Set<Kind>,
        store: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore?,
        nextLessonId: String? = nil
    ) async -> Bool {
        guard await scheduler.requestPermission() else { return false }
        if kinds.contains(.weekly) { store.weeklyEnabled = true }
        if kinds.contains(.daily) { store.enabled = true }
        refresh(store: store, scheduler: scheduler, streakStore: streakStore, nextLessonId: nextLessonId)
        return true
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
            chattedToday: streakStore?.confirmedToday ?? false,
            weeklyEnabled: store.weeklyEnabled,
            nextLessonId: nextLessonId
        )
    }
}
