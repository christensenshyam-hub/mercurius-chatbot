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

            // Render each pose tile once per refresh; every request needs its
            // OWN file on disk because the system MOVES attachment files into
            // its store when the request is added.
            var tiles: [ReminderPlanner.Pose: Data] = [:]
            for reminder in ReminderPlanner.plan(
                now: Date(), hour: hour, minute: minute,
                streak: streak, chattedToday: chattedToday
            ) {
                let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireDate, repeats: false)
                // A failed add (system limit, etc.) just drops that day —
                // the next refresh re-plans it.
                try? await center.add(
                    UNNotificationRequest(identifier: reminder.id,
                                          content: content(for: reminder, tiles: &tiles),
                                          trigger: trigger)
                )
            }
        }
    }

    /// Build the notification content: title, Merc-voiced body, and the
    /// rendered Merc pose tile as an image attachment (banner + expanded
    /// view). Attachment failures degrade to a text-only notification.
    private func content(
        for reminder: ReminderPlanner.PlannedReminder,
        tiles: inout [ReminderPlanner.Pose: Data]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Mercurius"
        content.body = reminder.body
        content.sound = .default

        let data: Data?
        if let cached = tiles[reminder.pose] {
            data = cached
        } else {
            data = MercNotificationArt.pngData(for: reminder.pose)
            tiles[reminder.pose] = data ?? Data()
        }
        if let data, !data.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("merc-notif-\(UUID().uuidString).png")
            if (try? data.write(to: url)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "merc", url: url) {
                content.attachments = [attachment]
            }
        }
        return content
    }

    #if DEBUG
    /// DEBUG-only (`-NotifPreview`): schedule one of each banner flavor a few
    /// seconds out so the artwork + copy can be seen without waiting for the
    /// real reminder time. Uses the exact same content-building path.
    public func scheduleDemo() {
        Task {
            _ = await requestPermission()
            var tiles: [ReminderPlanner.Pose: Data] = [:]
            let center = UNUserNotificationCenter.current()
            let flavors: [(TimeInterval, String, ReminderPlanner.Pose)] = [
                (8, ReminderPlanner.defenseLine(streak: 2), .sleep),
                (16, ReminderPlanner.dailyLines[0].body, .wave),
                (24, ReminderPlanner.dailyLines[5].body, .celebrate),
            ]
            for (delay, body, pose) in flavors {
                let reminder = ReminderPlanner.PlannedReminder(
                    id: "mercurius.demo.\(pose.rawValue)",
                    fireDate: DateComponents(), body: body, pose: pose
                )
                let content = content(for: reminder, tiles: &tiles)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }
    #endif

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
    #if DEBUG
    public func scheduleDemo() {}
    #endif
    #endif
}
