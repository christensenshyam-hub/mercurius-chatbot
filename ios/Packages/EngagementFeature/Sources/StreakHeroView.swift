import SwiftUI
import DesignSystem
import PersistenceKit

/// Hero streak display at the top of the Progress hub.
public struct StreakHeroView: View {
    private let streakStore: StreakStore

    public init(streakStore: StreakStore) {
        self.streakStore = streakStore
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(streakStore.current > 0 ? BrandColor.streakFlame : BrandColor.textSecondary)
            Text("\(streakStore.current)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColor.text)
                .monospacedDigit()
            Text("day streak")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            if streakStore.best > streakStore.current {
                Text("Best: \(streakStore.best) days")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
            Text(message)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, BrandSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
    }

    private var message: String {
        switch streakStore.current {
        case 0: return "Ask Mercurius a question today to start your streak."
        case 1: return "You're on the board. Come back tomorrow to keep it going."
        default: return "Keep it alive — one conversation a day."
        }
    }
}
