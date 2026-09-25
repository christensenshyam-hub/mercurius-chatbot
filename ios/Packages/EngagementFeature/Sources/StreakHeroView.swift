import SwiftUI
import DesignSystem
import PersistenceKit

/// Hero streak display at the top of the Progress hub. Before there's a
/// streak it's the flame and an invitation — no "0 day streak".
public struct StreakHeroView: View {
    private let streakStore: StreakStore

    public init(streakStore: StreakStore) {
        self.streakStore = streakStore
    }

    public var body: some View {
        let display = StreakDisplay(count: streakStore.current)
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(display.isZero ? BrandColor.textSecondary : BrandColor.streakFlame)
                .accessibilityHidden(true)
            if let countText = display.countText {
                Text(countText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.text)
                    .monospacedDigit()
                Text("day streak")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            if streakStore.best > streakStore.current {
                Text("Best: \(streakStore.best) \(streakStore.best == 1 ? "day" : "days")")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Text(display.heroMessage)
                .font(display.isZero ? BrandFont.bodyEmphasized : BrandFont.body)
                .foregroundStyle(display.isZero ? BrandColor.text : BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, BrandSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
    }
}
