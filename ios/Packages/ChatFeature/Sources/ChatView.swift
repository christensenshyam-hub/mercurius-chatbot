import SwiftUI
import DesignSystem
import NetworkingKit
import PersistenceKit

/// The root chat screen. Owns the view model and composes the message
/// list, input bar, and empty state.
public struct ChatView: View {
    @State private var model: ChatViewModel
    /// A single presented sheet. Settings and the quiz both route through ONE
    /// `.sheet(item:)` — stacking multiple `.sheet` modifiers on the same view
    /// is a SwiftUI footgun where only one presents (the others silently
    /// no-op).
    @State private var activeSheet: ActiveSheet?

    /// Outcome of the most recent report, driving the one feedback alert.
    @State private var reportFeedback: ReportFeedback?

    /// Brief "encouraging" Merc beat after a substantive exchange completes.
    @State private var encourage = false
    @State private var encourageTask: Task<Void, Never>?

    /// First-launch hint above the input bar. Visible only when the
    /// chat is empty AND the user hasn't dismissed it once. The X
    /// button on the hint is the only explicit dismissal path;
    /// sending a first message implicitly hides it because
    /// `model.messages.isEmpty` flips to false.
    @AppStorage(ChatInputHint.storageKey) private var hasSeenChatInputHint: Bool = false

    private enum ActiveSheet: Identifiable {
        case settings
        case quiz
        var id: String {
            switch self {
            case .settings: return "settings"
            case .quiz: return "quiz"
            }
        }
    }

    private let apiClient: APIClient
    private let sessionIdentity: SessionIdentity
    /// Awards tool-driven achievements (Quiz Master). Lives in
    /// PersistenceKit (a ChatFeature dependency). Optional for previews/tests.
    private let achievementStore: AchievementStore?

    /// Closure the host app provides to surface the Settings screen.
    /// Kept as a closure so `ChatFeature` doesn't depend on
    /// `SettingsFeature` — composition lives in `AppFeature`.
    private let settingsPresenter: (@MainActor () -> AnyView)?

    /// Optional header accessory (e.g. the streak chip). Injected as a closure
    /// so `ChatFeature` doesn't depend on `EngagementFeature` — composition
    /// lives in `AppFeature`, mirroring `settingsPresenter`.
    private let headerAccessory: (@MainActor () -> AnyView)?

    /// Optional escape hatch: if provided, renders a leading "Home"
    /// button in the header that invokes this closure. `AppFeature`
    /// wires it up to return the user to the branded HomeView so the
    /// chat tab never feels like a dead-end. Left optional so
    /// previews / tests / any future non-TabView host can omit it.
    private let onGoHome: (@MainActor () -> Void)?

    /// Each change closes whichever sheet this view is presenting, so a host
    /// about to present something of its own (a tapped reminder's lesson)
    /// isn't blocked by a sheet it can't otherwise reach.
    private let dismissSheetsToken: Int

    public init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        chatStore: ChatStore? = nil,
        achievementStore: AchievementStore? = nil,
        settingsPresenter: (@MainActor () -> AnyView)? = nil,
        headerAccessory: (@MainActor () -> AnyView)? = nil,
        onGoHome: (@MainActor () -> Void)? = nil
    ) {
        _model = State(
            initialValue: ChatViewModel(
                apiClient: apiClient,
                sessionIdentity: sessionIdentity,
                store: chatStore,
                achievementStore: achievementStore
            )
        )
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.achievementStore = achievementStore
        self.settingsPresenter = settingsPresenter
        self.headerAccessory = headerAccessory
        self.onGoHome = onGoHome
        self.dismissSheetsToken = 0
    }

    /// Alternate initializer used by `AppShellView`: share an existing
    /// ViewModel across tabs so the conversation survives tab switches
    /// and curriculum starters can push messages into the live chat.
    public init(
        model: ChatViewModel,
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        achievementStore: AchievementStore? = nil,
        settingsPresenter: (@MainActor () -> AnyView)? = nil,
        headerAccessory: (@MainActor () -> AnyView)? = nil,
        onGoHome: (@MainActor () -> Void)? = nil,
        dismissSheetsToken: Int = 0
    ) {
        _model = State(initialValue: model)
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.achievementStore = achievementStore
        self.settingsPresenter = settingsPresenter
        self.headerAccessory = headerAccessory
        self.onGoHome = onGoHome
        self.dismissSheetsToken = dismissSheetsToken
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BrandColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ModeSelectorView(model: model)
                    .background(BrandColor.background)
                Divider().overlay(BrandColor.border)

                if model.messages.isEmpty {
                    EmptyChatView(
                        suggestions: ModePromptProvider.prompts(for: model.currentMode),
                        mercMood: focalMercState.mood,
                        mercActivity: focalMercState.activity,
                        onSuggestion: { suggestion in
                            model.draft = suggestion
                            model.send()
                        }
                    )
                    // Re-key the view on the active mode so a mode
                    // switch crossfades the prompt chips rather than
                    // snap-replacing them. Cheap and obvious to the
                    // eye; tells the user "the suggestions just
                    // changed because of what you tapped."
                    .id(model.currentMode)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: model.currentMode)
                    .frame(maxHeight: .infinity)
                } else {
                    MessageListView(
                        messages: model.messages,
                        phase: model.phase,
                        onRetry: { model.retry() },
                        onExplainMore: { model.explainMore() },
                        onReport: { message, reason in
                            Task { @MainActor in
                                let outcome = await model.reportMessage(message, reason: reason)
                                reportFeedback = ReportFeedback(outcome)
                            }
                        },
                        onQuizMe: { activeSheet = .quiz },
                        mercMood: focalMercState.mood,
                        mercActivity: focalMercState.activity
                    )
                }

                if model.messages.isEmpty && !hasSeenChatInputHint {
                    ChatInputHint(onDismiss: dismissChatInputHint)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ChatInputBar(
                    text: Binding(
                        get: { model.draft },
                        set: { model.draft = $0 }
                    ),
                    isSending: isSending,
                    attachment: model.pendingImage,
                    isPreparingAttachment: model.isPreparingAttachment,
                    attachmentError: model.attachmentError,
                    characterLimit: model.draftCharacterLimit,
                    onSend: { model.send() },
                    onCancel: { model.cancel() },
                    onAttachImage: { model.attachImage(data: $0) },
                    onRemoveAttachment: { model.clearAttachment() }
                )
            }
        }
        // Animate the hint's appearance + dismissal so the transition
        // doesn't snap when `hasSeenChatInputHint` flips. Scoped to
        // just that state so other view churn isn't animated.
        .animation(.easeInOut(duration: 0.25), value: hasSeenChatInputHint)
        // A finished, substantive exchange earns a brief encouraging beat —
        // whether the reply streamed (.streaming→.idle) or arrived whole
        // (.sending→.idle, no deltas).
        .onChange(of: model.phase) { old, new in
            if (old == .streaming || old == .sending), new == .idle, hasEnoughConversation {
                triggerEncourage()
            }
        }
        .onChange(of: dismissSheetsToken) { _, _ in activeSheet = nil }
    }

    private func dismissChatInputHint() {
        hasSeenChatInputHint = true
    }

    // MARK: - Merc focal state

    private var isThinking: Bool { model.phase == .sending }
    private var isStreaming: Bool { model.phase == .streaming }
    private var isFailed: Bool {
        if case .failed = model.phase { return true } else { return false }
    }

    /// The single focal Merc state for the chat — resolved from the live signals
    /// via the centralized helper. Drives the intro Merc and the latest assistant
    /// avatar.
    private var focalMercState: MercMascotState {
        let resolved = MercMascotState.resolve(MercSignals(
            screen: .chat,
            isUserTyping: !model.draft.isEmpty,
            isAIThinking: isThinking,
            isAISpeaking: isStreaming,
            hasError: isFailed
        ))
        // The brief encouraging beat only colors an OTHERWISE-IDLE chat: live
        // ambient states (thinking / speaking / listening) and errors always win
        // — so a fast follow-up is never masked — and it never leaks onto the
        // empty intro.
        if encourage, resolved.activity == .idle, !model.messages.isEmpty {
            return MercMascotState(mood: .encouraging, activity: .success,
                                   priority: .reaction, duration: 2.5)
        }
        return resolved
    }

    private func triggerEncourage() {
        encourageTask?.cancel()
        encourage = true
        encourageTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            encourage = false
        }
    }

    private var isSending: Bool {
        switch model.phase {
        case .sending, .streaming: return true
        case .idle, .failed: return false
        }
    }

    private var header: some View {
        // The brand block (logo monogram + "Mercurius AI / AI LITERACY TUTOR")
        // was redundant — the app is obviously Mercurius — so the bar is now
        // just the controls: the in-screen pair (streak chip + Settings)
        // leads together, Home trails alone. (New Chat / History live in the
        // bottom tab bar; the Quiz / Report Card buttons were removed.)
        HStack(spacing: BrandSpacing.sm) {
            if let headerAccessory {
                headerAccessory()
            }
            if settingsPresenter != nil {
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            Spacer()
            // Home is the lone trailing item so it reads as
            // "exit this context" rather than an in-screen control
            // — mirroring how Cancel/Done sit at the trailing edge
            // of iOS toolbars.
            if let onGoHome {
                Button {
                    // Leaving the shell destroys this view model, so stop
                    // the reply rather than let it stream into the void. The
                    // thread then ends on the student's turn, and the model
                    // built on return offers Retry for it.
                    if isSending { model.cancel() }
                    onGoHome()
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BrandColor.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Home")
                .accessibilityHint("Return to the Mercurius home screen")
            }
        }
        .padding(.leading, BrandSpacing.lg)
        .padding(.trailing, 4)
        .padding(.vertical, BrandSpacing.sm)
        .background(BrandColor.background)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                if let settingsPresenter {
                    settingsPresenter()
                }
            case .quiz:
                // The dormant quiz feature, revived (Presentation P3): a
                // comprehension quiz generated from THIS conversation via
                // POST /api/quiz. All the machinery below the entry point
                // (QuizView, QuizViewModel, APIClient+Tools, quizMaster
                // achievement) shipped long ago and stayed tested.
                QuizView(
                    model: QuizViewModel(
                        tools: apiClient,
                        sessionIdProvider: { [sessionIdentity] in try sessionIdentity.current() },
                        achievementStore: achievementStore
                    ),
                    dismissAction: { activeSheet = nil }
                )
            }
        }
        .reportFeedbackAlert(reportFeedback)
        // Chat History presentation is owned by `AppShellView`
        // (the TabView host) so the History tab item there can
        // drive it without coupling ChatView to the action.
    }

    /// Whether the conversation is substantive enough (≥2 user turns, ≥4
    /// messages) to earn the brief "encouraging" Merc beat after a reply.
    private var hasEnoughConversation: Bool {
        model.messages.filter { $0.role == .user }.count >= 2
            && model.messages.count >= 4
    }
}

/// The message list's coordinate space: 0 is the top of the visible reading
/// area. A plain constant, so the geometry closures (which run off the main
/// actor) can read it.
private let messageListSpace = "messageList"

/// The lesson coach card's content, drawn as the first row of the lesson's
/// message list so it scrolls away with the lesson (AUD-08).
struct LessonCoach: Equatable {
    let line: String
    let reaction: CoachReaction?
    let activity: MercActivity
}

/// The thread's stack. Eager in lessons: a few very tall rows, whose heights
/// a lazy stack only estimates until they render — its offset and height
/// then jump as it corrects them, which breaks following and holding a
/// reply. Lazy in free chat, where threads are long and replies short.
private struct ThreadStack<Content: View>: View {
    let lazy: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: BrandSpacing.sm) { content }
        } else {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) { content }
        }
    }
}

/// Reports when the student starts and stops dragging or flinging the list
/// (iOS 18+), so the scroll policy needn't guess it from offset changes.
private struct StudentScrollTracking: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollPhaseChange { old, new in
                let was = old == .interacting || old == .decelerating
                let isNow = new == .interacting || new == .decelerating
                if was != isNow { onChange(isNow) }
            }
        } else {
            content
        }
    }
}

/// Scroll bookkeeping for `MessageListView`. A class held in `@State`, so
/// every layout can update it without re-rendering the list; only what
/// changes the picture (the pill, the coach card) goes through `@State`.
@MainActor
final class MessageListScrollState {
    var policy: MessageScrollPolicy = {
        if #available(iOS 18.0, macOS 15.0, *) {
            return MessageScrollPolicy(knowsStudentScrolling: true)   // StudentScrollTracking reports it
        }
        return MessageScrollPolicy()
    }()
    var coach = CoachCardPresence()
    /// The coach card's full height. Its position comes from the content
    /// offset instead: a lazy row that a jump scrolls away stops reporting
    /// its frame, so a remembered frame can claim it is still on screen.
    var coachHeight: CGFloat = 0
}

/// The scrollable thread. How it moves as messages arrive and stream is
/// decided by `MessageScrollPolicy` (AUD-09): a new turn goes to the bottom,
/// a streaming reply is followed only while the student is at the bottom and
/// is held at its first line once it fills the reading area, and a "Jump to
/// latest" pill shows whenever the end is out of view.
struct MessageListView: View {
    let messages: [ChatMessage]
    let phase: ChatViewModel.Phase
    let onRetry: () -> Void
    let onExplainMore: () -> Void
    /// The reported message plus the reason the student picked.
    let onReport: (ChatMessage, ReportReason) -> Void
    /// Lesson styling for the bubbles (presence line + callout + soft shadow).
    var lessonStyle: Bool = false
    /// Tap handler for the lesson check-question callout ("tap the question,
    /// keyboard opens"). Nil keeps the callout non-interactive.
    var onCheckTap: (() -> Void)? = nil
    /// Presents the conversation quiz (free chat only). Nil hides the chip.
    var onQuizMe: (() -> Void)? = nil
    /// blocks_v1: auto-sends a quiz-option pick as a user turn (lessons only).
    /// Nil renders [Q] blocks inert.
    var onQuizPick: ((String) -> Void)? = nil
    /// The live focal Merc state, applied to the LATEST assistant message's
    /// avatar (older avatars stay neutral). Avatars render only in free chat.
    var mercMood: MercMood = .neutral
    var mercActivity: MercActivity = .idle
    /// Lessons only: Merc's coach card, as the list's first row. Hidden at
    /// accessibility text sizes, and while the student types if it's on
    /// screen (see `CoachCardPresence`).
    var coach: LessonCoach? = nil
    /// Whether the composer under the list has focus (the keyboard is up).
    var composerFocused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var scroll = MessageListScrollState()
    @State private var showsJumpPill = false
    @State private var coachHiddenForTyping = false

    private static let bottomID = "message-list-bottom"
    private static let coachID = "lesson-coach"

    /// Which footer follows the thread; when it changes the end of the list
    /// moves.
    private enum Footer: Equatable { case none, retry, explainMore }

    private var footer: Footer {
        if case .failed(_, let isRetryable) = phase, isRetryable { return .retry }
        return shouldShowExplainMore ? .explainMore : .none
    }

    /// The coach row exists (it collapses rather than leaves while the
    /// student types — taking the first row out of a lazy stack scrolled far
    /// down can leave it laid out blank).
    private var hasCoachRow: Bool {
        coach != nil && !dynamicTypeSize.isAccessibilitySize
    }

    /// The latest assistant message — the one whose avatar reflects the live
    /// thinking / speaking / listening state.
    private var focalAssistantId: ChatMessage.ID? {
        guard let last = messages.last, last.role == .assistant else { return nil }
        return last.id
    }

    /// Whether assistant bubbles currently render the leading Merc avatar —
    /// mirrors `MessageBubbleView.shouldShowAvatar` (free chat only, dropped at
    /// accessibility type sizes), so the follow-up chip only leads-aligns with
    /// a bubble edge that actually exists.
    private var alignsWithAvatar: Bool {
        !lessonStyle && !dynamicTypeSize.isAccessibilitySize
    }

    /// The FIRST exchange of a Discussion chat (the user's opening message +
    /// Merc's first reply) gets a larger coach moment above the thread. Once a
    /// second user turn arrives it collapses and the compact per-message
    /// avatars carry Merc from there. (A one-exchange thread resumed from
    /// history shows it too — there it reads as an invitation to continue.)
    private var showsCoachIntro: Bool {
        !lessonStyle && messages.count <= 2
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ThreadStack(lazy: !lessonStyle) {
                    if let coach, hasCoachRow {
                        MercCoachCard(line: coach.line, reaction: coach.reaction,
                                      liveActivity: coach.activity)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { geo in
                                geo.size.height
                            } action: { height in
                                scroll.coachHeight = height
                            }
                            .frame(height: coachHiddenForTyping ? 0 : nil, alignment: .top)
                            .clipped()
                            .opacity(coachHiddenForTyping ? 0 : 1)
                            .accessibilityHidden(coachHiddenForTyping)
                            .id(Self.coachID)
                    }

                    if showsCoachIntro {
                        coachIntro
                            .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                    }

                    ForEach(messages) { message in
                        let isFocal = message.id == focalAssistantId
                        // One live Merc at a time: while the coach intro is up
                        // it carries the thinking/speaking motion and the
                        // message avatars stay neutral; after it collapses the
                        // latest assistant avatar becomes the live one.
                        let isLive = isFocal && !showsCoachIntro
                        MessageBubbleView(
                            message: message,
                            onReport: { reason in onReport(message, reason) },
                            lessonStyle: lessonStyle,
                            showAvatar: !lessonStyle,
                            avatarMood: isLive ? mercMood : .neutral,
                            avatarActivity: isLive ? mercActivity : .idle,
                            avatarIdleLife: isLive,
                            onCheckTap: onCheckTap,
                            quizInteraction: quizInteraction(for: message)
                        )
                        .equatable()
                        .id(message.id)
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.frame(in: .named(messageListSpace)).minY
                        } action: { minY in
                            if message.id == messages.last?.id { scroll.policy.latestMessageMoved(minY: minY) }
                        }
                    }

                    if case .failed(_, let isRetryable) = phase, isRetryable {
                        retryFooter
                            .id("retry-footer")
                    } else if shouldShowExplainMore {
                        // Soft footer surfaced after the assistant has
                        // finished a turn and the user is idle. Mirrors
                        // the spec's "first answer concise; user taps
                        // for depth" loop. Disabled while sending so
                        // taps don't queue alongside an in-flight send.
                        explainMoreFooter
                            .id("explain-more-footer")
                    }

                    // The end of the thread, below every footer: what
                    // "scroll to the bottom" aims at.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, BrandSpacing.md)
                // Gated like every other explicit animation in the app: under
                // Reduce Motion the intro just disappears (its transition is
                // already opacity-only) instead of sliding the thread up.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25),
                           value: showsCoachIntro)
                .onGeometryChange(for: CGRect.self) { geo in
                    geo.frame(in: .named(messageListSpace))
                } action: { frame in
                    var geometry = scroll.policy.geometry
                    geometry.contentMinY = frame.minY
                    geometry.contentHeight = frame.height
                    layoutChanged(geometry, proxy: proxy)
                }
            }
            .coordinateSpace(.named(messageListSpace))
            .modifier(StudentScrollTracking { scrolling in
                scroll.policy.studentScrolling(scrolling)
            })
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.size.height
            } action: { height in
                var geometry = scroll.policy.geometry
                geometry.viewportHeight = height
                layoutChanged(geometry, proxy: proxy)
            }
            .overlay(alignment: .bottom) {
                if showsJumpPill {
                    jumpToLatestPill(proxy: proxy)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onChange(of: messages.last?.id) { _, newValue in
                guard newValue != nil, let last = messages.last else { return }
                // Merc's empty placeholder means a reply is on its way (a
                // send, Retry, Explain more, a lesson opener): glide down to
                // it. Anything else is a thread that just loaded: jump.
                let isNewReply = last.role == .assistant && last.content.isEmpty
                    && last.status == .streaming
                perform(scroll.policy.latestMessageChanged(isNewReply: isNewReply), proxy: proxy)
            }
            .onChange(of: messages.last?.content) { _, content in
                // An empty placeholder is a new reply, handled just above.
                guard let content, !content.isEmpty else { return }
                perform(scroll.policy.latestMessageGrew(), proxy: proxy)
            }
            .onChange(of: footer) { _, _ in
                perform(scroll.policy.footerChanged(), proxy: proxy)
            }
            .onChange(of: composerFocused) { _, focused in
                let geometry = scroll.policy.geometry
                let coachOnScreen = hasCoachRow && !coachHiddenForTyping
                    && CoachCardPresence.isOnScreen(coachHeight: scroll.coachHeight,
                                                    topInset: BrandSpacing.md, geometry: geometry)
                let toBottom = scroll.coach.composerFocusChanged(
                    focused: focused, coachOnScreen: coachOnScreen, geometry: geometry)
                syncCoachPresence()
                if toBottom { perform(.scrollToBottom(animated: false), proxy: proxy) }
            }
        }
    }

    /// A new layout of the list (content or reading area) arrived.
    private func layoutChanged(_ geometry: MessageListGeometry, proxy: ScrollViewProxy) {
        perform(scroll.policy.geometryChanged(geometry), proxy: proxy)
        if coach != nil,
           scroll.coach.geometryChanged(composerFocused: composerFocused, geometry: geometry) {
            perform(.scrollToBottom(animated: false), proxy: proxy)
        }
        syncCoachPresence()
        let shows = !messages.isEmpty && scroll.policy.showsJumpPill
        if shows != showsJumpPill {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsJumpPill = shows }
        }
    }

    private func syncCoachPresence() {
        let hidden = scroll.coach.isHiddenForTyping
        if hidden != coachHiddenForTyping {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { coachHiddenForTyping = hidden }
        }
    }

    private func perform(_ action: MessageScrollPolicy.Action, proxy: ScrollViewProxy) {
        switch action {
        case .none:
            break
        case .scrollToBottom(let animated):
            if animated, !reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        case .showLatestMessageTop:
            if let id = messages.last?.id { proxy.scrollTo(id, anchor: .top) }
        }
    }

    /// Floats over the bottom of the list whenever the end of the thread is
    /// out of view — after a long reply was held at its top, or when the
    /// student scrolled up to re-read.
    private func jumpToLatestPill(proxy: ScrollViewProxy) -> some View {
        Button {
            perform(scroll.policy.jumpToLatest(), proxy: proxy)
        } label: {
            Label("Jump to latest", systemImage: "arrow.down")
                .font(BrandFont.caption.weight(.semibold))
                .foregroundStyle(BrandColor.accent)
                .padding(.vertical, BrandSpacing.sm)
                .padding(.horizontal, BrandSpacing.md)
                .background(BrandColor.surfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(BrandColor.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .padding(.bottom, BrandSpacing.xs)
        // Chrome over the reading text: it stops growing at xxxLarge so at
        // accessibility sizes it doesn't cover the lines it floats over
        // (long-press shows it large).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
        .accessibilityHint("Scrolls to the newest message")
    }

    /// The larger Merc coach moment above a brand-new thread — the handoff
    /// beat between the empty-state intro ("Hi, I'm Merc") and the compact
    /// per-message avatars. Carries the live thinking/speaking motion while
    /// Merc works on his first reply.
    private var coachIntro: some View {
        VStack(spacing: BrandSpacing.sm) {
            MercMascot(.idle, size: 84, emphasis: .softGlow,
                       mood: mercMood, activity: mercActivity,
                       idleAntics: true, pokeable: true)
                .accessibilityHidden(true)
            Text("Let’s sharpen this question together.")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BrandSpacing.xs)
        .padding(.bottom, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Merc, your tutor: Let’s sharpen this question together.")
    }

    private var retryFooter: some View {
        HStack {
            Spacer()
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(BrandFont.caption)
                    .padding(.vertical, BrandSpacing.sm)
                    .padding(.horizontal, BrandSpacing.md)
                    .background(BrandColor.surfaceElevated)
                    .foregroundStyle(BrandColor.accent)
                    .clipShape(Capsule())
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Retry sending the last message")
            Spacer()
        }
        .padding(.bottom, BrandSpacing.sm)
    }

    /// Visible when the conversation is idle and the most recent reply
    /// was from the assistant — invites the user to ask for more depth
    /// without re-typing. Wires to `ChatViewModel.explainMore()` which
    /// re-issues the chat request with `responseMode = .deep`.
    ///
    /// In the free chat the chip leads-aligns with the assistant bubble's
    /// text edge (past the Merc avatar) so it reads as part of Merc's turn;
    /// lessons have no avatar column, so it stays centered there.
    private var explainMoreFooter: some View {
        HStack {
            if !alignsWithAvatar { Spacer() }
            followUpChip("Explain more", systemImage: "text.alignleft", action: onExplainMore)
                .accessibilityHint("Asks Mercurius to expand on the previous answer in more depth")
            // "Quiz me" appears once the conversation has enough substance to
            // quiz on (two student turns) — the reading turns into doing.
            if let onQuizMe, messages.filter({ $0.role == .user }).count >= 2 {
                followUpChip("Quiz me", systemImage: "checklist", action: onQuizMe)
                    .accessibilityHint("Generates a short quiz from this conversation")
            }
            Spacer()
        }
        .padding(.leading, alignsWithAvatar
            ? BrandSpacing.lg + ChatAvatarMetrics.footprint + BrandSpacing.sm
            : 0)
        .padding(.top, BrandSpacing.xs)
        .padding(.bottom, BrandSpacing.sm)
    }

    /// blocks_v1 interaction for one lesson bubble: taps live only on the
    /// LATEST assistant message while no reply is in flight; older [Q]s
    /// render inert with the student's prior pick recovered from the
    /// following user message's "I picked X)" prefix — zero persistence
    /// changes. A complete [Q] in a reply that was then cut off stays
    /// answerable: the pick keeps that reply on the wire (AUD-29).
    private func quizInteraction(for message: ChatMessage) -> MessageBubbleView.QuizInteraction? {
        guard lessonStyle, let onQuizPick else { return nil }
        let isLatest = message.id == focalAssistantId
        let canAnswer: Bool
        switch phase {
        case .idle, .failed: canAnswer = true
        case .sending, .streaming: canAnswer = false
        }
        return MessageBubbleView.QuizInteraction(
            isEnabled: isLatest && canAnswer,
            answeredIndex: priorPickIndex(after: message),
            onPick: { quiz, index in
                let letter = String(UnicodeScalar(65 + index)!)
                let option = index < quiz.options.count ? quiz.options[index] : ""
                onQuizPick("I picked \(letter)) \(option)")
            }
        )
    }

    /// Scan the user message FOLLOWING an assistant [Q] for its recorded pick.
    private func priorPickIndex(after message: ChatMessage) -> Int? {
        guard let idx = messages.firstIndex(where: { $0.id == message.id }),
              idx + 1 < messages.count else { return nil }
        let next = messages[idx + 1]
        guard next.role == .user, next.content.hasPrefix("I picked "),
              let letter = next.content.dropFirst(9).first,
              let scalar = letter.unicodeScalars.first,
              (65...68).contains(Int(scalar.value)) else { return nil }
        return Int(scalar.value) - 65
    }

    /// The follow-up capsule chip ("Explain more" / "Quiz me") — one shared
    /// style so siblings can't drift.
    private func followUpChip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(BrandFont.caption)
                .padding(.vertical, BrandSpacing.sm)
                .padding(.horizontal, BrandSpacing.md)
                .background(BrandColor.surface)
                .foregroundStyle(BrandColor.accent)
                .overlay(
                    Capsule()
                        .strokeBorder(BrandColor.accent.opacity(0.4), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title)
    }

    /// Show the Explain More footer only when:
    ///   - we're not in a failure state (retry footer takes priority),
    ///   - we're idle (not mid-stream — otherwise tapping queues a
    ///     send while another is in flight, which `send()` already
    ///     no-ops but the affordance reads as broken),
    ///   - the last message is a non-empty assistant turn.
    private var shouldShowExplainMore: Bool {
        guard case .idle = phase else { return false }
        guard let last = messages.last else { return false }
        guard last.role == .assistant else { return false }
        guard !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }
}
