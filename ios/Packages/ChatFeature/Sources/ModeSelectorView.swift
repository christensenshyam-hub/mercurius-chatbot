import SwiftUI
import DesignSystem
import NetworkingKit

/// Horizontal pill group for switching between the four Mercurius
/// modes. Direct Mode shows a lock badge until unlocked — tapping it
/// while locked triggers an explainer alert rather than silently
/// failing.
struct ModeSelectorView: View {
    @Bindable var model: ChatViewModel

    @State private var showLockedAlert = false

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
        .alert("Direct Mode is locked", isPresented: $showLockedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Chat with Mercurius in Socratic Mode. When it sees enough critical thinking, it'll run a short test — pass it and Direct Mode unlocks.")
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
                // and the mode is marked seen. For unlocked modes we
                // proceed into the mode; for locked ones the user
                // learned what it is — no selection happens but the
                // subsequent-tap locked alert will fire if they try
                // again.
                continueIntoMode(description.mode)
            }
        }
    }

    // MARK: - Pieces

    private func pill(for mode: ChatMode) -> some View {
        let isActive = mode == model.currentMode
        let isLocked = mode.requiresUnlock && !model.isUnlocked
        let isPending = model.modeSwitchInFlight == mode

        return Button {
            handleTap(mode: mode, isLocked: isLocked)
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Text(mode.displayName)
                    .font(BrandFont.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                if isPending {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(labelColor(isActive: isActive, isLocked: isLocked))
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
            .opacity(isLocked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(model.modeSwitchInFlight != nil && !isPending)
        .accessibilityLabel(accessibilityLabel(mode: mode, isActive: isActive, isLocked: isLocked))
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

    private func labelColor(isActive: Bool, isLocked: Bool) -> Color {
        if isActive { return .white }
        if isLocked { return BrandColor.textSecondary }
        return BrandColor.text
    }

    private func accessibilityLabel(mode: ChatMode, isActive: Bool, isLocked: Bool) -> String {
        var label = mode.displayName
        if isLocked { label += ", locked" }
        if isActive { label += ", selected" }
        return label
    }

    // MARK: - Actions

    /// Tap flow per mode, first time vs. subsequent:
    ///
    /// - **First tap, unlocked mode**: show the description sheet;
    ///   `continueIntoMode(_:)` runs after dismiss and performs the
    ///   mode switch.
    /// - **First tap, locked mode**: show the description sheet. The
    ///   sheet itself explains why the mode is locked; no alert
    ///   follows.
    /// - **Subsequent tap, unlocked mode**: switch directly (no sheet,
    ///   matches pre-existing behavior).
    /// - **Subsequent tap, locked mode**: locked alert (matches
    ///   pre-existing behavior).
    private func handleTap(mode: ChatMode, isLocked: Bool) {
        if !ModeDescriptionStore.hasSeen(mode) {
            pendingDescription = ModeDescription.description(for: mode)
            return
        }

        if isLocked {
            showLockedAlert = true
            return
        }
        Task { await model.switchMode(to: mode) }
    }

    /// Run after the description sheet is acknowledged. `markSeen`
    /// already happened inside the sheet's Got-it action, so this
    /// just performs the post-sheet side effect — select the mode
    /// for unlocked ones; no-op for locked (the user has now been
    /// told what the mode is and why it's locked).
    private func continueIntoMode(_ mode: ChatMode) {
        let isLocked = mode.requiresUnlock && !model.isUnlocked
        guard !isLocked else { return }
        Task { await model.switchMode(to: mode) }
    }
}
