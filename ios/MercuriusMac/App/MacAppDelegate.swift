import AppKit

/// App-level hooks SwiftUI's `App` doesn't offer.
///
/// Reminders (the `UNUserNotificationCenter` delegate the iPhone app installs
/// here) aren't on the Mac yet — see docs/mac-app/PLAN.md.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MacSnapshot.startIfRequested()
        #endif
    }
}
