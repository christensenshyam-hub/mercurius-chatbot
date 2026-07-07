import SwiftUI
import DesignSystem

/// The "lesson passed" celebration — a clouded backdrop, an animated check, and
/// a clear path forward. This is what the student sees the moment a lesson is
/// completed, in place of the raw `[…]` marker that used to leak into the
/// transcript. Presented as a full-screen layer inside `CurriculumLessonView`.
struct LessonCompleteOverlay: View {
    /// The lesson just completed (shown as a subtitle).
    let lessonTitle: String
    /// The next lesson in this unit, if any. Nil = last lesson of the unit.
    let nextLessonNumber: Int?
    let nextLessonTitle: String?
    let reduceMotion: Bool
    /// Advance to the next lesson (only meaningful when `nextLessonTitle != nil`).
    let onNext: () -> Void
    /// Close the lesson window and return to the unit's lesson list.
    let onBackToLessons: () -> Void
    /// Dismiss the overlay and stay in the lesson (re-read the feedback).
    let onDismiss: () -> Void

    @State private var sheetOffset: CGFloat = 800
    @State private var mercScale: CGFloat = 0.6

    private var hasNext: Bool { nextLessonTitle != nil }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dimmed scrim. Tapping it keeps the celebration out of the way
                // so the student can re-read the final feedback.
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Keep reading the lesson")

                sheet
                    // Cap the sheet so a long title at large Dynamic Type scrolls
                    // instead of pushing the primary button off-screen.
                    .frame(maxHeight: geo.size.height * 0.86)
                    .offset(y: sheetOffset)
            }
        }
        .onAppear(perform: animateIn)
    }

    /// A bottom sheet with Merc (celebrating) bursting out over its top edge.
    private var sheet: some View {
        contentCard
            .overlay(alignment: .top) {
                MercMascot(.celebrate, size: 148)
                    .scaleEffect(mercScale)
                    .offset(y: -80)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
    }

    private var contentCard: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Color.clear.frame(height: 56)   // room for the bursting Merc

                VStack(spacing: BrandSpacing.xs) {
                    Text("Nailed it!")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(BrandColor.success)
                        .multilineTextAlignment(.center)
                    Text("Lesson complete · \(lessonTitle)")
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary)

                if hasNext { upNext }
                buttons
            }
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.top, BrandSpacing.lg)
            .padding(.bottom, BrandSpacing.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 34, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous
            )
            .fill(BrandColor.surface)
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.3), radius: 28, y: -8)
        )
    }

    private var upNext: some View {
        VStack(spacing: 2) {
            Text("UP NEXT")
                .font(BrandFont.caption)
                .tracking(1.5)
                .foregroundStyle(BrandColor.accent)
            Text(nextLabel)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BrandSpacing.xs)
    }

    private var nextLabel: String {
        if let n = nextLessonNumber, let t = nextLessonTitle {
            return "Lesson \(n) · \(t)"
        }
        return nextLessonTitle ?? ""
    }

    private var buttons: some View {
        VStack(spacing: BrandSpacing.sm) {
            if hasNext {
                BrandButton("Next lesson", style: .primary, action: onNext)
                BrandButton("Back to lessons", style: .ghost, action: onBackToLessons)
            } else {
                BrandButton("Back to lessons", style: .primary, action: onBackToLessons)
            }
        }
        .padding(.top, BrandSpacing.xs)
    }

    private var accessibilitySummary: String {
        if let n = nextLessonNumber, let t = nextLessonTitle {
            return "Lesson complete: \(lessonTitle). Up next, lesson \(n): \(t)."
        }
        return "Lesson complete: \(lessonTitle). You finished this unit's lessons."
    }

    private func animateIn() {
        guard !reduceMotion else { sheetOffset = 0; mercScale = 1; return }
        withAnimation(.timingCurve(0.2, 0.9, 0.3, 1.1, duration: 0.45)) { sheetOffset = 0 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.12)) { mercScale = 1 }
    }
}

#if DEBUG
#Preview("With next lesson") {
    LessonCompleteOverlay(
        lessonTitle: "The alignment problem",
        nextLessonNumber: 2,
        nextLessonTitle: "Reward hacking & specification gaming",
        reduceMotion: false,
        onNext: {}, onBackToLessons: {}, onDismiss: {}
    )
}

#Preview("Last lesson of unit") {
    LessonCompleteOverlay(
        lessonTitle: "Review: ethics & alignment",
        nextLessonNumber: nil,
        nextLessonTitle: nil,
        reduceMotion: false,
        onNext: {}, onBackToLessons: {}, onDismiss: {}
    )
}
#endif
