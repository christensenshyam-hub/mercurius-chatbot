import Foundation
#if os(iOS)
import UserNotifications
#endif

/// Thin wrapper over `UNUserNotificationCenter` for the learning reminders.
/// Guarded for iOS — the package also compiles for macOS (so `swift test`
/// runs), where these are no-ops.
///
/// The planning (which days, which Merc line, streak defense, the weekly
/// nudges) lives in the pure `ReminderPlanner`; this type only requests
/// permission and applies a plan to the notification center. It never sets
/// the center's delegate — that's `NotificationRouter`, installed by the app.
@MainActor
public final class NotificationScheduler {
    public init() {}

    /// This week's lessons against the weekly goal, read at every re-plan so
    /// the weekly nudges skip a week whose goal is met (AUD-36). Set by the
    /// composition root, which can see the curriculum; until it is, a week
    /// counts as nothing done.
    public var weekProgress: (@MainActor () -> ReminderPlanner.WeekProgress?)?

    /// The pre-plan era's repeating-reminder id — cleared on every refresh so
    /// upgrading users don't get the old static notification alongside the
    /// planned ones.
    private let legacyReminderId = "mercurius.daily.reminder"

    #if os(iOS)
    /// The last queued center operation. Each refresh/cancel is a
    /// remove-then-add across several awaits; chaining them keeps a quick
    /// off → on toggle from interleaving into a stale schedule.
    private var lastOperation: Task<Void, Never>?

    /// Ask for notification permission. Returns whether it was granted.
    public func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Whether the system currently lets Mercurius post notifications.
    public func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Re-plan every reminder from the current state. Safe to call often
    /// (launch, foreground, streak change, settings change): all Mercurius
    /// reminders are cleared, then re-added. No-ops without authorization —
    /// an unauthorized add is silently dropped by the system anyway, so this
    /// just keeps intent clear.
    ///
    /// - Parameters:
    ///   - enabled: the daily streak reminder preference. Daily reminders are
    ///     only scheduled while there's a live `streak` to protect, and only
    ///     through the last day a chat can still save it.
    ///   - streakDay: the day `streak` was last confirmed on.
    ///   - weeklyEnabled: the weekly nudges (Sunday + Wednesday), skipped in a
    ///     week whose goal `weekProgress` reports as met.
    ///   - nextLessonId: when given, every reminder opens that lesson on tap.
    public func refresh(
        enabled: Bool,
        hour: Int,
        minute: Int,
        streak: Int?,
        streakDay: Date?,
        chattedToday: Bool,
        weeklyEnabled: Bool,
        nextLessonId: String? = nil
    ) {
        var daily: ReminderPlanner.DailySettings?
        if enabled, let streak, let streakDay {
            daily = ReminderPlanner.DailySettings(hour: hour, minute: minute, streak: streak,
                                                  streakDay: streakDay, chattedToday: chattedToday)
        }
        let week = weeklyEnabled
            ? (weekProgress?() ?? ReminderPlanner.WeekProgress.unknown(now: Date()))
            : nil
        apply(daily: daily, week: week, nextLessonId: nextLessonId)
    }

    /// Clear and re-add the daily family (`daily == nil` → none planned) and
    /// the weekly family (`week == nil` → none planned).
    private func apply(
        daily: ReminderPlanner.DailySettings?,
        week: ReminderPlanner.WeekProgress?,
        nextLessonId: String?
    ) {
        let center = UNUserNotificationCenter.current()
        enqueue { [legacyReminderId] in
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter(Self.isPlannedReminder)
            center.removePendingNotificationRequests(withIdentifiers: pending + [legacyReminderId])

            let planned = ReminderPlanner.schedule(now: Date(), daily: daily, week: week)
            guard !planned.isEmpty, await self.notificationsAuthorized() else { return }

            // Render each pose tile once per refresh; every request needs its
            // OWN file on disk because the system MOVES attachment files into
            // its store when the request is added.
            var tiles: [ReminderPlanner.Pose: Data] = [:]
            for reminder in planned {
                // Every reminder is a dated one-off; re-planning keeps the
                // window ahead of the student.
                let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireDate, repeats: false)
                // A failed add (system limit, etc.) just drops that reminder —
                // the next refresh re-plans it.
                try? await center.add(
                    UNNotificationRequest(
                        identifier: reminder.id,
                        content: self.content(for: reminder, tiles: &tiles, nextLessonId: nextLessonId),
                        trigger: trigger
                    )
                )
            }
        }
    }

    private static func isPlannedReminder(_ id: String) -> Bool {
        id.hasPrefix(ReminderPlanner.idPrefix) || id.hasPrefix(ReminderPlanner.weeklyIdPrefix)
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = lastOperation
        lastOperation = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Build the notification content: title, Merc-voiced body, the lesson
    /// link, and the rendered Merc pose tile as an image attachment (banner +
    /// expanded view). Attachment failures degrade to a text-only notification.
    private func content(
        for reminder: ReminderPlanner.PlannedReminder,
        tiles: inout [ReminderPlanner.Pose: Data],
        nextLessonId: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Mercurius"
        content.body = reminder.body
        content.sound = .default
        if let nextLessonId {
            content.userInfo = [LessonDeepLink.userInfoKey: LessonDeepLink.urlString(forLesson: nextLessonId)]
        }

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
    ///
    /// Foreground banners come from `NotificationRouter` (the app installs it
    /// as the center's delegate at launch), so this never touches the
    /// delegate. With `nextLessonId`, tapping a banner exercises the lesson
    /// link end to end.
    public func scheduleDemo(nextLessonId: String? = nil) {
        Task {
            let center = UNUserNotificationCenter.current()
            // Full authorization so the banners actually interrupt (provisional
            // delivers quietly, with no foreground banner). One "Allow" tap on
            // the dialog; timers below start once it's granted.
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            var tiles: [ReminderPlanner.Pose: Data] = [:]
            let wednesday = ReminderPlanner.wednesdaySlot
            let flavors: [(TimeInterval, String, ReminderPlanner.Pose)] = [
                (4, ReminderPlanner.defenseLine(streak: 2), .sleep),
                (10, ReminderPlanner.weeklyLine(weekday: wednesday.weekday, done: 0), wednesday.pose),
                (16, ReminderPlanner.dailyLines[5].body, .celebrate),
            ]
            for (delay, body, pose) in flavors {
                let reminder = ReminderPlanner.PlannedReminder(
                    id: "mercurius.demo.\(pose.rawValue)",
                    fireDate: DateComponents(), body: body, pose: pose
                )
                let content = content(for: reminder, tiles: &tiles, nextLessonId: nextLessonId)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }
    #endif

    /// Cancel every scheduled Mercurius reminder, daily and weekly.
    public func cancel() {
        let center = UNUserNotificationCenter.current()
        enqueue { [legacyReminderId] in
            let pending = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter(Self.isPlannedReminder)
            center.removePendingNotificationRequests(withIdentifiers: pending + [legacyReminderId])
        }
    }

    #else
    public func requestPermission() async -> Bool { false }
    public func notificationsAuthorized() async -> Bool { false }
    public func refresh(
        enabled: Bool,
        hour: Int,
        minute: Int,
        streak: Int?,
        streakDay: Date?,
        chattedToday: Bool,
        weeklyEnabled: Bool,
        nextLessonId: String? = nil
    ) {}
    public func cancel() {}
    #if DEBUG
    public func scheduleDemo(nextLessonId: String? = nil) {}
    #endif
    #endif
}
