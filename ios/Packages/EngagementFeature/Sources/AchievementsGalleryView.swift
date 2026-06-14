import SwiftUI
import DesignSystem
import PersistenceKit

/// Grid of earned + locked achievement badges.
public struct AchievementsGalleryView: View {
    private let store: AchievementStore

    public init(store: AchievementStore) {
        self.store = store
    }

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: BrandSpacing.md)]

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                Text("Achievements")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                Spacer()
                Text("\(store.earnedCount) / \(AchievementCatalog.all.count)")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .monospacedDigit()
            }
            LazyVGrid(columns: columns, spacing: BrandSpacing.md) {
                ForEach(AchievementCatalog.all) { achievement in
                    badge(achievement, earned: store.has(achievement.id))
                }
            }
        }
    }

    private func badge(_ achievement: Achievement, earned: Bool) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: earned ? achievement.symbol : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(earned ? BrandColor.accent : BrandColor.textSecondary)
                .frame(width: 56, height: 56)
                .background(
                    earned ? BrandColor.accent.opacity(0.12) : BrandColor.surfaceElevated,
                    in: Circle()
                )
            Text(achievement.title)
                .font(BrandFont.caption)
                .foregroundStyle(earned ? BrandColor.text : BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .opacity(earned ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title). \(earned ? "Earned" : "Locked"). \(achievement.detail)")
    }
}
