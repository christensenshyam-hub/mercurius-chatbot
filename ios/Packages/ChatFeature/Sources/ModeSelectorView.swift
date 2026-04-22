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

    private func handleTap(mode: ChatMode, isLocked: Bool) {
        if isLocked {
            showLockedAlert = true
            return
        }
        Task { await model.switchMode(to: mode) }
    }
}
