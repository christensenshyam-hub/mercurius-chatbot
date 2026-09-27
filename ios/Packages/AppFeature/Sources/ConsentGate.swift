import Foundation

/// The versioned data-use agreement. `storageKey` holds the version the user
/// last agreed to (0 = never) in `UserDefaults.standard`, so a reinstall
/// re-asks; bumping `currentVersion` re-shows the disclosure to every
/// existing install. Pure so it runs under `swift test`.
public enum ConsentGate {
    public static let currentVersion = 1
    public static let storageKey = "consentVersion"

    public static func needsGate(storedVersion: Int) -> Bool {
        storedVersion < currentVersion
    }
}

/// Self-declared age check. The chosen age is compared here and then
/// dropped — never written to disk, never logged.
public enum AgeGate {
    public static let minimumAge = 13

    /// Every row the age wheel offers, youngest first. The ends are open
    /// buckets so the picker never asks for more precision than the check
    /// needs.
    public static let choices: [Int] = Array(12...18)

    public static func isEligible(age: Int) -> Bool {
        age >= minimumAge
    }

    public static func label(for age: Int) -> String {
        switch age {
        case ...12: return "12 or younger"
        case 18...: return "18 or older"
        default: return String(age)
        }
    }
}

/// An under-13 answer, remembered on this device so the block can't be undone
/// by going back or relaunching. Only when it happened is kept — never the
/// age. In `UserDefaults`, so deleting the app clears it.
public enum AgeBlock {
    public static let storageKey = "ageBlockedAt"

    /// How long a block holds.
    public static let coolOffDays = 7
    static var coolOff: TimeInterval { TimeInterval(coolOffDays) * 24 * 60 * 60 }

    /// A clock set back to before the block keeps it in force.
    public static func isActive(blockedAt: TimeInterval?, now: Date) -> Bool {
        guard let blockedAt, blockedAt > 0 else { return false }
        return now.timeIntervalSince1970 - blockedAt < coolOff
    }
}

/// Reads and writes the `AgeBlock` marker.
struct AgeBlockStore {
    let defaults: UserDefaults

    func isActive(now: Date = Date()) -> Bool {
        AgeBlock.isActive(blockedAt: defaults.object(forKey: AgeBlock.storageKey) as? TimeInterval, now: now)
    }

    func record(now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: AgeBlock.storageKey)
    }
}
