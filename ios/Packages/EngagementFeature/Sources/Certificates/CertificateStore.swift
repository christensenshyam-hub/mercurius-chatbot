import Foundation
import Observation
import DesignSystem

/// What the certificates keep, on this device only (`UserDefaults`, never
/// synced, never sent to the server, never logged):
/// - the learner's name, as it should appear on a certificate;
/// - per certificate, when this device saw it earned (`earnedAt`) and the
///   date it prints (`completionDate`, fixed the first time it's made).
///
/// "Delete my data & start over" and the other Settings resets call
/// `reset()` (`SettingsSheet`).
@MainActor
@Observable
public final class CertificateStore {
    /// The name, as typed; nil when none is saved.
    public private(set) var name: String?

    private var earned: [CertificateKind: Date]
    private var completion: [CertificateKind: Date]

    @ObservationIgnored private let defaults: UserDefaults

    static let keyPrefix = "com.mayoailiteracy.mercurius.certificate"
    static let nameKey = keyPrefix + ".name"
    static func earnedKey(_ kind: CertificateKind) -> String { keyPrefix + ".\(kind.rawValue).earnedAt" }
    static func completionKey(_ kind: CertificateKind) -> String { keyPrefix + ".\(kind.rawValue).completionDate" }

    /// Every key this store writes (for the reset and the tests).
    public static var allKeys: [String] {
        [nameKey] + CertificateKind.allCases.flatMap { [earnedKey($0), completionKey($0)] }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.name = defaults.string(forKey: Self.nameKey)
        var earned: [CertificateKind: Date] = [:]
        var completion: [CertificateKind: Date] = [:]
        for kind in CertificateKind.allCases {
            if let seconds = defaults.object(forKey: Self.earnedKey(kind)) as? Double {
                earned[kind] = Date(timeIntervalSince1970: seconds)
            }
            if let seconds = defaults.object(forKey: Self.completionKey(kind)) as? Double {
                completion[kind] = Date(timeIntervalSince1970: seconds)
            }
        }
        self.earned = earned
        self.completion = completion
    }

    /// Save the name (normalized: trimmed, single spaces, at most 80
    /// characters). An empty name removes it.
    public func setName(_ raw: String) {
        let normalized = CertificateNameFit.normalized(raw)
        let value: String? = normalized.isEmpty ? nil : normalized
        guard value != name else { return }
        name = value
        if let value {
            defaults.set(value, forKey: Self.nameKey)
        } else {
            defaults.removeObject(forKey: Self.nameKey)
        }
    }

    /// When this device saw the certificate earned (the moment its last
    /// requirement was met), if it did.
    public func earnedAt(_ kind: CertificateKind) -> Date? { earned[kind] }

    /// Record the moment a certificate was earned. The first record stands.
    public func recordEarned(_ kind: CertificateKind, at date: Date) {
        guard earned[kind] == nil else { return }
        earned[kind] = date
        defaults.set(date.timeIntervalSince1970, forKey: Self.earnedKey(kind))
    }

    /// The date the certificate prints, once it has been made.
    public func completionDate(_ kind: CertificateKind) -> Date? { completion[kind] }

    /// Fix the date a certificate prints (the first time it's made); later
    /// calls keep the first date and return it.
    @discardableResult
    public func fixCompletionDate(_ kind: CertificateKind, lastMetAt: Date?, now: Date = Date()) -> Date {
        let date = CertificateEligibility.completionDate(stored: completion[kind], lastMetAt: lastMetAt, now: now)
        if completion[kind] == nil {
            completion[kind] = date
            defaults.set(date.timeIntervalSince1970, forKey: Self.completionKey(kind))
        }
        return date
    }

    /// Erase the name and every date (Settings' resets).
    public func reset() {
        name = nil
        earned = [:]
        completion = [:]
        for key in Self.allKeys { defaults.removeObject(forKey: key) }
    }
}
