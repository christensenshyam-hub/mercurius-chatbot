import SwiftUI
import DesignSystem

/// A brief, inline progress reaction shown inside the coach card. Non-modal by
/// construction — it just swaps the card's line + plays a subtle Merc motion,
/// then the host clears it.
struct CoachReaction: Equatable {
    let copy: String
    let mood: MercMood
    let activity: MercActivity
}

/// A dedicated **coach** presence at the top of a lesson: Merc, large and fully
/// visible, alongside a short contextual line. This replaces the old
/// peek-behind-the-composer placement so Merc reads as a coach guiding the
/// lesson, not a sticker stuck to the input bar.
///
/// Steady by default — its only ambient motion is a one-time welcome wave that
/// settles to idle. When the host passes a `reaction` (a lesson-progress
/// moment), Merc briefly reacts in place (mood/activity motion + swapped copy)
/// without blocking the lesson below. Everything honors Reduce Motion.
struct MercCoachCard: View {
    let line: String
    var reaction: CoachReaction? = nil
    /// The lesson's live activity (thinking while the reply streams, etc.).
    /// Used when no reaction is showing — it both animates the coach in sync
    /// with the conversation and pauses the idle antics while Merc "works".
    var liveActivity: MercActivity = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mercState: MercState = .idle

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            // Large + softGlow so the coach reads cleanly on the dark surface.
            // Idle antics + poke keep the coach alive between lesson turns
            // (both pause automatically whenever a reaction drives the card).
            MercMascot(
                expression,
                size: 108,
                emphasis: .softGlow,
                mood: reaction?.mood ?? .neutral,
                activity: reaction?.activity ?? liveActivity,
                idleAntics: true,
                pokeable: true
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(eyebrowColor)
                Text(displayLine)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.sm)
        .padding(.horizontal, BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                .fill(BrandColor.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(reaction == nil ? BrandColor.border : eyebrowColor.opacity(0.5),
                                      lineWidth: 1)
                )
                .brandShadow(.card)
        )
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.xs)
        // Copy snaps (no muddy text overlap); the liveliness comes from Merc's
        // own pop motion, which already honors Reduce Motion.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your coach, Mercurius. \(displayLine)")
        .onAppear {
            // Welcome wave only when no reaction is driving the card.
            guard reaction == nil, !reduceMotion else { return }
            mercState = .wave
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                mercState = .idle
            }
        }
    }

    // MARK: - Reaction-aware presentation

    /// During a reaction Merc shows a matching expression; otherwise the welcome /
    /// idle state. (Reaction always wins, so the welcome wave is only visible when
    /// no reaction is active.)
    private var expression: MercState {
        guard let reaction else { return mercState }
        switch reaction.mood {
        case .celebrating:            return .celebrate
        case .happy, .encouraging:    return .happy
        default:                      return mercState
        }
    }

    private var eyebrow: String { reaction == nil ? "YOUR COACH" : "PROGRESS" }

    private var eyebrowColor: Color {
        guard let reaction else { return BrandColor.accent }
        return reaction.mood == .celebrating ? BrandColor.success : BrandColor.accent
    }

    private var displayLine: String { reaction?.copy ?? line }
}
