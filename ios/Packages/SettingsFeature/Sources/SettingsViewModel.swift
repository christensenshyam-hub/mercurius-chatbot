import Foundation
import Observation
import SwiftUI
import NetworkingKit

/// Abstraction over session storage so the view model is testable
/// without touching the Keychain. In production this is satisfied by
/// `SessionIdentity`.
public protocol SessionResetting: Sendable {
    /// Returns the current session identifier (generates one if needed).
    func current() throws -> String
    /// Deletes the current session identifier.
    func reset() throws
}

extension SessionIdentity: SessionResetting {}

/// Theme preference. `.system` follows iOS appearance settings.
public enum ThemePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Small wrapper around `UserDefaults` so tests can inject an
/// in-memory store without touching the app's shared defaults.
public protocol PreferenceStore: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

public final class UserDefaultsPreferenceStore: PreferenceStore, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    public func string(for key: String) -> String? {
        defaults.string(forKey: key)
    }
    public func set(_ value: String?, for key: String) {
        defaults.set(value, forKey: key)
    }
}

/// Settings-screen state. All UI state lives here; the view is purely
/// a projection of this object.
@MainActor
@Observable
public final class SettingsViewModel {

    // MARK: - Observable state

    public private(set) var sessionId: String = ""
    public var theme: ThemePreference {
        didSet { preferences.set(theme.rawValue, for: Keys.theme) }
    }
    public private(set) var isResetInProgress: Bool = false
    public private(set) var resetErrorMessage: String?

    /// App marketing version shown in the About section.
    public let appVersion: String
    public let buildNumber: String

    // MARK: - Dependencies

    private let sessionStorage: SessionResetting
    private let preferences: PreferenceStore

    // MARK: - Init

    public init(
        sessionStorage: SessionResetting,
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        bundle: Bundle = .main
    ) {
        self.sessionStorage = sessionStorage
        self.preferences = preferences
        self.appVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        self.buildNumber = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "—"

        let stored = preferences.string(for: Keys.theme)
            .flatMap(ThemePreference.init(rawValue:))
        self.theme = stored ?? .system
    }

    // MARK: - Actions

    /// Resolves the current session id for display in the UI. No-throw
    /// wrapper — if resolution fails we show "Unavailable" rather than
    /// surfacing the error.
    public func loadSessionId() {
        do {
            sessionId = try sessionStorage.current()
        } catch {
            sessionId = "Unavailable"
        }
    }

    /// Delete the current session and generate a new one. Used by a
    /// "Start Over" action — clears the student's identity on this
    /// device, so streak / memory / leaderboard entries won't be
    /// associated with their next session.
    @discardableResult
    public func resetSession() async -> Bool {
        guard !isResetInProgress else { return false }
        isResetInProgress = true
        resetErrorMessage = nil
        defer { isResetInProgress = false }

        do {
            try sessionStorage.reset()
            // Immediately generate a fresh one so the app has a valid
            // session to use on the next request.
            sessionId = try sessionStorage.current()
            return true
        } catch {
            resetErrorMessage = "Couldn't reset session. Try again."
            return false
        }
    }

    public func clearResetError() {
        resetErrorMessage = nil
    }

    // MARK: - Keys

    private enum Keys {
        static let theme = "com.mayoailiteracy.mercurius.theme"
    }
}
