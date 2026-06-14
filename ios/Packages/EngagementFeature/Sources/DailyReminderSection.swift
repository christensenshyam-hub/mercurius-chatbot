import SwiftUI
import DesignSystem
import PersistenceKit

/// Daily-reminder controls for the Progress hub: a toggle (which requests
/// notification permission on enable) + a time picker. Self-contained in
/// EngagementFeature so it doesn't pull SettingsFeature into the dependency.
public struct DailyReminderSection: View {
    private let store: ReminderStore
    private let scheduler: NotificationScheduler
    @State private var permissionDenied = false

    public init(store: ReminderStore, scheduler: NotificationScheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Daily reminder")
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)

            Toggle(isOn: Binding(get: { store.enabled }, set: { setEnabled($0) })) {
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
            store.enabled = false
            permissionDenied = false
            scheduler.cancel()
            return
        }
        Task {
            let granted = await scheduler.requestPermission()
            if granted {
                store.enabled = true
                permissionDenied = false
                scheduler.scheduleDaily(hour: store.hour, minute: store.minute)
            } else {
                store.enabled = false
                permissionDenied = true
            }
        }
    }

    private func setTime(_ date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        store.hour = comps.hour ?? 18
        store.minute = comps.minute ?? 0
        if store.enabled {
            scheduler.scheduleDaily(hour: store.hour, minute: store.minute)
        }
    }

    private func timeAsDate() -> Date {
        Calendar.current.date(bySettingHour: store.hour, minute: store.minute, second: 0, of: Date()) ?? Date()
    }
}
