import AppKit
import AppFeature

/// App-level hooks SwiftUI's `App` doesn't offer.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before launch finishes, as on iOS: a reminder clicked while the
        // app wasn't running is delivered to this delegate during launch.
        MainActor.assumeIsolated {
            MacAppSupport.installNotificationDelegate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MacSnapshot.startIfRequested()
        #endif
    }
}
