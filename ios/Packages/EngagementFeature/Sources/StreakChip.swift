import SwiftUI
import DesignSystem
import PersistenceKit

/// Compact flame + streak count for the chat header. Persistently visible so the
/// streak stays top-of-mind; tapping opens the Progress hub.
public struct StreakChip: View {
    private let streakStore: StreakStore
    private let action: () -> Void

    public init(streakStore: StreakStore, action: @escaping () -> Void) {
        self.streakStore = streakStore
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(streakStore.current > 0 ? Color.orange : BrandColor.textSecondary)
                Text("\(streakStore.current)")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                    .monospacedDigit()
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(BrandColor.surfaceElevated, in: Capsule())
        }
        .accessibilityLabel("Your progress. Current streak: \(streakStore.current) days.")
    }
}
