import SwiftUI
import DesignSystem
import PersistenceKit

/// The quiet Progress card for the Progress hub — character-free: Level, a flat
/// progress bar toward the next level, total XP, and a plain streak line. No
/// mascot, emblem, or voice. The engagement engine (XP/level/streak) is
/// unchanged; this is purely how it's presented.
///
/// Renders nothing unless the store is `enabled`, so it's invisible in the
/// default build. Shows engagement Level only — never a competency rank.
public struct ProgressCard: View {
    private let store: GamificationStore

    public init(store: GamificationStore) {
        self.store = store
    }

    public var body: some View {
        if store.enabled {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Level \(store.level)")
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                    Spacer()
                    Text("\(store.streak)-day streak")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                progressBar
                HStack {
                    Text("\(store.xp) XP")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.text)
                    Spacer()
                    Text("next: level \(store.level + 1)")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }
            .padding(BrandSpacing.lg)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: BrandRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg)
                    .strokeBorder(BrandColor.border.opacity(0.6), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Level \(store.level), \(store.xp) XP, \(store.streak) day streak.")
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandColor.surface)
                Capsule()
                    .fill(BrandColor.accent)
                    .frame(width: max(6, geo.size.width * min(1, max(0, store.levelProgress))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Progress card") {
    ProgressCard(store: .preview())
        .padding()
        .background(BrandColor.background)
}
#endif
