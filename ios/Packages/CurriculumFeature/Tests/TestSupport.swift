import Foundation
@testable import SettingsFeature

/// Minimal in-memory `PreferenceStore` for tests. Mirrors the one in
/// SettingsFeatureTests but kept local so this package's tests don't
/// cross-module-depend on another package's test target.
final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private(set) var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

/// A settable clock to hand the store as `now`.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

enum ProgressKeys {
    static let base = "com.mayoailiteracy.mercurius.curriculumProgress"
    static let version = base + ".version"
    static let completedAt = base + ".completedAt"
    static let lastOpened = base + ".lastOpened"
    static let inProgress = base + ".inProgress"
}
