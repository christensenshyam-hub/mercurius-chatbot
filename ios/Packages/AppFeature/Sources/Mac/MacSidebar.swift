#if os(macOS)
import SwiftUI
import DesignSystem
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// The Mac window's sidebar: Today, the learning path by unit (a section
/// that folds away), and the chats — New Chat, then the saved threads,
/// newest first.
///
/// A click goes through `MacShellModel.select(_:)`, which closes any open
/// lesson and opens a saved thread; code that routes on its own (opening a
/// lesson under its unit) sets the selection directly and isn't undone here.
///
/// New Chat is a row, not a button: while the chat shows a thread with no
/// saved message yet, that row is the thread's (`unsavedChatId`) and is
/// highlighted; otherwise selecting it starts one. The Delete key asks to
/// delete the selected saved thread, through the same confirmation as the
/// context menu.
struct MacSidebar: View {
    @Bindable var shell: MacShellModel
    let progress: CurriculumProgressStore
    /// Ask to delete a saved thread (the shell confirms first).
    let onDelete: (ConversationSummary) -> Void

    /// The Learning path section is open (kept across launches).
    @AppStorage("mac.sidebar.pathExpanded") private var pathExpanded = true

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .tag(MacShellModel.Destination.today)
            }

            Section("Learning path", isExpanded: $pathExpanded) {
                ForEach(MercuriusCurriculum.units) { unit in
                    UnitRow(unit: unit, progress: progress)
                        .tag(MacShellModel.Destination.unit(unit.id))
                }
            }

            Section("Chats") {
                Label("New Chat", systemImage: "square.and.pencil")
                    .tag(MacShellModel.Destination.chat(shell.unsavedChatId))
                    .help("Start a new chat (⌘N)")

                ForEach(shell.conversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(MacShellModel.Destination.chat(conversation.id))
                        .contextMenu {
                            Button("Delete Chat…", role: .destructive) { onDelete(conversation) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let conversation = Self.deletableConversation(selection: shell.selection,
                                                            in: shell.conversations) {
                onDelete(conversation)
            }
        }
    }

    /// The saved thread the Delete key would delete: the selected row's, if
    /// it is a saved thread.
    nonisolated static func deletableConversation(selection: MacShellModel.Destination?,
                                                  in conversations: [ConversationSummary]) -> ConversationSummary? {
        guard case .chat(let id?) = selection else { return nil }
        return conversations.first { $0.id == id }
    }

    /// Clicks route through the model; reads show what the detail shows.
    private var selection: Binding<MacShellModel.Destination?> {
        Binding(
            get: { shell.selection },
            set: { shell.select($0) }
        )
    }

    /// VoiceOver's reading of a unit row.
    nonisolated static func unitAccessibilityLabel(number: Int, title: String, done: Int, total: Int, mastered: Bool) -> String {
        "Unit \(number), \(title). \(done) of \(total) lessons done\(mastered ? ", mastered" : "")."
    }

    /// A saved thread's mode, as its row's second line says it. A mode this
    /// build doesn't know (the betas' "direct") reads as its stored name.
    nonisolated static func modeName(_ raw: String) -> String {
        ChatMode(rawValue: raw)?.displayName ?? raw.capitalized
    }

    /// The sidebar's unit number: the unit's own number, 0 if it has none.
    nonisolated static func unitNumber(_ unit: CurriculumFeature.Unit) -> Int { Int(unit.number) ?? 0 }

    /// A unit row's icon: its number in a circle (SF Symbols has 0–50), a
    /// seal once mastered.
    nonisolated static func unitSymbol(number: Int, mastered: Bool) -> String {
        if mastered { return "checkmark.seal.fill" }
        return (1...50).contains(number) ? "\(number).circle" : "book.closed"
    }
}

/// A unit: its number in the icon, its title, and its lessons done — or a
/// seal once its check is mastered. One line per unit where the title
/// fits, so the chats below stay in view.
private struct UnitRow: View {
    let unit: CurriculumFeature.Unit
    let progress: CurriculumProgressStore

    var body: some View {
        let done = progress.completedCount(in: unit)
        let total = unit.lessons.count
        let mastered = progress.isUnitMastered(unit.id)
        HStack(spacing: BrandSpacing.sm) {
            Label {
                Text(unit.title)
                    .lineLimit(2)
            } icon: {
                Image(systemName: MacSidebar.unitSymbol(number: Self.number(unit), mastered: mastered))
                    .foregroundStyle(mastered ? BrandColor.successText : BrandColor.accentText)
            }
            Spacer(minLength: 0)
            Text("\(done)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MacSidebar.unitAccessibilityLabel(
            number: Self.number(unit), title: unit.title, done: done, total: total, mastered: mastered))
    }

    static func number(_ unit: CurriculumFeature.Unit) -> Int { MacSidebar.unitNumber(unit) }
}

/// A saved thread: a chat bubble, its title, and its mode underneath —
/// lined up with the rows above it.
private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.title)
                    .lineLimit(1)
                Text(mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "bubble.left")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode) chat. \(conversation.title).")
    }

    private var mode: String { MacSidebar.modeName(conversation.mode) }
}
#endif
