import SwiftUI
import DesignSystem
import NetworkingKit
import PersistenceKit

/// Reads-from-store list of every saved conversation, grouped by
/// mode. Tapping a row asks the host to reopen that conversation —
/// which fires `ChatViewModel.openConversation(id:)` and dismisses
/// the chat-history surface so the user lands directly back in the
/// chat with the chosen thread loaded.
///
/// Reads happen through `ChatViewModel.archivedConversations()` so
/// the view doesn't need its own store reference; the existing
/// composition pattern (host owns store, passes adapter closures)
/// is preserved.
public struct ChatHistoryView: View {

    /// Closure the host wires to either `chatModel.openConversation(id:)`
    /// (and dismiss the Settings sheet) or — in unit/preview contexts
    /// — a no-op.
    private let onSelect: @MainActor (UUID) -> Void

    /// Closure the host wires to `chatModel.deleteConversation(id:)`
    /// for swipe-to-delete + the destructive confirm sheet. Returns
    /// nothing; the list re-fetches from the provider after the call.
    private let onDelete: @MainActor (UUID) -> Void

    /// Pull function for the underlying conversation list. Closure
    /// rather than a held reference so SwiftUI re-fetches every time
    /// the view's `body` runs (which is fine — the call is cheap and
    /// avoids stale snapshots after a delete).
    private let load: @MainActor () -> [ConversationSummary]

    /// Filter pill state. `nil` = "All".
    @State private var filter: ChatMode? = nil

    /// Pending-delete target shown in a destructive confirmation sheet.
    /// Optional so absence drives presentation via `.confirmationDialog`.
    @State private var pendingDelete: ConversationSummary? = nil

    public init(
        load: @escaping @MainActor () -> [ConversationSummary],
        onSelect: @escaping @MainActor (UUID) -> Void,
        onDelete: @escaping @MainActor (UUID) -> Void
    ) {
        self.load = load
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        let conversations = filteredConversations
        Group {
            if conversations.isEmpty {
                emptyState
            } else {
                list(conversations: conversations)
            }
        }
        .navigationTitle("Chat History")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                filterMenu
            }
        }
        .background(BrandColor.background)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { convo in
            Button("Delete", role: .destructive) {
                onDelete(convo.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { convo in
            Text("\"\(convo.title)\" will be permanently removed from this device. This can't be undone.")
        }
    }

    // MARK: - Filter menu

    /// Compact mode filter at the navigation title's slot. Populated
    /// only with modes that currently have at least one saved
    /// conversation so the filter doesn't surface useless rows.
    private var filterMenu: some View {
        let availableModes = Set(load().compactMap { ChatMode(rawValue: $0.mode) })

        return Menu {
            Button("All modes", action: { filter = nil })
            if !availableModes.isEmpty {
                Divider()
                ForEach(ChatMode.allCases.filter(availableModes.contains)) { mode in
                    Button(mode.displayName, action: { filter = mode })
                }
            }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Text(filter?.displayName ?? "All modes")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .accessibilityLabel("Filter by mode")
        .accessibilityValue(filter?.displayName ?? "All modes")
    }

    private var filteredConversations: [ConversationSummary] {
        let all = load()
        guard let filter else { return all }
        return all.filter { $0.mode == filter.rawValue }
    }

    // MARK: - List

    private func list(conversations: [ConversationSummary]) -> some View {
        List {
            ForEach(conversations) { convo in
                Button {
                    onSelect(convo.id)
                } label: {
                    ChatHistoryRow(conversation: convo)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = convo
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(BrandColor.background)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(BrandColor.textSecondary)
                .accessibilityHidden(true)
            Text(filter == nil ? "No previous chats yet" : "No \(filter!.displayName) chats yet")
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
            Text("Start a conversation and it'll show up here.")
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, BrandSpacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

private struct ChatHistoryRow: View {
    let conversation: ConversationSummary

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                modeChip
                Spacer()
                Text(Self.timestampFormatter.localizedString(for: conversation.updatedAt, relativeTo: Date()))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityLabel("Last updated \(conversation.updatedAt.formatted())")
            }

            Text(conversation.title)
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)
                .lineLimit(2)

            if !conversation.preview.isEmpty {
                Text(conversation.preview)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleSummary)
    }

    private var modeChip: some View {
        Text(displayMode)
            .font(BrandFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(BrandColor.accent)
            .padding(.vertical, 2)
            .padding(.horizontal, BrandSpacing.sm)
            .background(BrandColor.accent.opacity(0.12))
            .clipShape(Capsule())
    }

    private var displayMode: String {
        ChatMode(rawValue: conversation.mode)?.displayName ?? conversation.mode.capitalized
    }

    private var accessibleSummary: String {
        // VoiceOver-friendly: mode, title, message count, recency.
        "\(displayMode) Mode chat. \(conversation.title). \(conversation.messageCount) messages. Updated \(conversation.updatedAt.formatted())"
    }
}

// MARK: - Previews

#Preview("Populated") {
    let now = Date()
    let samples: [ConversationSummary] = [
        ConversationSummary(
            id: UUID(), mode: ChatMode.socratic.rawValue,
            title: "How does an LLM actually work?",
            preview: "It depends what you mean by 'work' — the simplest answer is next-token prediction…",
            messageCount: 6,
            createdAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-60)
        ),
        ConversationSummary(
            id: UUID(), mode: ChatMode.debate.rawValue,
            title: "Argue against the claim that AI will replace teachers",
            preview: "Even granting that AI tutors can scale, classroom teachers do work that's not just instruction…",
            messageCount: 4,
            createdAt: now.addingTimeInterval(-7200),
            updatedAt: now.addingTimeInterval(-3600)
        ),
    ]
    return NavigationStack {
        ChatHistoryView(
            load: { samples },
            onSelect: { _ in },
            onDelete: { _ in }
        )
    }
}

#Preview("Empty") {
    NavigationStack {
        ChatHistoryView(
            load: { [] },
            onSelect: { _ in },
            onDelete: { _ in }
        )
    }
}
