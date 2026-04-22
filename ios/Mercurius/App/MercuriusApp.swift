import SwiftUI
import AppFeature

@main
struct MercuriusApp: App {
    @StateObject private var environment = AppEnvironment(environment: .production)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(nil)  // respect system setting
        }
    }
}
