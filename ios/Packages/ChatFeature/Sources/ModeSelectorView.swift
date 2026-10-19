import SwiftUI
import DesignSystem
import NetworkingKit

/// The three Mercurius modes. A row of pills at standard text sizes; at
/// accessibility sizes a single "Mode: Socratic" menu, because three pills
/// side by side hyphenate or shrink to "So… De… Di…" (AUD-48). Tapping a
/// mode for the first time shows an explainer sheet; thereafter it switches
/// directly.
///
/// UI tests anchor on the "Debate" pill. At accessibility sizes it is an
/// item of the menu (`chat.modeMenu`), so it is reachable once the menu opens.
struct ModeSelectorView: View {
    @Bindable var model: ChatViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The description sheet presented the first time the user taps a
    /// mode. `nil` when no sheet is active. Set by `handleTap(...)`
    /// when the tapped mode hasn't been seen yet; cleared when the
    /// user acknowledges (or closes). `ModeDescription` is
    /// `Identifiable` so `.sheet(item:)` drives presentation directly
    /// off this binding without a separate `isPresented` flag.
    @State private var pendingDescription: ModeDescription?

    enum Layout: Equatable {
        case pills
        case menu
    }

    static func layout(for size: DynamicTypeSize) -> Layout {
        size.isAccessibilitySize ? .menu : .pills
    }

    /// The menu's visible title and VoiceOver label.
    static func menuTitle(for mode: ChatMode) -> String {
        "Mode: \(mode.displayName)"
    }

    static let menuIdentifier = "chat.modeMenu"

    var body: some View {
        Group {
            switch Self.layout(for: dynamicTypeSize) {
            case .pills: pillRow
            case .menu: modeMenu
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.vertical, BrandSpacing.sm)
        .alert(
            "Couldn't switch modes",
            isPresented: Binding(
                get: { model.modeSwitchError != nil },
                set: { if !$0 { model.clearModeSwitchError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.clearModeSwitchError() }
        } message: {
            Text(model.modeSwitchError ?? "")
        }
        .sheet(item: $pendingDescription) { description in
            ModeDescriptionSheet(description: description) {
                // Acknowledge handler: fires after the sheet dismisses
                // and the mode is marked seen — proceed into the mode.
                continueIntoMode(description.mode)
            }
        }
    }

    /// Three fixed modes — no scroll. Each pill takes an equal share of
    /// the row so the trio reads evenly spaced across the top.
    private var pillRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(ChatMode.allCases) { mode in
                pill(for: mode)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One control in place of the pills. The modes are a picker inside the
    /// menu, so VoiceOver and the menu's checkmark both say which is on.
    private var modeMenu: some View {
        let isSwitching = model.modeSwitchInFlight != nil
        return Menu {
            Picker("Mode", selection: Binding(
                get: { model.currentMode },
                set: { handleTap(mode: $0) }
            )) {
                ForEach(ChatMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Text(Self.menuTitle(for: model.currentMode))
                    .font(BrandFont.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSwitching {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(BrandFont.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.accentText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, BrandSpacing.sm)
            .padding(.horizontal, BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(BrandColor.surface,
                        in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .strokeBorder(BrandColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        // Same rule as the pills: no switching mid-reply or mid-switch.
        .disabled(isSwitching || isReplying)
        // Chrome above the reading area: it stops growing at AX3, where
        // "Mode: Socratic" still fits one line on an SE (at AX5 it took two
        // lines and 180 pt). A long press shows it large.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityShowsLargeContentViewer()
        .accessibilityLabel(Self.menuTitle(for: model.currentMode))
        .accessibilityHint("Shows the three chat modes")
        .accessibilityIdentifier(Self.menuIdentifier)
    }

    // MARK: - Pieces

    /// Whether a reply is currently being produced (sending or streaming).
    private var isReplying: Bool {
        switch model.phase {
        case .sending, .streaming: return true
        case .idle, .failed: return false
        }
    }

    private func pill(for mode: ChatMode) -> some View {
        let isActive = mode == model.currentMode
        let isPending = model.modeSwitchInFlight == mode

        return Button {
            handleTap(mode: mode)
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Text(mode.displayName)
                    .font(BrandFont.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                if isPending {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(labelColor(isActive: isActive))
            .padding(.vertical, 8)
            .padding(.horizontal, BrandSpacing.md)
            // Fill the equal-width column so the capsule itself stretches.
            .frame(maxWidth: .infinity)
            .background(background(isActive: isActive))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? Color.clear : BrandColor.border,
                        lineWidth: 1
                    )
            )
            .opacity(1)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        // Disabled while a switch is in flight AND while a reply is being
        // produced — switching workspaces mid-stream would abandon the
        // answer (switchMode also cancels defensively, but the pill
        // shouldn't invite it).
        .disabled((model.modeSwitchInFlight != nil && !isPending) || isReplying)
        .accessibilityLabel(accessibilityLabel(mode: mode, isActive: isActive))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func background(isActive: Bool) -> some View {
        if isActive {
            LinearGradient(
                colors: [BrandColor.userBubbleTop, BrandColor.userBubbleBottom],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            BrandColor.surface
        }
    }

    private func labelColor(isActive: Bool) -> Color {
        if isActive { return .white }
        return BrandColor.text
    }

    private func accessibilityLabel(mode: ChatMode, isActive: Bool) -> String {
        var label = mode.displayName
        if isActive { label += ", selected" }
        return label
    }

    // MARK: - Actions

    /// Tap flow per mode, first time vs. subsequent:
    ///
    /// - **First tap**: show the description sheet; `continueIntoMode(_:)`
    ///   runs after dismiss and performs the mode switch.
    /// - **Subsequent tap**: switch directly (no sheet).
    private func handleTap(mode: ChatMode) {
        if !ModeDescriptionStore.hasSeen(mode) {
            pendingDescription = ModeDescription.description(for: mode)
            return
        }
        Task { await model.switchMode(to: mode) }
    }

    /// Run after the description sheet is acknowledged. `markSeen`
    /// already happened inside the sheet's Got-it action, so this
    /// just performs the post-sheet side effect — select the mode.
    private func continueIntoMode(_ mode: ChatMode) {
        Task { await model.switchMode(to: mode) }
    }
}
