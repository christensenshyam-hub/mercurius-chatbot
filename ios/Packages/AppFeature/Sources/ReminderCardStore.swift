import Foundation
import Observation
#if os(iOS)
import UserNotifications
#endif

/// The one-time Home card that offers the weekly nudges to installs which
/// finished onboarding without choosing them — every install upgraded from
/// before the nudges existed. New installs answer the same question on
/// onboarding's "Your path" step, which marks the card handled, so they never
/// see it.
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

    /// Where iOS stands on notifications for Mercurius.
    enum Permission: Equatable {
        case notDetermined
        case denied
        /// Authorized, provisional or ephemeral.
        case allowed
    }

    /// Offered once to a student whose weekly nudges are off, after
    /// onboarding. An authorized install is asked too, since nudges it never
    /// chose stay off. Not when iOS notifications are off — Home shouldn't
    /// ask for what iOS Settings has refused — and not before the permission
    /// is known (`nil`).
    static func shows(
        weeklyEnabled: Bool,
        handled: Bool,
        onboardingComplete: Bool,
        permission: Permission?
    ) -> Bool {
        guard !weeklyEnabled, !handled, onboardingComplete, let permission else { return false }
        return permission != .denied
    }

    static func notificationPermission() async -> Permission {
        #if os(iOS)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        @unknown default: return .denied
        }
        #else
        return .notDetermined
        #endif
    }
}
