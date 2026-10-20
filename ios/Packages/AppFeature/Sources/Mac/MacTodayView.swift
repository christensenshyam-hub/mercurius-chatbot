#if os(macOS)
import SwiftUI
import DesignSystem
import CurriculumFeature
import NetworkingKit
import PersistenceKit

/// Today on the Mac: an overview rather than the iPhone's welcome screen.
///
/// - Merc and his greeting (the iPhone Home's line, `HomeState.greeting`).
/// - **Up next**: the next stop on the path — its unit, title and goal, the
///   unit's progress — with one button that opens it (Return presses it) and
///   one to the path.
/// - **This week** (the weekly goal's ring, with words) and **Streak**
///   (never a "0": with no streak yet it says how to start one). The streak
///   card opens Progress.
/// - **Recent chats**: the last three saved threads, and New Chat.
/// - The iPhone Home's one-time weekly-nudge offer, when it applies.
///
/// Everything here is read from the on-device stores; nothing in this view
/// talks to the server.
struct MacTodayView: View {
    let state: HomeState
    let progress: CurriculumProgressStore
    let conversations: [ConversationSummary]
    let reminders: MacTodayReminders
    let onOpenNext: () -> Void
    let onOpenPath: () -> Void
    let onOpenChat: (UUID) -> Void
    let onNewChat: () -> Void
    let onShowProgress: () -> Void

    /// How many saved threads the card lists.
    static let recentChatCount = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                greeting
                upNextCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: BrandSpacing.lg) {
                        weekCard
                        streakCard
                    }
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        weekCard
                        streakCard
                    }
                }
                recentChatsCard
                if reminders.shows {
                    reminderCard
                }
            }
            .padding(BrandSpacing.xl)
            .frame(maxWidth: MacLayout.readableWidth + 2 * BrandSpacing.xl, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(BrandColor.background)
        .navigationTitle("Today")
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .center, spacing: BrandSpacing.lg) {
            MercMascot(.idle, size: 84, emphasis: .softGlow, idleAntics: true)
                .accessibilityHidden(true)
            Text(state.greeting(hour: Calendar.current.component(.hour, from: Date())))
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Up next

    private var upNextCard: some View {
        let next = Self.upNext(state: state, progress: progress)
        return card {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text(next.eyebrow.uppercased())
                    .font(BrandFont.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(BrandColor.accentText)
                Text(next.title)
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(next.detail)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let unitProgress = next.unitProgress {
                    HStack(spacing: BrandSpacing.md) {
                        ProgressView(value: Double(unitProgress.done), total: Double(max(unitProgress.total, 1)))
                            .tint(BrandColor.accent)
                            .frame(maxWidth: 200)
                            .accessibilityHidden(true)
                        Text(unitProgress.label)
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                    }
                    .padding(.top, BrandSpacing.xxs)
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: BrandSpacing.md) {
                    Button(next.buttonTitle, action: onOpenNext)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .help("\(next.buttonTitle) (Return)")
                        .accessibilityIdentifier("today.nextStop")
                    Button("Learning Path", action: onOpenPath)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .help("Open the learning path (⌘2)")
                }
                .padding(.top, BrandSpacing.sm)
            }
        }
    }

    /// What the Up next card says about the next stop.
    struct UpNext: Equatable {
        struct UnitProgress: Equatable {
            let done: Int
            let total: Int
            let label: String
        }
        let eyebrow: String
        let title: String
        let detail: String
        let unitProgress: UnitProgress?
        let buttonTitle: String
    }

    @MainActor
    static func upNext(state: HomeState, progress: CurriculumProgressStore) -> UpNext {
        switch state.next {
        case .lesson(let lesson):
            let unit = MercuriusCurriculum.unit(containingLesson: lesson.id)
            let unitNumber = unit.map { Int($0.number) ?? 0 } ?? 0
            let place = unit.map { "Unit \(unitNumber) · Lesson \(lesson.number) of \($0.lessons.count)" }
                ?? "Lesson \(lesson.number)"
            let unitProgress = unit.map { unit -> UpNext.UnitProgress in
                let done = progress.completedCount(in: unit)
                return UpNext.UnitProgress(done: done, total: unit.lessons.count,
                                           label: "\(done) of \(unit.lessons.count) lessons done in Unit \(unitNumber)")
            }
            return UpNext(
                eyebrow: "Up next · \(place)",
                title: lesson.title,
                detail: lesson.objective,
                unitProgress: unitProgress,
                buttonTitle: state.resumesNext ? "Continue Lesson \(lesson.number)" : "Start Lesson \(lesson.number)"
            )
        case .unitTest(let unit):
            let number = Int(unit.number) ?? 0
            let questions = MercuriusCurriculum.unitTest(for: unit.id)?.questions.count ?? 0
            let detail = questions > 0
                ? "\(questions) questions, then one written answer Merc grades. Pass both to master the unit."
                : "A short check on the whole unit. Pass it to master the unit."
            return UpNext(
                eyebrow: "Up next · Unit \(number) check",
                title: unit.title,
                detail: detail,
                unitProgress: UpNext.UnitProgress(done: unit.lessons.count, total: unit.lessons.count,
                                                  label: "All \(unit.lessons.count) lessons done"),
                buttonTitle: "Take the Unit \(number) Check"
            )
        case nil:
            return UpNext(
                eyebrow: "Path complete",
                title: "You've finished every unit",
                detail: "Go back over any lesson, or chat with Merc to go deeper.",
                unitProgress: nil,
                buttonTitle: "Review Your Lessons"
            )
        }
    }

    // MARK: - This week, streak

    private var weekCard: some View {
        card {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(BrandColor.surfaceElevated, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: state.weekProgress)
                        .stroke(BrandGradient.mercHorizontal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("This week")
                        .font(BrandFont.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                    Text(Self.weekHeadline(state.week))
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                    Text(Self.weekDetail(state.week))
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.weekAccessibilityLabel)
        }
    }

    /// "1 of 2 lessons"; past the goal, "3 lessons".
    static func weekHeadline(_ week: WeeklyPlan) -> String {
        if week.done > week.goal { return "\(week.done) lessons" }
        return "\(week.done) of \(week.goal) \(week.goal == 1 ? "lesson" : "lessons")"
    }

    static func weekDetail(_ week: WeeklyPlan) -> String {
        if week.done >= week.goal { return "Goal met. Anything more is a bonus." }
        return "Goal: \(week.goal) lessons a week."
    }

    private var streakCard: some View {
        Button(action: onShowProgress) {
            card {
                HStack(alignment: .center, spacing: BrandSpacing.md) {
                    Image(systemName: state.streak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(state.streak > 0 ? BrandColor.streakFlame : BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        Text("Streak")
                            .font(BrandFont.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.textSecondary)
                        Text(Self.streakHeadline(state.streak))
                            .font(BrandFont.subheading)
                            .foregroundStyle(BrandColor.text)
                        Text(state.streak > 0 ? "One lesson or chat a day keeps it going." : "Finish a lesson to start one.")
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(BrandFont.caption.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macHoverHighlight(cornerRadius: BrandRadius.lg)
        .help("Your progress and achievements")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak: \(Self.streakHeadline(state.streak)). Opens your progress.")
        .accessibilityAddTraits(.isButton)
    }

    /// Never a "0": a streak not yet started is said in words.
    static func streakHeadline(_ streak: Int) -> String {
        switch streak {
        case ..<1: return "No streak yet"
        case 1: return "1 day"
        default: return "\(streak) days"
        }
    }

    // MARK: - Recent chats

    private var recentChatsCard: some View {
        card {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                HStack {
                    Text("Recent chats")
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: onNewChat) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    .help("Start a new chat (⌘N)")
                }
                let recent = Array(conversations.prefix(Self.recentChatCount))
                if recent.isEmpty {
                    Text("No chats yet. Ask Merc anything about AI: how it works, where it goes wrong, how to use it well.")
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(recent) { conversation in
                        chatRow(conversation)
                    }
                }
            }
        }
    }

    private func chatRow(_ conversation: ConversationSummary) -> some View {
        Button { onOpenChat(conversation.id) } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: "bubble.left")
                    .foregroundStyle(BrandColor.accentText)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(conversation.title)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .lineLimit(1)
                    Text(Self.chatDetail(conversation))
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(BrandFont.caption.weight(.semibold))
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
            .padding(.horizontal, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macHoverHighlight(cornerRadius: BrandRadius.sm)
        .accessibilityLabel("\(MacSidebar.modeName(conversation.mode)) chat. \(conversation.title).")
    }

    /// "Debate · yesterday".
    static func chatDetail(_ conversation: ConversationSummary) -> String {
        let when = conversation.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
        return "\(MacSidebar.modeName(conversation.mode)) · \(when)"
    }

    // MARK: - Weekly nudge offer

    private var reminderCard: some View {
        card {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BrandColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Want Merc to remind you twice a week?")
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                    Text("Wednesday at 7 PM and Sunday at 6 PM. You can change this in Progress.")
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: BrandSpacing.sm) {
                        Button("Remind Me", action: reminders.onAccept)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("home.reminderCard.accept")
                        Button("Not Now", action: reminders.onDismiss)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("home.reminderCard.dismiss")
                    }
                    .padding(.top, BrandSpacing.xs)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Card

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .fill(BrandColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                    .strokeBorder(BrandColor.border, lineWidth: 1)
            )
    }
}
#endif
