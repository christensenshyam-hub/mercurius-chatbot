import SwiftUI
import DesignSystem
import PersistenceKit

/// Compact flame + streak count for the chat header. Persistently visible so the
/// streak stays top-of-mind; tapping opens the Progress hub. With no streak
/// yet it's the flame alone — the invitation is in its VoiceOver label and in
/// the hub it opens (the header has no room for a sentence).
public struct StreakChip: View {
    private let streakStore: StreakStore
    private let action: () -> Void

    public init(streakStore: StreakStore, action: @escaping () -> Void) {
        self.streakStore = streakStore
        self.action = action
    }

    public var body: some View {
        let display = StreakDisplay(count: streakStore.current)
        Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(display.isZero ? BrandColor.textSecondary : BrandColor.streakFlame)
                if let countText = display.countText {
                    Text(countText)
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(BrandColor.surfaceElevated, in: Capsule())
        }
        .accessibilityLabel("Your progress. \(display.spokenStreak)")
    }
}
