#if os(iOS)
import Foundation
import UserNotifications

/// The app's `UNUserNotificationCenter` delegate: shows reminders as banners
/// while the app is open, and turns a tapped reminder into "open this
/// lesson" via `onOpenLesson`.
///
/// The app must install `shared` as the center's delegate before launch
/// finishes, or a tap that cold-launches the app is never delivered. A tap
/// that arrives before `onOpenLesson` is set is held and handed over as
/// soon as it is.
@MainActor
public final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationRouter()

    /// Called on the main actor with the lesson id from a tapped reminder.
    public var onOpenLesson: ((String) -> Void)? {
        didSet { deliverHeldLesson() }
    }

    private var heldLessonId: String?

    override private init() {
        super.init()
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // Completion-handler form on purpose: the system expects its completion
    // on the main thread, which a nonisolated async witness doesn't guarantee.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let lessonId = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? LessonDeepLink.lessonId(fromUserInfo: response.notification.request.content.userInfo)
            : nil
        if let lessonId {
            Task { @MainActor in self.open(lessonId) }
        }
        completionHandler()
    }

    private func open(_ lessonId: String) {
        if let onOpenLesson {
            onOpenLesson(lessonId)
        } else {
            heldLessonId = lessonId
        }
    }

    private func deliverHeldLesson() {
        guard let onOpenLesson, let lessonId = heldLessonId else { return }
        heldLessonId = nil
        onOpenLesson(lessonId)
    }
}
#endif
