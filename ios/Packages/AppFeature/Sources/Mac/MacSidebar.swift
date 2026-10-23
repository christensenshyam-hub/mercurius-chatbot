#if os(macOS)
import SwiftUI
import DesignSystem
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// The Mac window's sidebar: Today, the two courses by unit — "Basics" and
/// "Deep dive", each a section that folds away, the learner's own course
/// first (BEGINNER_GUIDE §2.1) — and the chats: New Chat, then the saved
/// threads, newest first.
///
/// A click goes through `MacShellModel.select(_:)`, which closes any open
/// lesson and opens a saved thread; code that routes on its own (opening a
/// lesson under its unit) sets the selection directly and isn't undone here.
///
/// Night Studio (SPEC.md §5.0): the rows keep the system's type, height and
/// selection; secondary text (counts, a chat's mode, section headers) is
/// Night's `ink3` — the system's secondary label is 3.86:1 on the light
/// sidebar — and turns to the system's own on a selected row. On macOS 26
/// the sidebar is the system's glass, with Today's canvas extended under it;
/// on macOS 14–25, every CI build, and under Reduce Transparency or Increase
/// Contrast it is an opaque `Night.sidebar`.
///
/// New Chat is a row, not a button: while the chat shows a thread with no
/// saved message yet, that row is the thread's (`unsavedChatId`) and is
/// highlighted; otherwise selecting it starts one. The Delete key asks to
/// delete the selected saved thread, through the same confirmation as the
/// context menu.
struct MacSidebar: View {
    @Bindable var shell: MacShellModel
    let progress: CurriculumProgressStore
    /// The learner's course, which section comes first. nil: the Deep dive.
    var track: CurriculumTrack = .deepDive
    /// Ask to delete a saved thread (the shell confirms first).
    let onDelete: (ConversationSummary) -> Void

    /// The Deep dive's section is open (kept across launches; the key is
    /// from when it was the only "Learning path").
    @AppStorage("mac.sidebar.pathExpanded") private var pathExpanded = true
    /// The Basics section is open (kept across launches).
    @AppStorage("mac.sidebar.basicsExpanded") private var basicsExpanded = true
    @NightSettings private var night

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .tag(MacShellModel.Destination.today)
            }

            ForEach(Self.sectionOrder(first: track), id: \.self) { course in
                Section(isExpanded: course == .basics ? $basicsExpanded : $pathExpanded) {
                    ForEach(course.units) { unit in
                        UnitRow(unit: unit, progress: progress, showsMastery: course.hasUnitTests)
                            .tag(MacShellModel.Destination.unit(unit.id))
                    }
                } header: {
                    SectionHeader(title: course.displayName)
                }
            }

            Section {
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
            } header: {
                SectionHeader(title: "Chats")
            }
        }
        .listStyle(.sidebar)
        .nightSidebarBackground(night)
        .onDeleteCommand {
            if let conversation = Self.deletableConversation(selection: shell.selection,
                                                            in: shell.conversations) {
                onDelete(conversation)
            }
        }
    }

    /// The courses' sections, the learner's own first.
    nonisolated static func sectionOrder(first: CurriculumTrack) -> [CurriculumTrack] {
        [first] + CurriculumTrack.allCases.filter { $0 != first }
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

/// A sidebar section's title in Night's `ink3`.
private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(Night.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Secondary text on a sidebar row: Night's `ink3`, or the system's own
/// secondary label on a selected row (it turns light on the selection's
/// fill, where `ink3` would vanish).
private struct SidebarSecondary: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        content.foregroundStyle(prominence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(Night.ink3))
    }
}

/// A unit: its number in the icon, its title, and its lessons done — or a
/// seal once its check is mastered. One line per unit where the title
/// fits, so the chats below stay in view.
private struct UnitRow: View {
    let unit: CurriculumFeature.Unit
    let progress: CurriculumProgressStore
    /// Basics has no unit checks, so no seal.
    var showsMastery = true
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let done = progress.completedCount(in: unit)
        let total = unit.lessons.count
        let mastered = showsMastery && progress.isUnitMastered(unit.id)
        HStack(spacing: BrandSpacing.sm) {
            Label {
                Text(unit.title)
                    .lineLimit(2)
            } icon: {
                Image(systemName: MacSidebar.unitSymbol(number: Self.number(unit), mastered: mastered))
                    .foregroundStyle(iconStyle(mastered: mastered))
            }
            Spacer(minLength: 0)
            Text("\(done)/\(total)")
                .font(.caption.monospacedDigit())
                .modifier(SidebarSecondary())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MacSidebar.unitAccessibilityLabel(
            number: Self.number(unit), title: unit.title, done: done, total: total, mastered: mastered))
    }

    static func number(_ unit: CurriculumFeature.Unit) -> Int { MacSidebar.unitNumber(unit) }

    /// Night's accent (a mastered seal in its green); white on a selected
    /// row, like the row's text.
    private func iconStyle(mastered: Bool) -> AnyShapeStyle {
        if prominence == .increased { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(mastered ? Night.successText : Night.accentText)
    }
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
                    .modifier(SidebarSecondary())
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
