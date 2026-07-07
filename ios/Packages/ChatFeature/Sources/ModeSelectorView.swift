import SwiftUI
import DesignSystem
import NetworkingKit

/// Horizontal pill group for switching between the three Mercurius
/// modes. Tapping a mode for the first time shows an explainer sheet;
/// thereafter it switches directly.
struct ModeSelectorView: View {
    @Bindable var model: ChatViewModel

    /// The description sheet presented the first time the user taps a
    /// mode. `nil` when no sheet is active. Set by `handleTap(...)`
    /// when the tapped mode hasn't been seen yet; cleared when the
    /// user acknowledges (or closes). `ModeDescription` is
    /// `Identifiable` so `.sheet(item:)` drives presentation directly
    /// off this binding without a separate `isPresented` flag.
    @State private var pendingDescription: ModeDescription?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(ChatMode.allCases) { mode in
                    pill(for: mode)
                }
            }
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm)
        }
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
