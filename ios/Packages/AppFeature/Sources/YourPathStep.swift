import SwiftUI
import DesignSystem
import CurriculumFeature
import EngagementFeature
import PersistenceKit

/// The last screen of the full first-run flow: Unit 1's four lessons, the
/// daily-reminder toggle, and the two ways into the app. The rows are built
/// here rather than reusing the learning path's nodes, which are internal
/// to CurriculumFeature.
struct YourPathStep: View {
    let reminderStore: ReminderStore
    let streakStore: StreakStore
    let onStartLesson1: () -> Void
    let onJustChat: () -> Void

    @State private var scheduler = NotificationScheduler()

    private var unit: CurriculumFeature.Unit? { MercuriusCurriculum.units.first }

    var body: some View {
        GateStepContainer(
            title: "Your path",
            subtitle: unit.map { "Unit \($0.number) · \($0.title)" }
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                VStack(spacing: 0) {
                    ForEach(unit?.lessons ?? []) { lesson in
                        lessonRow(lesson)
                        if lesson.id != unit?.lessons.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))

                DailyReminderSection(store: reminderStore, scheduler: scheduler, streakStore: streakStore)
            }
            .padding(.top, BrandSpacing.sm)
        } cta: {
            DuoButton("Start Lesson 1", style: .primary, action: onStartLesson1)
                .accessibilityIdentifier("onboarding.startLesson1")

            DuoButton("Just chat instead", style: .secondary, action: onJustChat)
                .accessibilityIdentifier("onboarding.justChat")
        }
        .onAppear { OnboardingTelemetry.pathShown() }
    }

    private func lessonRow(_ lesson: Lesson) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            Text("\(lesson.number)")
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(BrandGradient.merc, in: Circle())
                .accessibilityHidden(true)

            Text(lesson.title)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lesson \(lesson.number). \(lesson.title)")
    }
}
