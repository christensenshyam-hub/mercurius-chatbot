#if os(macOS)
import SwiftUI
import DesignSystem

// MARK: - What the host hands the card

/// This week's count after the completion, for the complete card's week
/// row. `MacShellView` passes it (ChatFeature can't see the curriculum's
/// weekly plan); nil hides the row.
public struct NightLessonWeek: Equatable, Sendable {
    /// Lessons first completed this week, this one included when it counts.
    public let done: Int
    public let goal: Int
    /// This lesson's completion is one of `done` (first completed this week),
    /// so the ring lights one more arc as the card arrives.
    public let includesThisLesson: Bool

    public init(done: Int, goal: Int, includesThisLesson: Bool) {
        self.done = done
        self.goal = goal
        self.includesThisLesson = includesThisLesson
    }

    /// The count the ring starts from.
    var before: Int { includesThisLesson ? max(done - 1, 0) : done }
}

private struct NightLessonWeekKey: EnvironmentKey {
    static let defaultValue: NightLessonWeek? = nil
}

/// What the lesson itself knows for its complete card: the objective (the
/// credential headline) and the `[KEY]` ideas Merc gave in its thread.
struct NightLessonRecap: Equatable {
    var objective: String
    var keyIdeas: [String]

    static let empty = NightLessonRecap(objective: "", keyIdeas: [])
}

private struct NightLessonRecapKey: EnvironmentKey {
    static let defaultValue = NightLessonRecap.empty
}

public extension EnvironmentValues {
    /// The Mac's lesson-complete card: this week's count after the
    /// completion (`MacShellView`).
    var nightLessonWeek: NightLessonWeek? {
        get { self[NightLessonWeekKey.self] }
        set { self[NightLessonWeekKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var nightLessonRecap: NightLessonRecap {
        get { self[NightLessonRecapKey.self] }
        set { self[NightLessonRecapKey.self] = newValue }
    }
}

// MARK: - The words (pure, tested)

/// Every line the Mac's lesson-complete card says (SPEC.md §5.6, §6),
/// held to the honest-copy register by `NightCompleteCopyTests`.
enum NightCompleteCopy {
    /// The credential headline, derived from the lesson's objective in
    /// `Curriculum.swift`, only where it says so honestly: an objective of
    /// the form "Understand X." becomes "You can now explain X." The card
    /// shows only after Merc judged the student's answers proficient
    /// (`[LESSON_COMPLETE]`), and the line under it says that. Any other
    /// objective ("Apply …", "Master …", "Learn …") gets no credential:
    /// "You can now master …" would claim more than one lesson shows.
    static func credential(objective: String) -> String? {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = "Understand "
        guard trimmed.hasPrefix(lead) else { return nil }
        var rest = String(trimmed.dropFirst(lead.count))
        while let last = rest.last, ".!".contains(last) { rest.removeLast() }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return "You can now explain \(rest)."
    }

    static let lessonComplete = "Lesson complete"

    /// The headline: the credential, else "Lesson complete".
    static func headline(objective: String) -> String {
        credential(objective: objective) ?? lessonComplete
    }

    /// Where the credential comes from, in one quiet line.
    static let attribution = "Merc marked this lesson complete from your answers."

    /// "Unit 1 · Lesson 1 · Complete".
    static func eyebrow(unitLabel: String?, lessonNumber: Int?) -> String {
        var parts: [String] = []
        if let unitLabel, !unitLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(CurriculumLessonView.unitName(unitLabel))
        }
        if let lessonNumber { parts.append("Lesson \(lessonNumber)") }
        parts.append("Complete")
        return parts.joined(separator: " · ")
    }

    // Key ideas
    static let keyIdeasLabel = "Key ideas from this lesson"
    /// The most the card lists; the rest stay in the lesson.
    static let keyIdeaLimit = 3
    static func moreKeyIdeas(_ count: Int) -> String { "+\(count) more in the lesson" }
    static func keyIdeaAccessibility(_ text: String) -> String { "Key idea: \(text)" }

    /// The ideas the card lists: the last `keyIdeaLimit`, and how many more
    /// the lesson holds.
    static func shownKeyIdeas(_ ideas: [String]) -> (shown: [String], more: Int) {
        let shown = Array(ideas.suffix(keyIdeaLimit))
        return (shown, ideas.count - shown.count)
    }

    // The week
    static func weekHeadline(done: Int, goal: Int) -> String {
        done > goal ? "\(done) this week" : "\(done) of \(goal) this week"
    }

    /// The stopping cue: true at any hour (no "call it a night").
    static func weekDetail(done: Int, goal: Int) -> String {
        let left = goal - done
        if left <= 0 { return "Weekly goal met. Anything more is a bonus." }
        if left == 1 { return "One more meets this week's goal. Or stop here for today." }
        return "\(left) more meet this week's goal. Or stop here for today."
    }

    // Up next
    static func upNextEyebrow(_ stop: LessonCompleteOverlay.NextStop) -> String {
        switch stop {
        case .lesson(let number, _): return "Up next · Lesson \(number)"
        case .unitTest(let unitNumber, _): return "Up next · Unit \(displayUnit(unitNumber)) check"
        }
    }

    static func upNextTitle(_ stop: LessonCompleteOverlay.NextStop) -> String {
        switch stop {
        case .lesson(_, let title): return title
        case .unitTest(_, let unitTitle): return unitTitle
        }
    }

    static func upNextAnnouncement(_ stop: LessonCompleteOverlay.NextStop?) -> String? {
        switch stop {
        case .lesson(let number, let title): return "Up next: Lesson \(number), \(title)."
        case .unitTest(let unitNumber, _): return "Up next: the Unit \(displayUnit(unitNumber)) check."
        case nil: return nil
        }
    }

    // Buttons
    static let doneForNow = "Done for now"
    static let doneForNowHelp = "Close the lesson and come back to the path later"

    /// The primary button; nil when there's nothing next (then "Done for
    /// now" is the one button).
    static func primaryTitle(_ stop: LessonCompleteOverlay.NextStop?) -> String? {
        switch stop {
        case .lesson(let number, _): return "Start Lesson \(number)"
        case .unitTest(let unitNumber, _): return "Take the Unit \(displayUnit(unitNumber)) Check"
        case nil: return nil
        }
    }

    static let share = "Share"
    static let shareHelp = "Share a picture of this finished lesson"
    static let keepReading = "Keep reading the lesson"

    /// "01" reads as "1".
    static func displayUnit(_ unitNumber: String) -> String {
        Int(unitNumber).map(String.init) ?? unitNumber
    }
}

/// The `[KEY]` ideas Merc gave in a lesson's thread, in order, each once.
enum NightKeyIdeas {
    static func collect(from messages: [ChatMessage]) -> [String] {
        var seen = Set<String>()
        var ideas: [String] = []
        for message in messages where message.role == .assistant {
            for block in BlockParser.parse(message.content) {
                guard case .key(let text) = block else { continue }
                let idea = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !idea.isEmpty, seen.insert(idea).inserted else { continue }
                ideas.append(idea)
            }
        }
        return ideas
    }
}

// MARK: - The card

/// Lesson complete on the Mac, in Night Studio (SPEC.md §5.6): a card over
/// the dimmed lesson, on its own canvas. Merc celebrates inside it (never
/// over its edge); the credential from the objective is the headline; the
/// lesson's key ideas are recapped; the week's ring lights the arc this
/// lesson earned, with a stopping cue; the next stop is named; "Done for
/// now" and the next step sit side by side at equal weight. Return takes
/// the next step, Escape (or a click on the backdrop) goes back to the
/// lesson. Nothing waits on the animation, and Reduce Motion is one
/// crossfade.
struct NightLessonComplete: View {
    let lessonTitle: String
    let nextStop: LessonCompleteOverlay.NextStop?
    let unitLabel: String?
    let lessonNumber: Int?
    let reduceMotion: Bool
    let exits: LessonCompleteExits

    @Environment(\.nightLessonRecap) private var recap
    @Environment(\.nightLessonWeek) private var week
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    @State private var shown = false
    @State private var mercOn = false
    @State private var mercState: MercState = .celebrate
    @State private var keysShown = false
    @State private var ringLit = false
    @State private var share: ShareItem?
    @State private var dismissalReported = false

    private struct ShareItem {
        let image: LessonShareImage
        let preview: Image
    }

    /// No motion: Reduce Motion (the system's or the DEBUG flag) or the
    /// host's own reading of it.
    private var still: Bool { reduceMotion || night.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 640
            ZStack {
                // The lesson stays visible under a canvas-coloured scrim.
                Night.canvasBottom.opacity(night.reduceTransparency ? 0.92 : 0.7)
                    .contentShape(Rectangle())
                    .onTapGesture { exit(.dismiss) }
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint(NightCompleteCopy.keepReading)

                card(compact: compact)
                    .frame(width: min(520, max(geo.size.width - 48, 320)))
                    .frame(maxHeight: max(geo.size.height - 48, 300))
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: shown || still ? 0 : 12)
                    .opacity(shown ? 1 : 0)

                // Escape: back to the lesson, as a click on the backdrop does.
                Button(NightCompleteCopy.keepReading) { exit(.dismiss) }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear(perform: arrive)
        .task { await renderShareCard() }
    }

    // MARK: Card

    private func card(compact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.hero, style: .continuous)
        return VStack(spacing: 0) {
            ScrollView {
                content(compact: compact)
                    .padding(.horizontal, Night.Space.hero)
                    .padding(.top, Night.Space.hero)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            // In a short window the content scrolls above the pinned
            // buttons: a line running under them fades out rather than
            // being cut mid-line.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [fadeColor.opacity(0), fadeColor], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            buttons
                .padding(.horizontal, Night.Space.hero)
                .padding(.top, 12)
                .padding(.bottom, Night.Space.hero)
        }
        .background {
            NightCanvas(pools: .both, stars: true)
                .clipShape(shape)
        }
        .nightLit(radius: Night.Radius.hero, fill: Night.canvasTop)
        .overlay(alignment: .topTrailing) { shareButton.padding(14) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The card's canvas at its foot (flat under Increase Contrast).
    private var fadeColor: Color { night.increasedContrast ? Night.canvasTop : Night.canvasBottom }

    private func content(compact: Bool) -> some View {
        let objective = recap.objective
        let credential = NightCompleteCopy.credential(objective: objective)
        let keys = NightCompleteCopy.shownKeyIdeas(recap.keyIdeas)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                merc(size: compact ? 72 : 96)
                NightEyebrow(NightCompleteCopy.eyebrow(unitLabel: unitLabel, lessonNumber: lessonNumber),
                             systemImage: "checkmark.seal.fill")
                Text(NightCompleteCopy.headline(objective: objective))
                    .nightFont(credential == nil ? .display : .title)
                    .foregroundStyle(Night.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(lessonTitle)
                    .nightFont(.body)
                    .foregroundStyle(Night.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NightCompleteCopy.attribution)
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            if !keys.shown.isEmpty {
                keyIdeas(keys.shown, more: keys.more)
            }
            if let week {
                weekRow(week)
            }
            if let nextStop {
                upNext(nextStop)
            }
        }
    }

    /// Merc inside the card, with one bloom of the brand light behind him
    /// (none under Increase Contrast) and no rings.
    private func merc(size: CGFloat) -> some View {
        ZStack {
            if !night.increasedContrast {
                Circle()
                    .fill(RadialGradient(colors: [Night.violet.opacity(scheme == .dark ? 0.42 : 0.26),
                                                  Night.accent.opacity(scheme == .dark ? 0.18 : 0.10),
                                                  Night.accent.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.8))
                    .frame(width: size * 1.6, height: size * 1.6)
                    .scaleEffect(mercOn || still ? 1 : 0.6)
                    .opacity(mercOn || still ? 1 : 0)
            }
            MercMascot(mercState, size: size, idleLife: !still)
        }
        .frame(width: size * 1.6, height: size * 1.25)
        .accessibilityHidden(true)
    }

    private func keyIdeas(_ ideas: [String], more: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NightCompleteCopy.keyIdeasLabel)
                .nightFont(.headline)
                .foregroundStyle(Night.ink2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(ideas.enumerated()), id: \.offset) { index, idea in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Night.accentText)
                        .accessibilityHidden(true)
                    Text(nightInlineMarkdown(idea))
                        .font(NightType.keep(16))
                        .lineSpacing(3)
                        .foregroundStyle(Night.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NightCompleteCopy.keyIdeaAccessibility(nightSpoken(idea)))
                .opacity(keysShown || still ? 1 : 0)
                .animation(still ? nil : Night.Motion.layout.delay(Double(index) * 0.08), value: keysShown)
            }
            if more > 0 {
                Text(NightCompleteCopy.moreKeyIdeas(more))
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekRow(_ week: NightLessonWeek) -> some View {
        let lit = ringLit || still ? week.done : week.before
        return HStack(spacing: 14) {
            NightRhythmRing(done: lit, goal: week.goal, lineWidth: 5, showsLabel: false)
                .frame(width: 44, height: 44)
                .animation(still ? nil : .easeInOut(duration: 0.6), value: lit)
            VStack(alignment: .leading, spacing: 3) {
                Text(NightCompleteCopy.weekHeadline(done: week.done, goal: week.goal))
                    .nightFont(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Night.ink)
                Text(NightCompleteCopy.weekDetail(done: week.done, goal: week.goal))
                    .nightFont(.callout)
                    .foregroundStyle(Night.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Night.surfaceRaised, in: RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
        .overlay {
            if night.increasedContrast {
                RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous)
                    .strokeBorder(Night.hairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NightCompleteCopy.weekHeadline(done: week.done, goal: week.goal)). "
                            + NightCompleteCopy.weekDetail(done: week.done, goal: week.goal))
    }

    private func upNext(_ stop: LessonCompleteOverlay.NextStop) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NightEyebrow(NightCompleteCopy.upNextEyebrow(stop), color: Night.ink3)
            Text(NightCompleteCopy.upNextTitle(stop))
                .nightFont(.headline)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Buttons

    /// "Done for now" beside the next step, at equal weight; Return takes
    /// the next step. With nothing next, "Done for now" is the one button.
    private var buttons: some View {
        HStack(spacing: 12) {
            if let primary = NightCompleteCopy.primaryTitle(nextStop) {
                Button { exit(.backToLessons) } label: {
                    Text(NightCompleteCopy.doneForNow).frame(maxWidth: .infinity)
                }
                .buttonStyle(NightSecondaryButtonStyle(size: .large))
                .nightFocusRing(Capsule())
                .help(NightCompleteCopy.doneForNowHelp)

                Button { exit(.next) } label: {
                    NightButtonLabel(title: primary, systemImage: "arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(NightPrimaryButtonStyle(size: .large))
                .keyboardShortcut(.defaultAction)
                .nightFocusRing(Capsule())
                .help("\(primary) (Return)")
                .accessibilityLabel(primary)
            } else {
                Button { exit(.backToLessons) } label: {
                    Text(NightCompleteCopy.doneForNow).frame(maxWidth: .infinity)
                }
                .buttonStyle(NightPrimaryButtonStyle(size: .large))
                .keyboardShortcut(.defaultAction)
                .nightFocusRing(Capsule())
                .help("\(NightCompleteCopy.doneForNow) (Return)")
            }
        }
    }

    /// The existing share card (`LessonShareCard`), from a 30 pt chrome
    /// circle in the card's corner. Holds its place while it renders.
    @ViewBuilder private var shareButton: some View {
        let icon = Image(systemName: "square.and.arrow.up")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Night.ink)
            .frame(width: 30, height: 30)
            .nightChrome(in: Circle(), interactive: true)
            .contentShape(Circle())
        if let share {
            ShareLink(item: share.image,
                      preview: SharePreview("Lesson complete · \(lessonTitle)", image: share.preview)) {
                icon
            }
            .buttonStyle(.plain)
            .nightFocusRing(Circle())
            .help(NightCompleteCopy.shareHelp)
            .accessibilityLabel(NightCompleteCopy.share)
            .accessibilityHint(NightCompleteCopy.shareHelp)
        } else {
            icon.opacity(0.5).accessibilityHidden(true)
        }
    }

    // MARK: Motion and actions

    /// The card rises 12 pt and fades in; Merc celebrates and his bloom
    /// opens at +0.15 s; the key ideas fade in from +0.25 s, 0.08 s apart;
    /// the ring lights this lesson's arc from +0.5 s. Reduce Motion: one
    /// crossfade to the final state.
    private func arrive() {
        if let line = NightCompleteCopy.upNextAnnouncement(nextStop) {
            AccessibilityNotification.Announcement(line).post()
        }
        if still {
            withAnimation(Night.Motion.fade) { shown = true }
            mercOn = true
            keysShown = true
            ringLit = true
            mercState = .happy
            return
        }
        withAnimation(Night.Motion.milestone) { shown = true }
        withAnimation(Night.Motion.layout.delay(0.15)) { mercOn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { keysShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ringLit = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { mercState = .happy }
    }

    private func exit(_ path: LessonCompleteExits.Path) {
        // The backdrop stays clickable while the card fades out; the host
        // hears about the dismissal once.
        exits.take(path, reportDismissal: !dismissalReported)
        dismissalReported = true
    }

    private func renderShareCard() async {
        // Rendering is synchronous main-actor work: let the card land first.
        if !still { try? await Task.sleep(for: .milliseconds(650)) }
        guard !Task.isCancelled else { return }
        let card = LessonShareCard(lessonTitle: lessonTitle, unitLabel: unitLabel, lessonNumber: lessonNumber)
        if let rendered = card.renderShareable() {
            share = ShareItem(image: rendered.item, preview: rendered.preview)
        }
    }
}
#endif
