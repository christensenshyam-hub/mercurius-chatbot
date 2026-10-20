#if os(macOS)
import SwiftUI
import DesignSystem
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// The Mac window's sidebar: Today, the learning path by unit, and the chats
/// (New Chat plus the saved threads, newest first).
///
/// A click goes through `MacShellModel.show(_:)`, which closes any open
/// lesson and opens a saved thread; code that routes on its own (opening a
/// lesson under its unit) sets the selection directly and isn't undone here.
struct MacSidebar: View {
    @Bindable var shell: MacShellModel
    let progress: CurriculumProgressStore
    /// Ask to delete a saved thread (the shell confirms first).
    let onDelete: (ConversationSummary) -> Void

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Today", systemImage: "sun.max")
                    .tag(MacShellModel.Destination.today)
            }

            Section("Learning path") {
                ForEach(MercuriusCurriculum.units) { unit in
                    UnitRow(unit: unit, progress: progress)
                        .tag(MacShellModel.Destination.unit(unit.id))
                }
            }

            Section("Chats") {
                Button {
                    shell.newChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
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
    }

    /// Clicks route through the model; reads show what the detail shows.
    private var selection: Binding<MacShellModel.Destination?> {
        Binding(
            get: { shell.selection },
            set: { if let destination = $0 { shell.show(destination) } }
        )
    }
}

/// "Unit 1 · What AI is" with the unit's lessons done, or a seal once its
/// check is mastered.
private struct UnitRow: View {
    let unit: CurriculumFeature.Unit
    let progress: CurriculumProgressStore

    var body: some View {
        let done = progress.completedCount(in: unit)
        let total = unit.lessons.count
        let mastered = progress.isUnitMastered(unit.id)
        HStack(spacing: BrandSpacing.sm) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unit \(Self.number(unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(unit.title)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: mastered ? "checkmark.seal.fill" : "book.closed")
                    .foregroundStyle(mastered ? BrandColor.successText : BrandColor.accentText)
            }
            Spacer(minLength: 0)
            Text("\(done)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unit \(Self.number(unit)), \(unit.title). \(done) of \(total) lessons done\(mastered ? ", mastered" : "").")
    }

    static func number(_ unit: CurriculumFeature.Unit) -> Int { Int(unit.number) ?? 0 }
}

/// A saved thread: its title, and its mode underneath.
private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(conversation.title)
                .lineLimit(1)
            Text(mode)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode) chat. \(conversation.title).")
    }

    private var mode: String {
        ChatMode(rawValue: conversation.mode)?.displayName ?? conversation.mode.capitalized
    }
}
#endif
