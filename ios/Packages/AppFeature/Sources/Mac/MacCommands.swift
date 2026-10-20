#if os(macOS)
import SwiftUI

/// The Mac menu bar: File ▸ New Chat (⌘N) in place of New Window — the app
/// is one window — and View ▸ Today / Learning Path / Chat (⌘1–⌘3) above the
/// sidebar commands. Every item is off while the consent gate shows (and
/// `MacShellModel` ignores them then anyway).
public struct MacCommands: Commands {
    private let shell: MacShellModel

    public init(shell: MacShellModel) {
        self.shell = shell
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { shell.newChat() }
                .keyboardShortcut("n")
                .disabled(shell.isGated)
        }

        SidebarCommands()

        CommandGroup(before: .sidebar) {
            Button("Today") { shell.show(.today) }
                .keyboardShortcut("1")
                .disabled(shell.isGated)
            Button("Learning Path") { shell.showPath() }
                .keyboardShortcut("2")
                .disabled(shell.isGated)
            Button("Chat") { shell.showChat() }
                .keyboardShortcut("3")
                .disabled(shell.isGated)
            Divider()
        }
    }
}
#endif
