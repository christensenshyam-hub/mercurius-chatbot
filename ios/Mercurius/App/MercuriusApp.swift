import SwiftUI
import AppFeature

@main
struct MercuriusApp: App {
    @StateObject private var environment = AppEnvironment(environment: .production)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
            // NOTE: do NOT set `.preferredColorScheme` here. `RootView` applies
            // the user's choice from `ThemePreferenceStore` (System/Light/Dark).
            // A `.preferredColorScheme(nil)` at this level is nearer the window
            // root and OVERRIDES RootView's value, pinning the app to the system
            // appearance — which made the Settings theme toggle appear to do
            // nothing.
        }
    }
}
