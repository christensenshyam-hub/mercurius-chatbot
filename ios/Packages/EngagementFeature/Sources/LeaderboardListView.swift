import SwiftUI
import DesignSystem
import NetworkingKit

/// Renders the leaderboard as a list of rows. Rendered as a VStack (not a `List`)
/// so it composes inside the Progress hub's `ScrollView`. Loads on appear.
///
/// Ownership note: the view model is owned by the parent (`ProgressHubView`) via
/// `@State`; this view reads it as a plain reference and observes it.
public struct LeaderboardListView: View {
    private let model: LeaderboardViewModel

    public init(model: LeaderboardViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                Text("Leaderboard")
                    .font(BrandFont.subheading)
                    .foregroundStyle(BrandColor.text)
                Spacer()
                Text("By streak")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }

            switch model.phase {
            case .loading:
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, BrandSpacing.lg)

            case .failed(let reason, let retryable):
                VStack(spacing: BrandSpacing.sm) {
                    Text(reason)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                    if retryable {
                        BrandButton("Try again", style: .secondary) {
                            Task { await model.load() }
                        }
                        .frame(maxWidth: 200)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.lg)

            case .ready(let entries):
                if entries.isEmpty {
                    Text("No one's on the board yet. Keep a streak going to claim a spot.")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                } else {
                    VStack(spacing: BrandSpacing.xs) {
                        ForEach(entries) { row(for: $0) }
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private func row(for entry: LeaderboardEntry) -> some View {
        let you = model.isYou(entry)
        return HStack(spacing: BrandSpacing.md) {
            Text("\(entry.rank)")
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.textSecondary)
                .frame(width: 26, alignment: .trailing)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name ?? entry.badge)
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                Text("\(entry.messages) messages")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("\(entry.streak)")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.text)
                    .monospacedDigit()
            }

            if you {
                Text("YOU")
                    .font(BrandFont.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, 2)
                    .background(BrandColor.accent, in: Capsule())
            }
        }
        .padding(BrandSpacing.sm)
        .background(
            you ? BrandColor.accent.opacity(0.10) : BrandColor.surface,
            in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
        )
    }
}
