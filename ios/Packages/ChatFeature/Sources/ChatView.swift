import SwiftUI
import DesignSystem
import NetworkingKit
import PersistenceKit

/// The root chat screen. Owns the view model and composes the message
/// list, input bar, and empty state.
public struct ChatView: View {
    @State private var model: ChatViewModel
    /// A single presented sheet. Settings + the analytical tools all route
    /// through ONE `.sheet(item:)` — stacking multiple `.sheet` modifiers on the
    /// same view is a SwiftUI footgun where only one presents (the others
    /// silently no-op), which is exactly why "Generate Quiz" / "Report Card"
    /// did nothing while Settings worked.
    @State private var activeSheet: ActiveSheet?

    /// Confirmation shown after the user reports an AI response.
    @State private var showReportConfirmation = false

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
        var id: String { "settings" }
    }

    private let apiClient: APIClient
    private let sessionIdentity: SessionIdentity
    /// Awards tool-driven achievements (Quiz Master, Report Card). Lives in
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
        onGoHome: (@MainActor () -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.apiClient = apiClient
        self.sessionIdentity = sessionIdentity
        self.achievementStore = achievementStore
        self.settingsPresenter = settingsPresenter
        self.headerAccessory = headerAccessory
        self.onGoHome = onGoHome
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
                        onReport: { message in
                            model.reportMessage(message)
                            showReportConfirmation = true
                        },
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
                    attachedImageData: model.pendingImageData,
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
        // bottom tab bar; Quiz / Report Card were removed.)
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
                    // Leaving the shell destroys this view model — an
                    // in-flight reply would stream into the void and leave
                    // the persisted thread permanently unanswered. Cancel
                    // first so the bubble is marked and state is coherent
                    // when the user comes back.
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
            }
        }
        .alert("Reported", isPresented: $showReportConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Thanks — we'll review this response.")
        }
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

/// Scrollable list that auto-scrolls to the bottom when a new message
/// appears or when the last message's content grows (streaming).
struct MessageListView: View {
    let messages: [ChatMessage]
    let phase: ChatViewModel.Phase
    let onRetry: () -> Void
    let onExplainMore: () -> Void
    let onReport: (ChatMessage) -> Void
    /// Lesson styling for the bubbles (presence line + callout + soft shadow).
    var lessonStyle: Bool = false
    /// Tap handler for the lesson check-question callout ("tap the question,
    /// keyboard opens"). Nil keeps the callout non-interactive.
    var onCheckTap: (() -> Void)? = nil
    /// The live focal Merc state, applied to the LATEST assistant message's
    /// avatar (older avatars stay neutral). Avatars render only in free chat.
    var mercMood: MercMood = .neutral
    var mercActivity: MercActivity = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                LazyVStack(alignment: .leading, spacing: BrandSpacing.sm) {
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
                            onReport: { onReport(message) },
                            lessonStyle: lessonStyle,
                            showAvatar: !lessonStyle,
                            avatarMood: isLive ? mercMood : .neutral,
                            avatarActivity: isLive ? mercActivity : .idle,
                            onCheckTap: onCheckTap
                        )
                        .id(message.id)
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
                }
                .padding(.vertical, BrandSpacing.md)
                // Gated like every other explicit animation in the app: under
                // Reduce Motion the intro just disappears (its transition is
                // already opacity-only) instead of sliding the thread up.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25),
                           value: showsCoachIntro)
            }
            .onChange(of: messages.last?.id) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.content) { _, _ in
                // During streaming, keep the bottom anchored so new
                // content is visible without yanking the user around.
                guard let id = messages.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
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
            Button(action: onExplainMore) {
                Label("Explain more", systemImage: "text.alignleft")
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
            .accessibilityLabel("Explain more")
            .accessibilityHint("Asks Mercurius to expand on the previous answer in more depth")
            Spacer()
        }
        .padding(.leading, alignsWithAvatar
            ? BrandSpacing.lg + ChatAvatarMetrics.footprint + BrandSpacing.sm
            : 0)
        .padding(.top, BrandSpacing.xs)
        .padding(.bottom, BrandSpacing.sm)
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
