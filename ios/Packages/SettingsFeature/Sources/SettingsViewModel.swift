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
///
/// No longer offered or read: both apps are dark only (`BrandAppearance`,
/// docs/ios-night-only/PR.md). The type and its store stay so the stored
/// key and the hosts' initialisers don't change; a later cleanup can drop
/// them.
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

    /// True while "Delete my data & start over" is talking to the server
    /// and/or rotating the local id. Distinct from `isResetInProgress` so
    /// the two rows can be disabled independently.
    public private(set) var isDeleteInProgress: Bool = false
    public private(set) var deleteErrorMessage: String?

    /// App marketing version shown in the About section.
    public let appVersion: String
    public let buildNumber: String

    /// Called after a successful consent withdrawal (server data deleted and
    /// the local id rotated). The host uses it to reset the consent flag and
    /// dismiss Settings so the agreement is shown again.
    public var onConsentWithdrawn: (@MainActor () -> Void)?

    /// Awaited before the server delete so a chat stream still running under
    /// the old id can't finish after the erasure and re-create rows for it.
    /// The host wires this to the chat model's stop; nil when there is no
    /// chat to stop (previews, tests).
    public var cancelInFlight: (@MainActor () async -> Void)?

    /// Displayed when the session id can't be read. Kept distinct from the
    /// real ids so the copy button knows there's nothing worth copying.
    static let unavailableSessionId = "Unavailable"

    /// Shown when the server can't be reached to delete the session. Says
    /// up front what the fallback leaves behind (AUD-54).
    static let serverDeleteFailedMessage =
        "Couldn't reach the server to delete your data. Check your connection and try again. "
        + resetLeavesServerCopy

    /// Shown when the delete failed for a reason that isn't the connection
    /// and isn't an `APIError` with copy of its own.
    static let genericDeleteFailedMessage =
        "Couldn't delete your data right now. Try again. " + resetLeavesServerCopy

    static let resetLeavesServerCopy = "Resetting only this device leaves your chats on our server."

    /// The alert copy for a failed server delete. Only a connection problem
    /// gets the "check your connection" line; a 400/429/500 says what the
    /// server actually did. `.unknown` is treated as a connection problem:
    /// on this path it means the server never confirmed (an unmapped
    /// `URLError`, a non-HTTP response), where "reach the server — or reset
    /// this device only" is still the right escape hatch.
    static func deleteFailureMessage(for error: APIError) -> String {
        switch error {
        case .offline, .connectionLost, .unreachableOnThisNetwork, .timeout, .unknown:
            return serverDeleteFailedMessage
        default:
            return error.userFacingMessage
        }
    }

    /// Whether `sessionId` holds a real identifier (not empty, not the
    /// "Unavailable" placeholder).
    public var canCopySessionId: Bool {
        !sessionId.isEmpty && sessionId != Self.unavailableSessionId
    }

    // MARK: - Dependencies

    private let sessionStorage: SessionResetting
    /// Optional so hosts without networking (previews, tests) can omit it;
    /// when nil, deletion falls back to the local-only reset.
    private let sessionDeleter: SessionDeleting?
    public let themeStore: ThemePreferenceStore

    /// Standby gamification "show progress nudges" preference. Constructed
    /// internally (no init-signature change) so existing callers are
    /// unaffected. Only surfaced in the UI when `GamificationFlag.clientEnabled`.
    public let nudgeStore: NudgePreferenceStore = NudgePreferenceStore()

    /// Optional hook for resetting app-side state that isn't owned by
    /// `SettingsFeature` — e.g. clearing the persisted chat history.
    /// Runs synchronously alongside the session reset.
    private let extraReset: (@MainActor () -> Void)?

    // MARK: - Theme projection

    /// Computed binding through the shared `ThemePreferenceStore`. No
    /// Settings screen shows it any more, and nothing applies it: the app is
    /// dark only (`BrandAppearance`).
    public var theme: ThemePreference {
        get { themeStore.theme }
        set { themeStore.theme = newValue }
    }

    /// Computed binding for the "show progress nudges" toggle. Writes through
    /// the shared preference store (and thus the shared UserDefaults key that
    /// `GamificationStore` reads).
    public var nudgesEnabled: Bool {
        get { nudgeStore.isEnabled }
        set { nudgeStore.isEnabled = newValue }
    }

    // MARK: - Init

    public init(
        sessionStorage: SessionResetting,
        themeStore: ThemePreferenceStore,
        bundle: Bundle = .main,
        extraReset: (@MainActor () -> Void)? = nil,
        sessionDeleter: SessionDeleting? = nil
    ) {
        self.sessionStorage = sessionStorage
        self.themeStore = themeStore
        self.extraReset = extraReset
        self.sessionDeleter = sessionDeleter
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
            sessionId = Self.unavailableSessionId
        }
    }

    /// Local-only reset: delete the current session id and generate a new
    /// one without contacting the server. Offered as the fallback when
    /// `deleteServerDataAndStartOver()` can't reach the server. Data the
    /// server holds under the old id stays there but is no longer linked
    /// to this device.
    @discardableResult
    public func resetSession() async -> Bool {
        guard !isResetInProgress, !isDeleteInProgress else { return false }
        isResetInProgress = true
        resetErrorMessage = nil
        defer { isResetInProgress = false }

        do {
            try resetLocally()
            return true
        } catch {
            resetErrorMessage = "Couldn't reset session. Try again."
            return false
        }
    }

    /// Erase the session on the server (under the id the data was written
    /// with), then run the local reset and mint a fresh id. If the server
    /// call fails nothing local changes — beyond the in-flight reply having
    /// been stopped — so the user can retry; the old id is the only
    /// capability that can delete that data.
    @discardableResult
    public func deleteServerDataAndStartOver() async -> Bool {
        guard !isDeleteInProgress, !isResetInProgress else { return false }
        isDeleteInProgress = true
        deleteErrorMessage = nil
        defer { isDeleteInProgress = false }

        let oldId: String
        do {
            oldId = try sessionStorage.current()
        } catch {
            deleteErrorMessage = "Couldn't read this device's session ID. Try again. " + Self.resetLeavesServerCopy
            return false
        }

        // Stop any reply still streaming under `oldId` before the erasure —
        // its completion would otherwise write the session back.
        await cancelInFlight?()

        if let sessionDeleter {
            do {
                try await sessionDeleter.deleteSession(sessionId: oldId)
            } catch let error as APIError {
                deleteErrorMessage = Self.deleteFailureMessage(for: error)
                return false
            } catch {
                deleteErrorMessage = Self.genericDeleteFailedMessage
                return false
            }
        }

        do {
            try resetLocally()
            return true
        } catch {
            // Server-side data is already gone (the endpoint is idempotent,
            // so a retry is harmless); only the local rotation failed.
            deleteErrorMessage = "Your data was deleted from the server, but this device couldn't be reset. Try again."
            return false
        }
    }

    /// Consent withdrawal = full deletion plus telling the host to show
    /// the agreement again. The host callback only fires on success so a
    /// failed server delete never leaves the app in a half-withdrawn state.
    @discardableResult
    public func withdrawConsent() async -> Bool {
        let ok = await deleteServerDataAndStartOver()
        if ok { onConsentWithdrawn?() }
        return ok
    }

    /// Fallback for consent withdrawal when the server can't be reached:
    /// reset this device only and still show the agreement again. Data
    /// under the old id stays on the server.
    @discardableResult
    public func withdrawConsentLocally() async -> Bool {
        let ok = await resetSession()
        if ok { onConsentWithdrawn?() }
        return ok
    }

    /// What to show before a device-only reset, the fallback when the
    /// server delete fails: the ID the server data sits under, re-read now,
    /// since the reset is about to replace it (AUD-54).
    public func deviceOnlyResetNotice() -> DeviceOnlyResetNotice {
        loadSessionId()
        return DeviceOnlyResetNotice(sessionId: canCopySessionId ? sessionId : nil)
    }

    public func clearResetError() {
        resetErrorMessage = nil
    }

    public func clearDeleteError() {
        deleteErrorMessage = nil
    }

    // MARK: - Private

    /// Shared tail of both reset paths: drop the Keychain id, clear the
    /// host-owned local state, and immediately mint a fresh id so the next
    /// request has a valid one.
    private func resetLocally() throws {
        try sessionStorage.reset()
        extraReset?()
        sessionId = try sessionStorage.current()
    }
}

/// The warning before "Reset this device only" (AUD-54). A device-only reset
/// drops the ID that is the only key to the student's server data, so after
/// it nothing on the device can delete that data; only an email to
/// `privacyEmail` quoting the old ID can. The sheet shows the ID with a Copy
/// button first.
public struct DeviceOnlyResetNotice: Equatable, Identifiable, Sendable {
    /// Where a student who reset only this device can still have the old
    /// ID's data deleted (the privacy policy's email route).
    public static let privacyEmail = "privacy@trymercurius.com"

    /// The current (soon old) ID, or nil when it can't be read.
    public let sessionId: String?

    public var id: String { sessionId ?? "unreadable" }

    public var title: String { "Reset this device only?" }

    public var message: String {
        if sessionId != nil {
            return "Our server still has your chats and progress under the ID below. "
                + "After this reset, the app can't delete them for you. "
                + "To delete them later, email \(Self.privacyEmail) with this ID, so copy it first."
        }
        return "Our server still has your chats and progress under this device's ID, which can't be "
            + "read right now. After this reset, nothing on this device can delete them. "
            + "Try deleting again later instead if you can."
    }
}
