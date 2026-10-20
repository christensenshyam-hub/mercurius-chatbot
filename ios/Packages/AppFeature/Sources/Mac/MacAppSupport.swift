#if os(macOS)
import Foundation
import UserNotifications
import EngagementFeature

/// App-level hooks for the Mac app target, which links only AppFeature and
/// DesignSystem.
public enum MacAppSupport {
    /// Install the reminders' notification-center delegate (shows a reminder
    /// while the app is open; a click opens its lesson). Must run before
    /// launch finishes, or a click that launches the app is lost — as on iOS
    /// (`MercuriusApp`). Nothing happens outside an app bundle.
    @MainActor
    public static func installNotificationDelegate() {
        NotificationScheduler.center?.delegate = NotificationRouter.shared
    }
}
#endif
