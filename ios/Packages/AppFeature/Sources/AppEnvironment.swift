import Foundation
import NetworkingKit
import SettingsFeature

/// The app's composition root — a single place where singletons are
/// constructed and injected into feature modules. Features never reach
/// for a singleton directly; they take their dependencies as inputs.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let apiClient: APIClient
    public let sessionIdentity: SessionIdentity

    /// App-wide theme preference. Observed by `RootView` so the chosen
    /// color scheme propagates everywhere the moment the user changes
    /// it in Settings.
    public let themeStore: ThemePreferenceStore

    public init(environment: APIEnvironment = .production) {
        let identity = SessionIdentity()
        self.sessionIdentity = identity
        self.apiClient = APIClient(
            environment: environment,
            sessionIdentity: identity
        )
        self.themeStore = ThemePreferenceStore()
    }
}
