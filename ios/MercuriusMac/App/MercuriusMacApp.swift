import SwiftUI
import AppFeature

/// The native Mac app: the main window, the Settings window and the Help
/// window, all composed in AppFeature like the iPhone app's screens.
///
/// - The main window hosts `RootView` — the same bootstrap as iOS (session
///   id, then the consent gate before anything reaches the server), which on
///   the Mac lands in `MacShellView`, a NavigationSplitView of Today, the
///   path by unit and the chats. It is a single `Window`, not a
///   `WindowGroup`: everything in it shares one shell model and one chat, so
///   a second window would only mirror the first (and re-run its launch
///   work). Closing it keeps the app running; the Dock icon or Window ▸
///   Mercurius brings it back.
/// - `MacCommands` is the menu bar: New Chat (⌘N), Today / Learning Path /
///   Chat (⌘1–⌘3), the modes (⌥⌘1–⌥⌘3), Retry (⌘R), Explain More (⇧⌘E),
///   Attach Image… (⇧⌘A) and Help (⌘?).
/// - Settings (⌘,) is `MacSettingsView`: General, Privacy, About.
/// - Help is `MacHelpView`: how Mercurius teaches, the Mac's shortcuts, and
///   where to get help.
@main
struct MercuriusMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment(environment: .production)

    var body: some Scene {
        Window("Mercurius", id: "main") {
            RootView()
                .environmentObject(environment)
                // Narrow enough to tile beside a browser on a 13-inch
                // MacBook (half of its 1440–1470 pt screen). Below the
                // sidebar plus the detail's minimum, the sidebar folds away
                // (⌃⌘S brings it back).
                .frame(minWidth: 700, minHeight: 600)
                #if DEBUG
                .background(MacDebugWindows())
                #endif
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

        Window("Mercurius Help", id: MacCommands.helpWindowId) {
            MacHelpView()
                .environmentObject(environment)
        }
        .defaultSize(width: 600, height: 640)
        .windowResizability(.contentMinSize)
    }
}

#if DEBUG
/// DEBUG `-MacOpenWindow help|settings`: open that window at launch, for the
/// screenshot harness (`MacSnapshot`), which then photographs it.
private struct MacDebugWindows: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .onAppear {
                switch UserDefaults.standard.string(forKey: "MacOpenWindow") {
                case "help":
                    openWindow(id: MacCommands.helpWindowId)
                case "settings":
                    openSettings()
                default:
                    break
                }
            }
    }
}
#endif
