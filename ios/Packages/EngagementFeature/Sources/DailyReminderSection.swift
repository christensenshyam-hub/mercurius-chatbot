import SwiftUI
import DesignSystem
import PersistenceKit

/// Daily-reminder controls for the Progress hub: a toggle (which requests
/// notification permission on enable) + a time picker. Self-contained in
/// EngagementFeature so it doesn't pull SettingsFeature into the dependency.
public struct DailyReminderSection: View {
    private let store: ReminderStore
    private let scheduler: NotificationScheduler
    /// Feeds the streak-defense layer: when the streak is fresh and unsaved
    /// today, the next reminder becomes "your N-day streak is on the line".
    /// Optional so previews/tests without a streak store still work.
    private let streakStore: StreakStore?
    @State private var permissionDenied = false
    /// Enable is asynchronous (it awaits the notification-permission request,
    /// which can sit under the system alert for as long as the user deliberates).
    /// The Toggle reads this so the switch stays ON while the request is in
    /// flight instead of visibly snapping back to OFF — which reads as "the tap
    /// didn't take" and invites re-taps.
    @State private var pendingOn = false

    public init(store: ReminderStore, scheduler: NotificationScheduler,
                streakStore: StreakStore? = nil) {
        self.store = store
        self.scheduler = scheduler
        self.streakStore = streakStore
    }

    /// Re-plan the reminder window (rotating Merc copy + streak defense).
    private func refreshSchedule() {
        scheduler.refresh(
            enabled: store.enabled,
            hour: store.hour,
            minute: store.minute,
            streak: (streakStore?.isCurrentFresh == true) ? streakStore?.current : nil,
            chattedToday: streakStore?.confirmedToday ?? false
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Daily reminder")
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)

            Toggle(isOn: Binding(get: { store.enabled || pendingOn }, set: { setEnabled($0) })) {
                Text("Remind me to learn each day")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
            }
            .tint(BrandColor.accent)

            if store.enabled {
                DatePicker(
                    "Time",
                    selection: Binding(get: { timeAsDate() }, set: { setTime($0) }),
                    displayedComponents: .hourAndMinute
                )
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
            }

            if permissionDenied {
                Text("Notifications are off for Mercurius. Turn them on in the iOS Settings app to get reminders.")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .padding(BrandSpacing.lg)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
    }

    private func setEnabled(_ on: Bool) {
        guard on else {
            pendingOn = false
            store.enabled = false
            permissionDenied = false
            scheduler.cancel()
            return
        }
        // Re-entry guard: a second flip while the permission request is in
        // flight must not spawn a parallel request.
        guard !pendingOn else { return }
        pendingOn = true
        Task {
            let granted = await scheduler.requestPermission()
            if granted {
                store.enabled = true
                permissionDenied = false
                refreshSchedule()
            } else {
                // Only an actual denial animates the switch back OFF.
                store.enabled = false
                permissionDenied = true
            }
            pendingOn = false
        }
    }

    private func setTime(_ date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        store.hour = comps.hour ?? 18
        store.minute = comps.minute ?? 0
        if store.enabled {
            refreshSchedule()
        }
    }

    private func timeAsDate() -> Date {
        Calendar.current.date(bySettingHour: store.hour, minute: store.minute, second: 0, of: Date()) ?? Date()
    }
}
