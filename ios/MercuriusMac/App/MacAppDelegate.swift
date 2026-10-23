import AppKit
import AppFeature

/// App-level hooks SwiftUI's `App` doesn't offer.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Dark only (`BrandAppearance`), before the first window: the
            // menus, alerts and panels too, whatever the Mac's appearance.
            // The scenes also apply the dark scheme to their windows.
            NSApp.appearance = NSAppearance(named: .darkAqua)
            // Before launch finishes, as on iOS: a reminder clicked while
            // the app wasn't running is delivered to this delegate during
            // launch.
            MacAppSupport.installNotificationDelegate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MacSnapshot.startIfRequested()
        #endif
    }
}
