import Testing
import Foundation
import NetworkingKit
@testable import SettingsFeature

// MARK: - Fakes

final class FakeSessionStorage: SessionResetting, @unchecked Sendable {
    enum Behavior {
        case ok
        case throwOnCurrent(Error)
        case throwOnReset(Error)
    }
    var behavior: Behavior = .ok
    var storedId: String = "existing-id"
    var resetCount = 0
    var currentCallCount = 0

    func current() throws -> String {
        currentCallCount += 1
        if case .throwOnCurrent(let error) = behavior { throw error }
        return storedId
    }

    func reset() throws {
        resetCount += 1
        if case .throwOnReset(let error) = behavior { throw error }
        storedId = "new-id-\(resetCount)"
    }
}

/// Ordered record of which hooks fired, for call-order assertions.
final class CallLog: @unchecked Sendable {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

/// Records every id it was asked to delete. `error` makes the call throw;
/// `delay` keeps it suspended so callers can observe the in-progress flag;
/// `onDelete` fires on entry so tests can log call order against other hooks.
final class FakeSessionDeleter: SessionDeleting, @unchecked Sendable {
    var error: Error?
    var delay: Duration = .zero
    var onDelete: (@Sendable () -> Void)?
    private(set) var deletedIds: [String] = []

    func deleteSession(sessionId: String) async throws {
        deletedIds.append(sessionId)
        onDelete?()
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let error { throw error }
    }
}

@MainActor
private func makeModel(
    storage: FakeSessionStorage = FakeSessionStorage(),
    prefs: InMemoryPreferenceStore = InMemoryPreferenceStore(),
    bundle: Bundle = .main,
    extraReset: (@MainActor () -> Void)? = nil,
    deleter: FakeSessionDeleter? = nil
) -> SettingsViewModel {
    let themeStore = ThemePreferenceStore(preferences: prefs)
    return SettingsViewModel(
        sessionStorage: storage,
        themeStore: themeStore,
        bundle: bundle,
        extraReset: extraReset,
        sessionDeleter: deleter
    )
}

// MARK: - Tests

@Suite("ThemePreference")
struct ThemePreferenceTests {

    @Test("All cases have display names")
    func displayNames() {
        for theme in ThemePreference.allCases {
            #expect(!theme.displayName.isEmpty)
        }
    }

    @Test("System returns nil color scheme; light/dark return matching")
    func colorSchemes() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }
}

@Suite("SettingsViewModel initial state")
@MainActor
struct SettingsViewModelInitTests {

    @Test("Defaults to system theme when no preference stored")
    func defaultTheme() {
        let model = makeModel()
        #expect(model.theme == .system)
    }

    @Test("Restores previously persisted theme")
    func restoresPersistedTheme() {
        let prefs = InMemoryPreferenceStore()
        prefs.set(ThemePreference.dark.rawValue, for: "com.mayoailiteracy.mercurius.theme")
        let model = makeModel(prefs: prefs)
        #expect(model.theme == .dark)
    }

    @Test("Ignores unknown persisted theme values")
    func ignoresUnknownTheme() {
        let prefs = InMemoryPreferenceStore()
        prefs.set("turbo", for: "com.mayoailiteracy.mercurius.theme")
        let model = makeModel(prefs: prefs)
        #expect(model.theme == .system)
    }

    @Test("Changing theme persists to preferences")
    func persistsThemeChange() {
        let prefs = InMemoryPreferenceStore()
        let model = makeModel(prefs: prefs)
        model.theme = .dark
        #expect(prefs.string(for: "com.mayoailiteracy.mercurius.theme") == "dark")
    }

    @Test("Version and build are read from the supplied bundle")
    func versionFromBundle() {
        // Bundle.main won't have the app's Info.plist when run under
        // `swift test` (it's the test bundle's Info.plist). We accept
        // any non-empty value — either the real version or the "—"
        // fallback from SettingsViewModel when keys are missing.
        let model = makeModel()
        #expect(!model.appVersion.isEmpty)
        #expect(!model.buildNumber.isEmpty)
    }
}

@Suite("SettingsViewModel session reset")
@MainActor
struct SettingsViewModelResetTests {

    @Test("loadSessionId displays the current id")
    func loadsCurrentId() {
        let storage = FakeSessionStorage()
        storage.storedId = "abc123"
        let model = makeModel(storage: storage)
        model.loadSessionId()
        #expect(model.sessionId == "abc123")
    }

    @Test("loadSessionId falls back gracefully when current throws")
    func loadFailsGracefully() {
        struct E: Error {}
        let storage = FakeSessionStorage()
        storage.behavior = .throwOnCurrent(E())
        let model = makeModel(storage: storage)
        model.loadSessionId()
        #expect(model.sessionId == "Unavailable")
    }

    @Test("resetSession deletes, regenerates, and returns true on success")
    func resetSucceeds() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let model = makeModel(storage: storage)
        model.loadSessionId()
        #expect(model.sessionId == "old-id")

        let ok = await model.resetSession()
        #expect(ok)
        #expect(storage.resetCount == 1)
        #expect(model.sessionId.hasPrefix("new-id-"))
        #expect(model.isResetInProgress == false)
        #expect(model.resetErrorMessage == nil)
    }

    @Test("resetSession surfaces an error message on failure")
    func resetFails() async {
        struct E: Error {}
        let storage = FakeSessionStorage()
        storage.behavior = .throwOnReset(E())
        let model = makeModel(storage: storage)

        let ok = await model.resetSession()
        #expect(!ok)
        #expect(model.resetErrorMessage != nil)
        #expect(model.isResetInProgress == false)
    }

    @Test("clearResetError clears the message")
    func clearsError() async {
        struct E: Error {}
        let storage = FakeSessionStorage()
        storage.behavior = .throwOnReset(E())
        let model = makeModel(storage: storage)
        _ = await model.resetSession()
        #expect(model.resetErrorMessage != nil)
        model.clearResetError()
        #expect(model.resetErrorMessage == nil)
    }

    // NOTE on concurrent reset safety:
    // `resetSession()` runs entirely on the MainActor with no internal
    // `await` between the `isResetInProgress` flag being set and cleared
    // (the underlying Keychain ops are synchronous). Concurrent callers
    // therefore can't observe the flag mid-flight, so a "second call
    // becomes a no-op" test can't be expressed meaningfully without
    // artificially slowing the implementation. The guard is kept as
    // defensive programming in case `reset()` ever becomes async.
    // `deleteServerDataAndStartOver()` DOES suspend (on the server call),
    // so its guard is exercised in `SettingsViewModelDeleteTests`.
}

@Suite("SettingsViewModel delete server data")
@MainActor
struct SettingsViewModelDeleteTests {
    struct E: Error {}

    @Test("Deletes under the OLD id, then resets locally and mints a new one")
    func deletesOldIdThenMintsNew() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        var extraResetCalls = 0
        let model = makeModel(
            storage: storage,
            extraReset: { extraResetCalls += 1 },
            deleter: deleter
        )
        model.loadSessionId()
        #expect(model.sessionId == "old-id")

        let ok = await model.deleteServerDataAndStartOver()

        #expect(ok)
        // The fake storage rotates its id inside reset(), so seeing "old-id"
        // here proves the server call happened before the local reset.
        #expect(deleter.deletedIds == ["old-id"])
        #expect(storage.resetCount == 1)
        #expect(extraResetCalls == 1)
        #expect(model.sessionId.hasPrefix("new-id-"))
        #expect(model.isDeleteInProgress == false)
        #expect(model.deleteErrorMessage == nil)
    }

    @Test("Server failure keeps the local id, sets the error, and never resets")
    func serverFailureLeavesDeviceUntouched() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.error = E()
        var extraResetCalls = 0
        let model = makeModel(
            storage: storage,
            extraReset: { extraResetCalls += 1 },
            deleter: deleter
        )
        model.loadSessionId()

        let ok = await model.deleteServerDataAndStartOver()

        #expect(!ok)
        #expect(deleter.deletedIds == ["old-id"])
        #expect(storage.resetCount == 0)
        #expect(extraResetCalls == 0)
        #expect(storage.storedId == "old-id")
        #expect(model.sessionId == "old-id")
        // A non-APIError gets the neutral copy, not the connection line.
        #expect(model.deleteErrorMessage == SettingsViewModel.genericDeleteFailedMessage)
        #expect(model.deleteErrorMessage?.contains("reset this device only") == true)
        #expect(model.isDeleteInProgress == false)
    }

    @Test("Only connection failures get the 'check your connection' copy")
    func failureCopyMatchesTheError() async {
        let cases: [(error: APIError, expected: String)] = [
            (.offline, SettingsViewModel.serverDeleteFailedMessage),
            (.timeout, SettingsViewModel.serverDeleteFailedMessage),
            // Never confirmed by the server: reach-the-server copy is still right.
            (.unknown(underlying: "Non-HTTP response"), SettingsViewModel.serverDeleteFailedMessage),
            // A dropped socket surfaces as a URLError, not the reachability verdict.
            (APIClient.mapURLError(URLError(.networkConnectionLost)), SettingsViewModel.serverDeleteFailedMessage),
            (.rateLimited, APIError.rateLimited.userFacingMessage),
            (.server(status: 500), APIError.server(status: 500).userFacingMessage),
            (.invalidRequest(reason: "bad id"), APIError.invalidRequest(reason: "bad id").userFacingMessage),
        ]
        for c in cases {
            let deleter = FakeSessionDeleter()
            deleter.error = c.error
            let model = makeModel(deleter: deleter)

            #expect(await model.deleteServerDataAndStartOver() == false)
            #expect(model.deleteErrorMessage == c.expected, "\(c.error)")
        }
        #expect(SettingsViewModel.deleteFailureMessage(for: .rateLimited)
                != SettingsViewModel.serverDeleteFailedMessage)
        #expect(SettingsViewModel.deleteFailureMessage(for: .server(status: 500))
                != SettingsViewModel.serverDeleteFailedMessage)
    }

    @Test("cancelInFlight runs before the server delete")
    func cancelsInFlightBeforeDelete() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        let log = CallLog()
        deleter.onDelete = { log.append("deleteSession") }
        let model = makeModel(storage: storage, deleter: deleter)
        model.cancelInFlight = { log.append("cancelInFlight") }

        #expect(await model.deleteServerDataAndStartOver() == true)
        #expect(log.entries == ["cancelInFlight", "deleteSession"])
    }

    @Test("A failing delete after cancelInFlight still leaves the device untouched")
    func failedDeleteAfterCancelLeavesDeviceUntouched() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.error = APIError.server(status: 500)
        let log = CallLog()
        deleter.onDelete = { log.append("deleteSession") }
        var extraResetCalls = 0
        let model = makeModel(storage: storage, extraReset: { extraResetCalls += 1 }, deleter: deleter)
        model.cancelInFlight = { log.append("cancelInFlight") }
        model.loadSessionId()

        #expect(await model.deleteServerDataAndStartOver() == false)
        #expect(log.entries == ["cancelInFlight", "deleteSession"])
        #expect(storage.resetCount == 0)
        #expect(extraResetCalls == 0)
        #expect(storage.storedId == "old-id")
        #expect(model.sessionId == "old-id")
    }

    @Test("Retry after a server failure succeeds and still uses the old id")
    func retryAfterFailure() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.error = E()
        let model = makeModel(storage: storage, deleter: deleter)

        #expect(await model.deleteServerDataAndStartOver() == false)
        deleter.error = nil
        #expect(await model.deleteServerDataAndStartOver() == true)

        #expect(deleter.deletedIds == ["old-id", "old-id"])
        #expect(storage.resetCount == 1)
        #expect(model.deleteErrorMessage == nil)
    }

    @Test("Without a deleter it falls back to the local reset")
    func noDeleterFallsBackToLocalReset() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let model = makeModel(storage: storage)

        let ok = await model.deleteServerDataAndStartOver()

        #expect(ok)
        #expect(storage.resetCount == 1)
        #expect(model.sessionId.hasPrefix("new-id-"))
    }

    @Test("Unreadable session id fails before contacting the server")
    func unreadableIdFailsEarly() async {
        let storage = FakeSessionStorage()
        storage.behavior = .throwOnCurrent(E())
        let deleter = FakeSessionDeleter()
        let model = makeModel(storage: storage, deleter: deleter)

        let ok = await model.deleteServerDataAndStartOver()

        #expect(!ok)
        #expect(deleter.deletedIds.isEmpty)
        #expect(storage.resetCount == 0)
        #expect(model.deleteErrorMessage != nil)
    }

    @Test("Local reset failing after a successful server delete reports an error")
    func localResetFailureAfterServerDelete() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        storage.behavior = .throwOnReset(E())
        let deleter = FakeSessionDeleter()
        let model = makeModel(storage: storage, deleter: deleter)

        let ok = await model.deleteServerDataAndStartOver()

        #expect(!ok)
        #expect(deleter.deletedIds == ["old-id"])
        #expect(model.deleteErrorMessage?.contains("deleted from the server") == true)
        #expect(model.isDeleteInProgress == false)
    }

    @Test("A second call while the server call is in flight is a no-op")
    func concurrentCallIsNoOp() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.delay = .milliseconds(200)
        let model = makeModel(storage: storage, deleter: deleter)

        async let first = model.deleteServerDataAndStartOver()
        // Let the first call pass its guard and suspend on the server call.
        var spins = 0
        while !model.isDeleteInProgress, spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        #expect(model.isDeleteInProgress)

        let second = await model.deleteServerDataAndStartOver()
        #expect(second == false)

        let firstResult = await first
        #expect(firstResult)
        #expect(deleter.deletedIds == ["old-id"])
        #expect(storage.resetCount == 1)
        #expect(model.isDeleteInProgress == false)
    }

    @Test("clearDeleteError clears the message")
    func clearsDeleteError() async {
        let storage = FakeSessionStorage()
        let deleter = FakeSessionDeleter()
        deleter.error = E()
        let model = makeModel(storage: storage, deleter: deleter)

        _ = await model.deleteServerDataAndStartOver()
        #expect(model.deleteErrorMessage != nil)
        model.clearDeleteError()
        #expect(model.deleteErrorMessage == nil)
    }

    @Test("canCopySessionId is false for empty and Unavailable ids")
    func canCopySessionId() {
        let storage = FakeSessionStorage()
        storage.storedId = "abc123"
        let model = makeModel(storage: storage)
        #expect(model.canCopySessionId == false)
        model.loadSessionId()
        #expect(model.canCopySessionId == true)

        let broken = FakeSessionStorage()
        broken.behavior = .throwOnCurrent(E())
        let brokenModel = makeModel(storage: broken)
        brokenModel.loadSessionId()
        #expect(brokenModel.sessionId == "Unavailable")
        #expect(brokenModel.canCopySessionId == false)
    }
}

@Suite("SettingsViewModel consent withdrawal")
@MainActor
struct SettingsViewModelConsentTests {
    struct E: Error {}

    @Test("withdrawConsent deletes, resets, and notifies the host on success")
    func withdrawSucceeds() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        let model = makeModel(storage: storage, deleter: deleter)
        var notified = 0
        model.onConsentWithdrawn = { notified += 1 }

        let ok = await model.withdrawConsent()

        #expect(ok)
        #expect(notified == 1)
        #expect(deleter.deletedIds == ["old-id"])
        #expect(storage.resetCount == 1)
    }

    @Test("withdrawConsent cancels the in-flight reply before the server delete")
    func withdrawCancelsInFlightFirst() async {
        let deleter = FakeSessionDeleter()
        let log = CallLog()
        deleter.onDelete = { log.append("deleteSession") }
        let model = makeModel(deleter: deleter)
        model.cancelInFlight = { log.append("cancelInFlight") }

        #expect(await model.withdrawConsent() == true)
        #expect(log.entries == ["cancelInFlight", "deleteSession"])
    }

    @Test("withdrawConsent does NOT notify the host when the server delete fails")
    func withdrawFailureDoesNotNotify() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.error = E()
        let model = makeModel(storage: storage, deleter: deleter)
        var notified = 0
        model.onConsentWithdrawn = { notified += 1 }

        let ok = await model.withdrawConsent()

        #expect(!ok)
        #expect(notified == 0)
        #expect(storage.resetCount == 0)
        #expect(model.deleteErrorMessage != nil)
    }

    @Test("withdrawConsent works without a host callback")
    func withdrawWithoutCallback() async {
        let storage = FakeSessionStorage()
        let model = makeModel(storage: storage, deleter: FakeSessionDeleter())
        #expect(await model.withdrawConsent() == true)
    }

    @Test("withdrawConsentLocally resets the device without a server call and notifies")
    func withdrawLocally() async {
        let storage = FakeSessionStorage()
        storage.storedId = "old-id"
        let deleter = FakeSessionDeleter()
        deleter.error = E()
        let model = makeModel(storage: storage, deleter: deleter)
        var notified = 0
        model.onConsentWithdrawn = { notified += 1 }

        let ok = await model.withdrawConsentLocally()

        #expect(ok)
        #expect(notified == 1)
        #expect(deleter.deletedIds.isEmpty)
        #expect(storage.resetCount == 1)
        #expect(model.sessionId.hasPrefix("new-id-"))
    }

    @Test("withdrawConsentLocally does not notify when the local reset fails")
    func withdrawLocallyFailure() async {
        let storage = FakeSessionStorage()
        storage.behavior = .throwOnReset(E())
        let model = makeModel(storage: storage)
        var notified = 0
        model.onConsentWithdrawn = { notified += 1 }

        let ok = await model.withdrawConsentLocally()

        #expect(!ok)
        #expect(notified == 0)
        #expect(model.resetErrorMessage != nil)
    }
}
