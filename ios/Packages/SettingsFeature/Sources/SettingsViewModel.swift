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
    public private(set) var isResetInProgress: Bool = false
    public private(set) var resetErrorMessage: String?

    /// App marketing version shown in the About section.
    public let appVersion: String
    public let buildNumber: String

    // MARK: - Dependencies

    private let sessionStorage: SessionResetting
    public let themeStore: ThemePreferenceStore

    /// Optional hook for resetting app-side state that isn't owned by
    /// `SettingsFeature` — e.g. clearing the persisted chat history.
    /// Runs synchronously alongside the session reset.
    private let extraReset: (@MainActor () -> Void)?

    // MARK: - Theme projection

    /// Computed binding so SwiftUI pickers can read and write through
    /// the shared `ThemePreferenceStore`. Writes propagate app-wide.
    public var theme: ThemePreference {
        get { themeStore.theme }
        set { themeStore.theme = newValue }
    }

    // MARK: - Init

    public init(
        sessionStorage: SessionResetting,
        themeStore: ThemePreferenceStore,
        bundle: Bundle = .main,
        extraReset: (@MainActor () -> Void)? = nil
    ) {
        self.sessionStorage = sessionStorage
        self.themeStore = themeStore
        self.extraReset = extraReset
        self.appVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
        self.buildNumber = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
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
            // Clear any extra app-side state the host wired up
            // (e.g. persisted chat history).
            extraReset?()
            // Immediately generate a fresh session so the app has
            // a valid one for the next request.
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
}
