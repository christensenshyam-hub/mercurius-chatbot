import Foundation
#if os(iOS)
import UserNotifications
#endif

/// Thin wrapper over `UNUserNotificationCenter` for the learning reminders.
/// Guarded for iOS — the package also compiles for macOS (so `swift test`
/// runs), where these are no-ops.
///
/// The planning (which days, which Merc line, streak defense) lives in the
/// pure `ReminderPlanner`; this type only requests permission and applies a
/// plan to the notification center.
@MainActor
public final class NotificationScheduler {
    public init() {}

    /// The pre-plan era's repeating-reminder id — cleared on every refresh so
    /// upgrading users don't get the old static notification alongside the
    /// planned ones.
    private let legacyReminderId = "mercurius.daily.reminder"

    #if os(iOS)
    /// Ask for notification permission. Returns whether it was granted.
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Re-plan the reminder window from the current state. Safe to call often
    /// (launch, foreground, streak change, settings change): the plan's
    /// per-day identifiers make re-adding a replace, and stale days are
    /// cleared first. No-ops without authorization — an unauthorized add is
    /// silently dropped by the system anyway, so this just keeps intent clear.
    public func refresh(
        enabled: Bool,
        hour: Int,
        minute: Int,
        streak: Int?,
        chattedToday: Bool
    ) {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending + [legacyReminderId])

            guard enabled else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            for reminder in ReminderPlanner.plan(
                now: Date(), hour: hour, minute: minute,
                streak: streak, chattedToday: chattedToday
            ) {
                let content = UNMutableNotificationContent()
                content.title = "Mercurius"
                content.body = reminder.body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireDate, repeats: false)
                center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }

    /// Cancel every scheduled reminder (toggle turned off).
    public func cancel() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending + [legacyReminderId])
        }
    }
    #else
    public func requestPermission() async -> Bool { false }
    public func refresh(enabled: Bool, hour: Int, minute: Int, streak: Int?, chattedToday: Bool) {}
    public func cancel() {}
    #endif
}
