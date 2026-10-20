#if os(macOS)
import SwiftUI
import ChatFeature
import NetworkingKit

/// The Mac menu bar.
///
/// - File: New Chat (⌘N) in place of New Window — the app is one window —
///   and Attach Image… (⇧⌘A).
/// - Chat: Socratic / Debate / Discussion (⌥⌘1 / ⌥⌘2 / ⌥⌘3), Retry (⌘R),
///   Explain More (⇧⌘E). The modes are on only while the free chat shows:
///   a lesson has no mode, and switching from one would close it.
/// - View: Today / Learning Path / Chat (⌘1 / ⌘2 / ⌘3, the sidebar's
///   destinations, as in Mail or Finder) and Progress (⌘4, the Progress
///   sheet) above the sidebar commands.
/// - Help: Mercurius Help (⌘?) opens the Help window; the support site,
///   feedback and support email follow.
///
/// Settings (⌘,) is the app menu's own, from the `Settings` scene.
///
/// Every item that touches the shell is off while the consent gate shows or
/// Settings is erasing the student's data (`MacShellModel.commandsBlocked`;
/// the model ignores the gate's anyway). Retry, Explain More and Attach
/// Image act on whichever chat or lesson the key window shows
/// (`ChatCommandTarget`), and are off when there is none.
public struct MacCommands: Commands {
    private let shell: MacShellModel

    @FocusedValue(\.chatCommandTarget) private var target
    @Environment(\.openWindow) private var openWindow

    public init(shell: MacShellModel) {
        self.shell = shell
    }

    /// The Help window's scene id (`MercuriusMacApp`).
    public static let helpWindowId = "help"

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { shell.newChat() }
                .keyboardShortcut("n")
                .disabled(shell.commandsBlocked)
            Button("Attach Image…") { target?.attachImage() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(shell.commandsBlocked || target?.canAttach != true)
        }

        CommandMenu("Chat") {
            ForEach(ChatMode.allCases) { mode in
                Toggle(mode.displayName, isOn: Binding(
                    get: { target?.currentMode == mode },
                    set: { _ in shell.requestMode(mode) }
                ))
                .keyboardShortcut(Self.modeKey(mode), modifiers: Self.modeModifiers)
                .disabled(!Self.modesEnabled(blocked: shell.commandsBlocked, chatMode: target?.currentMode))
            }
            Divider()
            Button("Retry") { target?.retry() }
                .keyboardShortcut("r")
                .disabled(shell.commandsBlocked || target?.canRetry != true)
            Button("Explain More") { target?.explainMore() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(shell.commandsBlocked || target?.canExplainMore != true)
        }

        SidebarCommands()

        CommandGroup(before: .sidebar) {
            Button("Today") { shell.show(.today) }
                .keyboardShortcut(Self.destinationKey(.today))
                .disabled(shell.commandsBlocked)
            Button("Learning Path") { shell.showPath() }
                .keyboardShortcut(Self.destinationKey(.path))
                .disabled(shell.commandsBlocked)
            Button("Chat") { shell.showChat() }
                .keyboardShortcut(Self.destinationKey(.chat))
                .disabled(shell.commandsBlocked)
            Button("Progress") { shell.showProgress() }
                .keyboardShortcut(Self.progressKey)
                .disabled(shell.commandsBlocked)
            Divider()
        }

        CommandGroup(replacing: .help) {
            // Static pages and links: fine before consent too (nothing here
            // talks to Mercurius's server).
            Button("Mercurius Help") { openWindow(id: Self.helpWindowId) }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            ForEach(MacHelpLinks.all) { link in
                Link(link.title, destination: link.url)
            }
        }
    }

    /// ⌥⌘1 Socratic, ⌥⌘2 Debate, ⌥⌘3 Discussion — the toolbar's order.
    static func modeKey(_ mode: ChatMode) -> KeyEquivalent {
        let index = ChatMode.allCases.firstIndex(of: mode) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }

    static let modeModifiers: EventModifiers = [.command, .option]

    /// The View menu's destinations, in the sidebar's order.
    enum Destination: CaseIterable { case today, path, chat }

    /// ⌘1 Today, ⌘2 Learning Path, ⌘3 Chat (plain ⌘-number, as the Mac's
    /// sidebar apps use it).
    static func destinationKey(_ destination: Destination) -> KeyboardShortcut {
        let index = Destination.allCases.firstIndex(of: destination) ?? 0
        return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
    }

    /// ⌘4: View ▸ Progress, after the three destinations (the toolbar's
    /// Progress button; the streak left the toolbar for it).
    static let progressKey = KeyboardShortcut("4", modifiers: .command)

    /// The mode items work only on the free chat in front (a lesson's
    /// command target has no mode), and never behind the gate or mid-erase.
    nonisolated static func modesEnabled(blocked: Bool, chatMode: ChatMode?) -> Bool {
        !blocked && chatMode != nil
    }
}

/// The support links the Help menu, the Help window and Settings share
/// (the same addresses as the iPhone's Settings ▸ About).
enum MacHelpLinks {
    struct Item: Identifiable {
        let title: String
        let url: URL
        var id: String { title }
    }

    static let faq = Item(title: "Help & FAQ", url: URL(string: "https://trymercurius.com/support")!)
    static let feedback = Item(title: "Send Feedback", url: URL(string: "https://trymercurius.com/feedback")!)
    static let support = Item(title: "Contact Support", url: URL(string: "mailto:support@trymercurius.com")!)
    static let terms = Item(title: "Terms of Use", url: URL(string: "https://trymercurius.com/terms")!)
    static let privacy = Item(title: "Privacy Policy", url: URL(string: "https://trymercurius.com/privacy")!)

    /// The Help menu's links.
    static let all: [Item] = [faq, feedback, support]
}
#endif
