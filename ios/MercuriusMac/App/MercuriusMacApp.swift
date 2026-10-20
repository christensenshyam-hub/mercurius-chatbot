import SwiftUI
import AppFeature

/// The native Mac app: one window and the Settings window, both composed in
/// AppFeature like the iPhone app's.
///
/// - The window hosts `RootView` — the same bootstrap as iOS (session id,
///   then the consent gate before anything reaches the server), which on the
///   Mac lands in `MacShellView`, a NavigationSplitView of Today, the path by
///   unit and the chats.
/// - `MacCommands` puts New Chat on ⌘N (the app is one window, so it takes
///   New Window's place) and Today / Learning Path / Chat on ⌘1–⌘3.
/// - Settings (⌘,) is the iPhone's Settings screen, wired to the window.
@main
struct MercuriusMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment(environment: .production)

    var body: some Scene {
        WindowGroup("Mercurius", id: "main") {
            RootView()
                .environmentObject(environment)
                // Any smaller and the sidebar and a lesson stop fitting side by side.
                .frame(minWidth: 860, minHeight: 600)
            // NOTE: no `.preferredColorScheme` here — `RootView` applies the
            // student's System/Light/Dark choice, and one nearer the window
            // root would override it (see MercuriusApp on iOS).
        }
        .defaultSize(width: 1180, height: 800)
        .commands {
            MacCommands(shell: environment.macShell)
        }

        Settings {
            MacSettingsView()
                .environmentObject(environment)
        }
    }
}
