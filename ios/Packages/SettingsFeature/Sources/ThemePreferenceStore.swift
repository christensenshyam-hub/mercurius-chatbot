import SwiftUI
import Observation

/// Observable, app-wide source of truth for the user's theme preference.
///
/// `AppEnvironment` constructs one and applies the selected color
/// scheme at the root of the app. `SettingsViewModel` writes through
/// the same store so changes take effect immediately.
///
/// Values are persisted via `PreferenceStore` — `UserDefaults` in
/// production, an in-memory fake in tests.
@MainActor
@Observable
public final class ThemePreferenceStore {
    public var theme: ThemePreference {
        didSet { preferences.set(theme.rawValue, for: Keys.theme) }
    }

    private let preferences: PreferenceStore

    public init(preferences: PreferenceStore = UserDefaultsPreferenceStore()) {
        self.preferences = preferences
        let stored = preferences.string(for: Keys.theme)
            .flatMap(ThemePreference.init(rawValue:))
        self.theme = stored ?? .system
    }

    private enum Keys {
        static let theme = "com.mayoailiteracy.mercurius.theme"
    }
}
