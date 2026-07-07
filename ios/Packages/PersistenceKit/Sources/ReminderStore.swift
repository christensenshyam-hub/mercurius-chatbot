import Foundation
import Observation

/// Persists the daily-reminder preference (on/off + time-of-day). The actual
/// scheduling lives in `EngagementFeature.NotificationScheduler`; this is just
/// the stored state, kept in infra so both the Progress hub and the app shell
/// can read it. `@Observable` so the toggle/time picker stay in sync.
@MainActor
@Observable
public final class ReminderStore {
    public var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }
    /// Hour (0–23) the reminder fires.
    public var hour: Int {
        didSet { defaults.set(hour, forKey: Key.hour) }
    }
    /// Minute (0–59) the reminder fires.
    public var minute: Int {
        didSet { defaults.set(minute, forKey: Key.minute) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let enabled = "engagement.reminder.enabled"
        static let hour = "engagement.reminder.hour"
        static let minute = "engagement.reminder.minute"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Key.enabled)
        // Default to 6:00 PM if the user has never set a time.
        if defaults.object(forKey: Key.hour) != nil {
            self.hour = defaults.integer(forKey: Key.hour)
            self.minute = defaults.integer(forKey: Key.minute)
        } else {
            self.hour = 18
            self.minute = 0
        }
    }
}
