import SwiftUI
import DesignSystem

/// The section banner that opens each unit on the learning path — the Duolingo
/// "checkpoint" divider. A gradient card with the unit number eyebrow, title,
/// and a lessons-completed count (plus a Mastered badge once the unit test is
/// passed). Uses the rounded type ramp for the playful, gamified feel.
struct UnitCheckpointHeader: View {
    let unit: Unit
    let completed: Int
    let total: Int
    let mastered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNIT \(unit.number)")
                .font(.system(.caption, design: .rounded, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.85))

            Text(unit.title)
                .font(BrandFont.roundedTitle)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BrandSpacing.sm) {
                Text("\(completed) / \(total) lessons")
                    .font(BrandFont.roundedCaption)
                    .foregroundStyle(.white.opacity(0.9))
                if mastered {
                    Label("Mastered", systemImage: "rosette")
                        .font(BrandFont.roundedCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.lg)
        .background(BrandGradient.merc, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .brandShadow(.card)
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.xl)
        .padding(.bottom, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unit \(unit.number): \(unit.title). \(completed) of \(total) lessons complete.\(mastered ? " Mastered." : "")")
    }
}
