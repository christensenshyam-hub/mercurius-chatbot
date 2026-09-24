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
