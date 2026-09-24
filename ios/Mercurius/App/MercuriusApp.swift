import SwiftUI
import UIKit
import UserNotifications
import AppFeature
import EngagementFeature

@main
struct MercuriusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The delegate must be in place before launch finishes, or the tap
        // that cold-launched the app is never delivered to the router.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }
}
