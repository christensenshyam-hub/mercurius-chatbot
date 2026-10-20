import SwiftUI
import AppFeature

/// The native Mac app: the main window, the Settings window and the Help
/// window, all composed in AppFeature like the iPhone app's screens.
///
/// - The main window hosts `RootView` — the same bootstrap as iOS (session
///   id, then the consent gate before anything reaches the server), which on
///   the Mac lands in `MacShellView`, a NavigationSplitView of Today, the
///   path by unit and the chats.
/// - `MacCommands` is the menu bar: New Chat (⌘N), the modes (⌘1–⌘3), Retry
///   (⌘R), Explain More (⇧⌘E), Attach Image… (⇧⌘A), Today / Learning Path /
///   Chat (⌥⌘1–⌥⌘3) and Help (⌘?).
/// - Settings (⌘,) is `MacSettingsView`: General, Privacy, About.
/// - Help is `MacHelpView`: how Mercurius teaches, the Mac's shortcuts, and
///   where to get help.
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
