import Foundation
#if os(iOS)
import UserNotifications
#endif

/// Thin wrapper over `UNUserNotificationCenter` for the single daily learning
/// reminder. Guarded for iOS — the package also compiles for macOS (so
/// `swift test` runs), where these are no-ops.
@MainActor
public final class NotificationScheduler {
    public init() {}

    private let reminderId = "mercurius.daily.reminder"

    #if os(iOS)
    /// Ask for notification permission. Returns whether it was granted.
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Schedule (or replace) the repeating daily reminder at `hour:minute`.
    /// Copy is deliberately streak-number-free so it never goes stale between
    /// launches.
    public func scheduleDaily(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])

        let content = UNMutableNotificationContent()
        content.title = "Mercurius"
        content.body = "Keep your streak alive — take a couple minutes to think with AI today."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger))
    }

    /// Cancel the daily reminder.
    public func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
    }
    #else
    public func requestPermission() async -> Bool { false }
    public func scheduleDaily(hour: Int, minute: Int) {}
    public func cancel() {}
    #endif
}
