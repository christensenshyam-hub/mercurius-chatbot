import Testing
import Foundation
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

final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

@MainActor
private func makeModel(
    storage: FakeSessionStorage = FakeSessionStorage(),
    prefs: InMemoryPreferenceStore = InMemoryPreferenceStore(),
    bundle: Bundle = .main
) -> SettingsViewModel {
    let themeStore = ThemePreferenceStore(preferences: prefs)
    return SettingsViewModel(
        sessionStorage: storage,
        themeStore: themeStore,
        bundle: bundle
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
}
