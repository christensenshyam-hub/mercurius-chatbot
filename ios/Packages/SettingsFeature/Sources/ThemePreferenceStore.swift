import SwiftUI
import Observation

/// Observable store for the theme preference earlier versions offered.
///
/// No longer read: both apps are dark only (`BrandAppearance`), so a stored
/// System or Light choice is ignored, and Settings no longer shows the
/// picker. `AppEnvironment` still constructs one and `SettingsViewModel`
/// still holds it, so their initialisers don't change.
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
