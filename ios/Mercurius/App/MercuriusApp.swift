import SwiftUI
import UIKit
import UserNotifications
import AppFeature
import DesignSystem
import EngagementFeature

@main
struct MercuriusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment(environment: .production)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                // Dark only (`BrandAppearance`): the same scheme `RootView`
                // applies, here at the window's root too. Info.plist's
                // `UIUserInterfaceStyle = Dark` covers the launch and the
                // system's own sheets and keyboard. (There is no student
                // choice any more for this to override.)
                .preferredColorScheme(BrandAppearance.colorScheme)
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
