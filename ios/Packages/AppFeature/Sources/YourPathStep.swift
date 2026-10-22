import SwiftUI
import DesignSystem
import CurriculumFeature
import EngagementFeature
import PersistenceKit

/// The last screen of the full first-run flow: where to start, the reminder
/// switches, and the way into the free chat.
///
/// Two equal choices (BEGINNER_GUIDE §2.1): "I'm new to AI: start with the
/// Basics" and "Take the Deep dive", each a full-width button that remembers
/// the choice and opens that course's first lesson. Learners pick by
/// experience, never by age, and "You can switch any time" says the choice
/// locks nothing. The two buttons are the step's pinned CTA, so both stay on
/// screen at every text size (AUD-12); what each course is reads above them,
/// and "Just chat instead" closes the scrolling part.
struct YourPathStep: View {
    let reminderStore: ReminderStore
    let scheduler: NotificationScheduler
    let streakStore: StreakStore
    let reminderCardStore: ReminderCardStore
    /// Start the chosen course's first lesson.
    let onStart: (CurriculumTrack) -> Void
    let onJustChat: () -> Void

    var body: some View {
        GateStepContainer(
            title: "Your path",
            subtitle: YourPathCopy.subtitle
        ) {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(YourPathCopy.order, id: \.self) { track in
                        courseRow(track)
                        if track != YourPathCopy.order.last {
                            Divider().padding(.leading, BrandSpacing.md)
                        }
                    }
                }
                #if os(macOS)
                .nightLit(radius: Night.Radius.card)
                #else
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
                #endif

                RemindersSection(
                    store: reminderStore,
                    scheduler: scheduler,
                    streakStore: streakStore,
                    nextLessonId: MercuriusCurriculum.units.first?.lessons.first?.id
                )

                BrandButton("Just chat instead", style: .ghost, action: onJustChat)
                    .accessibilityIdentifier("onboarding.justChat")
            }
            .padding(.top, BrandSpacing.sm)
        } cta: {
            ForEach(YourPathCopy.order, id: \.self) { track in
                DuoButton(YourPathCopy.title(track), style: .primary) { onStart(track) }
                    .accessibilityHint(YourPathCopy.hint(track))
                    .accessibilityIdentifier(YourPathCopy.identifier(track))
            }
        }
        .onAppear {
            OnboardingTelemetry.pathShown()
            // New installs answer the reminder question here; Home's one-time
            // card is for installs that onboarded before it existed.
            reminderCardStore.markHandled()
        }
    }

    /// What one course is, in a line: its name, then who it's for.
    private func courseRow(_ track: CurriculumTrack) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(track.displayName)
                #if os(macOS)
                .nightFont(.headline)
                .foregroundStyle(Night.ink)
                #else
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
                #endif
            Text(YourPathCopy.detail(track))
                #if os(macOS)
                .nightFont(.body)
                .foregroundStyle(Night.ink2)
                #else
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                #endif
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// The words on "Your path" (BEGINNER_GUIDE §2.1).
enum YourPathCopy {
    /// Basics first: a beginner reads down from the top.
    static let order: [CurriculumTrack] = [.basics, .deepDive]

    static let subtitle = "Where would you like to start? You can switch any time."

    static func title(_ track: CurriculumTrack) -> String {
        switch track {
        case .basics: return "I'm new to AI: start with the Basics"
        case .deepDive: return "Take the Deep dive"
        }
    }

    static func detail(_ track: CurriculumTrack) -> String {
        switch track {
        case .basics: return "New to AI chatbots? Learn the basics, one small step at a time."
        case .deepDive: return "Already use AI? Learn how it works, where it goes wrong, and how to think about it."
        }
    }

    static func hint(_ track: CurriculumTrack) -> String {
        switch track {
        case .basics: return "Opens the first Basics lesson"
        case .deepDive: return "Opens Lesson 1 of the Deep dive"
        }
    }

    /// The Deep dive keeps the identifier the UI tests tap ("Start Lesson 1").
    static func identifier(_ track: CurriculumTrack) -> String {
        switch track {
        case .basics: return "onboarding.startBasics"
        case .deepDive: return "onboarding.startLesson1"
        }
    }
}
