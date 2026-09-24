import Foundation
import Observation
#if os(iOS)
import UserNotifications
#endif

/// The one-time Home card that offers the weekly nudges to installs which
/// finished onboarding before the nudges existed. New installs answer the
/// same question on onboarding's "Your path" step, which marks the card
/// handled, so they never see it.
@MainActor
@Observable
final class ReminderCardStore {
    static let storageKey = "home.reminderCard.handled"

    private(set) var isHandled: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isHandled = defaults.bool(forKey: Self.storageKey)
    }

    /// Accepted, dismissed, or answered in onboarding — never shown again.
    func markHandled() {
        guard !isHandled else { return }
        isHandled = true
        defaults.set(true, forKey: Self.storageKey)
    }

    /// Only offered while iOS would still show its permission prompt: a
    /// student who already allowed notifications gets the weekly nudges by
    /// default, and one who declined shouldn't be asked again from Home.
    static func shows(handled: Bool, canAskPermission: Bool) -> Bool {
        !handled && canAskPermission
    }

    /// Whether the system permission prompt has never been answered.
    static func canAskForNotifications() async -> Bool {
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
        #else
        return false
        #endif
    }
}
