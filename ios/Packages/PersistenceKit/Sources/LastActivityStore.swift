import Foundation
import Observation

/// When the student last did something in the app (sent a chat, opened or
/// finished a lesson, left the app mid-session), plus which tab they were
/// on — so a cold launch shortly after can resume where they were instead
/// of replaying Home.
///
/// Only real activity should `touch()` it: going Home on purpose is not
/// activity, or the resume would fight that choice on the next launch.
/// `UserDefaults`-backed (injectable for tests and the UI-test suite).
@MainActor
@Observable
public final class LastActivityStore {
    public private(set) var lastActivityAt: Date?
    /// The shell tab the student was last on (a raw tab identifier owned by
    /// the app layer). `nil` clears it.
    public var lastTab: String? {
        didSet {
            if let lastTab {
                defaults.set(lastTab, forKey: Key.lastTab)
            } else {
                defaults.removeObject(forKey: Key.lastTab)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let lastActivityAt = "engagement.lastActivityAt"
        static let lastTab = "engagement.lastTab"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastActivityAt = defaults.object(forKey: Key.lastActivityAt) as? Date
        self.lastTab = defaults.string(forKey: Key.lastTab)
    }

    /// Stamp activity at `now`.
    public func touch(now: Date = Date()) {
        lastActivityAt = now
        defaults.set(now, forKey: Key.lastActivityAt)
    }

    /// Whether the last activity happened less than `interval` ago. A stamp
    /// in the future (the device clock moved backwards) counts as not recent,
    /// so a skewed clock falls back to Home rather than resuming blindly.
    public func isWithin(_ interval: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastActivityAt else { return false }
        let elapsed = now.timeIntervalSince(lastActivityAt)
        return elapsed >= 0 && elapsed < interval
    }
}
