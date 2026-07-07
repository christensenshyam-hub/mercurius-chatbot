import Foundation
import Observation
import NetworkingKit
import PersistenceKit

/// View model for the chat screen.
///
/// Lifecycle:
/// - Constructed with an `APIClient` and a `SessionIdentity`.
/// - Owns the list of visible messages and a draft input.
/// - `send()` appends the user message, opens an SSE stream, and
///   updates the pending assistant message as deltas arrive.
/// - `cancel()` aborts an in-flight request.
///
/// State machine:
/// ```
/// idle → sending → streaming → idle
///          └───→ error (retryable / not)
/// ```
///
/// Isolated to the main actor — all state reads/writes happen on main.
@MainActor
@Observable
public final class ChatViewModel {
    // MARK: - Observable state

    public private(set) var messages: [ChatMessage] = []
    public var draft: String = ""
    public private(set) var phase: Phase = .idle

    /// A photo the user attached to the next message. Drives the composer's
    /// thumbnail; compressed + uploaded when the message is sent. Nil = none.
    public private(set) var pendingImageData: Data?

    /// Active teaching mode. Defaults to Socratic on first launch;
    /// updated from the server on each `complete` event and on
    /// successful `switchMode(to:)` calls.
    public private(set) var currentMode: ChatMode = .socratic

    /// State of an in-flight mode switch, used by the UI to disable
    /// pills and show a progress indicator.
    public private(set) var modeSwitchInFlight: ChatMode?

    public enum Phase: Equatable, Sendable {
        /// No request in flight.
        case idle
        /// Request sent, waiting on first token.
        case sending
        /// Deltas are arriving.
        case streaming
        /// The last request failed. `reason` is safe to show.
        /// `isRetryable` drives the Retry button.
        case failed(reason: String, isRetryable: Bool)
    }

    // MARK: - Dependencies

    private let chatClient: ChatStreaming
    private let modeClient: ModeChanging
    private let sessionIdProvider: @Sendable () throws -> String
    private let store: ChatStore?
    /// Image upload client + preparer for attached photos. `imageUploader` is
    /// nil in tests that don't exercise attachments; the production init wires
    /// the real `APIClient`.
    private let imageUploader: ImageUploading?
    private let preparer: ImagePreparing
    /// Reports objectionable AI responses (App Store Guideline 1.2). Nil in
    /// tests that don't exercise it; the production init wires `APIClient`.
    private let reporting: Reporting?
    /// Engagement stores. Optional — nil in tests that don't exercise
    /// streaks/achievements. Streak is captured from each `complete` event;
    /// achievements are awarded at chat milestones.
    private let streakStore: StreakStore?
    private let achievementStore: AchievementStore?
    /// Standby gamification — set post-init via `configureGamification`. When a
    /// reasoning move is detected in a send, a gated, fire-and-forget event is
    /// requested (the server decides). No-op unless the feature is on.
    @ObservationIgnored private var gamificationStore: GamificationStore?
    @ObservationIgnored private var progressionProvider: ProgressionProviding?

    /// Fired when the lesson is completed this turn (proficiency demonstrated).
    /// Set by the curriculum lesson view; nil for normal chat — so its non-nil
    /// state also marks "this is a lesson conversation".
    @ObservationIgnored public var onLessonComplete: (() -> Void)?

    /// Bumps each time the current turn reports lesson completion (server flag
    /// or a pass marker in the reply text), so the lesson view can present a
    /// celebration. Observable on purpose; distinct from `onLessonComplete`,
    /// which marks progress.
    public private(set) var lessonCompletionEvents = 0

    /// A lesson thread sets `onLessonComplete`; normal chat leaves it nil. Used
    /// to gate marker handling so ordinary chat text is never touched.
    private var isLessonConversation: Bool { onLessonComplete != nil }

    /// Set during streaming if a pass marker arrives in the raw deltas, so a
    /// stream that truncates before its `.complete` event (legacy backend, no
    /// flag) still registers the completion. Reset at the start of each turn.
    @ObservationIgnored private var sawPassMarkerThisTurn = false
    /// The `[CURRICULUM: …]` opener, sent wire-only (hidden from the visible
    /// thread) as the FIRST user message on every lesson turn so the server
    /// keeps the whole lesson — including graded follow-ups — in curriculum mode.
    @ObservationIgnored private var lessonWirePrefix: ChatMessageDTO?

    // MARK: - Private

    private var streamingTask: Task<Void, Never>?
    /// The active conversation id. Public read so the curriculum lesson view can
    /// record it for resume; only the view model mutates it.
    public private(set) var conversationId: UUID?

    /// Response-mode used by the most recent `send` call. `retry()`
    /// reuses this so a failed deep request retries deep, not as a
    /// concise one-off. Defaults to `.concise` (the mobile default).
    private var lastResponseMode: ResponseMode = .concise

    // MARK: - Init

    /// Production initializer — takes the real `APIClient`, a
    /// `SessionIdentity`, and (optionally) a persistence store so
    /// conversations survive app kills.
    public convenience init(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        store: ChatStore? = nil,
        streakStore: StreakStore? = nil,
        achievementStore: AchievementStore? = nil
    ) {
        self.init(
            chatClient: apiClient,
            modeClient: apiClient,
            sessionIdProvider: { try sessionIdentity.current() },
            store: store,
            imageUploader: apiClient,
            reporting: apiClient,
            streakStore: streakStore,
            achievementStore: achievementStore
        )
    }

    /// Designated initializer — useful in tests, where stub clients
    /// and a fixed session id can be injected.
    public init(
        chatClient: ChatStreaming,
        modeClient: ModeChanging,
        sessionIdProvider: @escaping @Sendable () throws -> String,
        store: ChatStore? = nil,
        imageUploader: ImageUploading? = nil,
        preparer: ImagePreparing = JPEGImagePreparer(),
        reporting: Reporting? = nil,
        streakStore: StreakStore? = nil,
        achievementStore: AchievementStore? = nil,
        hydrateOnInit: Bool = true
    ) {
        self.chatClient = chatClient
        self.modeClient = modeClient
        self.sessionIdProvider = sessionIdProvider
        self.store = store
        self.imageUploader = imageUploader
        self.preparer = preparer
        self.reporting = reporting
        self.streakStore = streakStore
        self.achievementStore = achievementStore
        if hydrateOnInit { hydrateFromStore() }
    }

    /// Load the latest persisted conversation, if any. Runs on init
    /// so the UI can render immediately without a loading flicker.
    ///
    /// Mode-resume policy: pick the conversation that was most
    /// recently updated across every mode and adopt ITS mode as the
    /// current one. That way a user who was in Debate when the app
    /// quit lands back in Debate on relaunch — without any persisted
    /// "current mode" pref of our own. The server's mode is still the
    /// source of truth for backend behavior; `switchMode` syncs them.
    private func hydrateFromStore() {
        guard let store else { return }
        if let existingId = store.latestConversationId(),
           let convo = store.loadConversation(conversationId: existingId),
           let parsed = ChatMode(rawValue: convo.mode) {
            conversationId = existingId
            currentMode = parsed
            messages = convo.messages.compactMap(Self.hydratedMessage)
        } else {
            // Fresh install, cleared store — or the latest record carries a
            // mode this build no longer knows (e.g. the retired "direct"
            // from shipped betas). Never adopt an unknown-mode thread as
            // the writable active conversation: new turns would persist
            // into a record whose tag lies about its contents, breaking the
            // mode-locked invariant. The legacy thread stays in History.
            conversationId = store.createConversation(mode: currentMode)
        }
    }

    /// Rebuild one persisted record as a renderable message. Unknown roles
    /// are skipped rather than crashing. Empty user content — a photo-only
    /// turn persisted by an older build (image bytes are in-memory only) —
    /// is healed to the same placeholder new sends use, so the turn stays
    /// visible and its replay is never rejected as empty content.
    private static func hydratedMessage(_ record: StoredMessage) -> ChatMessage? {
        guard let role = ChatMessage.Role(rawValue: record.role) else { return nil }
        var content = record.content
        if role == .user, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = "[Shared an image]"
        }
        return ChatMessage(
            id: record.id,
            role: role,
            content: content,
            createdAt: record.createdAt,
            status: .idle
        )
    }

    /// Ensure a conversation exists and return its id. Creates one in
    /// the current mode lazily if the store is present but no
    /// conversation has been opened yet. Returns `nil` if no store is
    /// attached.
    private func ensureConversationId() -> UUID? {
        guard let store else { return nil }
        if let existing = conversationId { return existing }
        let fresh = store.createConversation(mode: currentMode)
        conversationId = fresh
        return fresh
    }

    private func persistMessage(_ message: ChatMessage) {
        guard let store, let convoId = ensureConversationId() else { return }
        store.append(
            StoredMessage(
                id: message.id,
                role: message.role.rawValue,
                content: message.content,
                createdAt: message.createdAt
            ),
            to: convoId
        )
    }

    // MARK: - Actions

    /// Send the current draft as a user message.
    ///
    /// No-op if the draft is empty or a request is already in flight.
    /// After a previous failure, sending a new message drops the failed
    /// assistant bubble so the history stays clean.
    ///
    /// `responseMode` controls the answer's length / depth. The default
    /// is `.concise` — the mobile-native short answer. The "Explain
    /// more" affordance flips this to `.deep` for one round; see
    /// `explainMore()`.
    /// Attach a photo to the next message. Shown as a thumbnail in the
    /// composer; compressed + uploaded when the message is sent.
    public func attachImage(data: Data) {
        pendingImageData = data
    }

    /// Remove the pending photo attachment.
    public func clearAttachment() {
        pendingImageData = nil
    }

    public func send(responseMode: ResponseMode = .concise) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachedImage = pendingImageData
        // Allow sending text, a photo, or both — but not nothing.
        guard !text.isEmpty || attachedImage != nil else { return }

        switch phase {
        case .sending, .streaming:
            return  // in flight — ignore
        case .idle:
            break
        case .failed:
            // Drop the trailing failed assistant bubble, if any.
            if let last = messages.last,
               last.role == .assistant,
               case .failed = last.status {
                messages.removeLast()
            }
        }

        // A photo-only turn must never carry empty content: Anthropic
        // rejects empty user text when the thread is replayed on later
        // curriculum turns (bricking the lesson), and an empty persisted
        // turn hydrates as an invisible message after relaunch. Mirror the
        // server's own dbHistory substitution.
        let content = text.isEmpty && attachedImage != nil ? "[Shared an image]" : text
        let userMessage = ChatMessage(role: .user, content: content, imageData: attachedImage)
        messages.append(userMessage)
        persistMessage(userMessage)
        awardSendAchievements()
        recordReasoningMove(from: text)
        draft = ""
        pendingImageData = nil

        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            content: "",
            status: .streaming
        )
        messages.append(assistantPlaceholder)
        let assistantId = assistantPlaceholder.id

        phase = .sending
        lastResponseMode = responseMode
        lastRequest = LastRequest(responseMode: responseMode,
                                  injectedUserTurn: nil,
                                  imageData: attachedImage)

        streamingTask = Task { [weak self] in
            await self?.runSend(assistantId: assistantId, responseMode: responseMode, imageData: attachedImage)
        }
    }

    /// Attach the standby gamification store + provider after init (avoids a
    /// SwiftUI @State ordering problem at the call site). The feature stays
    /// no-op when off — `recordEvent` is gated in the store.
    public func configureGamification(store: GamificationStore, provider: ProgressionProviding) {
        self.gamificationStore = store
        self.progressionProvider = provider
    }

    /// Detect a reasoning move in the user's turn and request a gated XP
    /// evaluation (the server decides, validates, and caps). Fire-and-forget;
    /// never blocks the send. No-op unless gamification is configured + on.
    private func recordReasoningMove(from userText: String) {
        guard let gamificationStore, let provider = progressionProvider,
              let reason = ReasoningMoveDetector.detect(in: userText),
              let sid = try? sessionIdProvider() else { return }
        Task { await gamificationStore.recordEvent(using: provider, sessionId: sid, reason: reason, sourceType: "chat") }
    }

    /// Upload the attached photo (if any), then open the chat stream with its
    /// id so the server can show it to Claude. Upload failures mark the turn
    /// failed (retryable) without ever opening the stream.
    private func runSend(assistantId: UUID, responseMode: ResponseMode, imageData: Data?) async {
        var imageId: String?
        if let imageData, let uploader = imageUploader {
            do {
                let sessionId = try sessionIdProvider()
                let preparer = self.preparer
                let input = try await Task.detached(priority: .userInitiated) {
                    try preparer.prepare(imageData: imageData, fileName: nil)
                }.value
                if Task.isCancelled { return }
                let response = try await uploader.uploadImage(input, sessionId: sessionId)
                imageId = response.id
            } catch is CancellationError {
                return
            } catch let error as APIError {
                markCurrentFailed(reason: error.userFacingMessage, isRetryable: error.isRetryable, assistantId: assistantId)
                return
            } catch {
                markCurrentFailed(reason: "Couldn't attach that photo. Try again.", isRetryable: true, assistantId: assistantId)
                return
            }
        }
        await runStream(assistantId: assistantId, responseMode: responseMode, imageId: imageId)
    }

    /// "Explain more" — asks the model to expand on the previous reply
    /// with a `deep` token budget. The instruction is sent on the wire
    /// as an injected user turn but NEVER added to the visible chat
    /// thread or to local persistence. From the user's perspective,
    /// tapping the button just produces a new, deeper assistant reply
    /// in place — no "Explain more" message appears in their history.
    ///
    /// Server-side that injected turn does land in the SQLite memory
    /// table on the chat path, which is fine — that table feeds the
    /// model's memory profile and isn't replayed into the user-visible
    /// conversation.
    ///
    /// No-op if the chat is empty, the last turn isn't from the
    /// assistant, or a request is already in flight.
    public func explainMore() {
        guard let last = messages.last, last.role == .assistant else { return }
        guard !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if case .sending = phase { return }
        if case .streaming = phase { return }

        // Drop a previous failed bubble if there is one, mirroring
        // `send()`'s housekeeping.
        if case .failed = phase,
           let trailing = messages.last,
           trailing.role == .assistant,
           case .failed = trailing.status {
            messages.removeLast()
        }

        let placeholder = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(placeholder)
        let assistantId = placeholder.id

        phase = .sending
        lastResponseMode = .deep

        let instruction = "Explain more — go deeper on the same topic. Don't repeat what you already said."
        lastRequest = LastRequest(responseMode: .deep,
                                  injectedUserTurn: instruction,
                                  imageData: nil)
        streamingTask = Task { [weak self] in
            await self?.runStream(
                assistantId: assistantId,
                responseMode: .deep,
                injectedUserTurn: instruction
            )
        }
    }

    // MARK: - Curriculum lessons (persisted + resumable)

    /// A lesson view model: persists to `store` (for resume) but does NOT
    /// hydrate the latest main conversation. Pair with `beginLessonConversation`
    /// (new lesson) or `resumeLesson` (continue a saved one).
    public static func makeLesson(
        apiClient: APIClient,
        sessionIdentity: SessionIdentity,
        store: ChatStore?,
        streakStore: StreakStore? = nil,
        achievementStore: AchievementStore? = nil
    ) -> ChatViewModel {
        ChatViewModel(
            chatClient: apiClient,
            modeClient: apiClient,
            sessionIdProvider: { try sessionIdentity.current() },
            store: store,
            imageUploader: apiClient,
            reporting: apiClient,
            streakStore: streakStore,
            achievementStore: achievementStore,
            hydrateOnInit: false
        )
    }

    /// Start a NEW lesson: create a curriculum-tagged conversation, anchor the
    /// `[CURRICULUM: …]` opener as a hidden wire prefix (so every turn — opener
    /// and graded follow-ups — stays in curriculum mode), and stream the first
    /// reply. The raw opener is never shown. Returns the conversation id for the
    /// resume mapping. Only valid on an empty thread.
    @discardableResult
    public func beginLessonConversation(starter: String) -> UUID? {
        guard messages.isEmpty else { return conversationId }
        lessonWirePrefix = ChatMessageDTO(role: "user", content: Self.withCompletionContract(starter))
        let convoId = store?.createCurriculumConversation()
        if let convoId { conversationId = convoId }

        let placeholder = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(placeholder)
        phase = .sending
        lastResponseMode = .balanced
        lastRequest = LastRequest(responseMode: .balanced,
                                  injectedUserTurn: nil,
                                  imageData: nil)
        streamingTask = Task { [weak self] in
            await self?.runStream(assistantId: placeholder.id, responseMode: .balanced)
        }
        return convoId
    }

    /// Resume a saved lesson: load its persisted transcript and re-anchor the
    /// curriculum wire prefix so follow-ups stay in curriculum mode. Does NOT
    /// re-send the opener. Returns false if the saved conversation is gone —
    /// or empty: nothing persists until the first reply finalizes, so a
    /// zero-message record means the opener stream never finished (Stop /
    /// app-kill / network error mid-first-reply). Reporting false lets the
    /// host start fresh and re-send the opener instead of presenting a blank
    /// lesson that never teaches.
    @discardableResult
    public func resumeLesson(conversationId: UUID, starter: String) async -> Bool {
        lessonWirePrefix = ChatMessageDTO(role: "user", content: Self.withCompletionContract(starter))
        let opened = await openConversation(id: conversationId)
        return opened && !messages.isEmpty
    }

    /// The lesson opener plus the completion contract. The current backend's
    /// curriculum prompt already instructs the `[LESSON_COMPLETE]` marker, but
    /// the deployed legacy generation's prompt does not — embedding the
    /// contract in the opener makes completion detectable against BOTH server
    /// generations (the client's `LessonMarker` fallback recognizes and strips
    /// the marker either way).
    private static func withCompletionContract(_ starter: String) -> String {
        starter + " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line."
    }

    /// The request that was actually sent on the wire, captured at every
    /// send site so `retry()` can replay it verbatim. Inferring the request
    /// from the visible thread breaks for wire-only turns: the explain-more
    /// instruction and the lesson opener never appear in `messages`, so a
    /// rebuilt history would end on an assistant turn (a deterministic 400)
    /// or — for a failed lesson opener — contain nothing to re-send at all.
    /// Cleared whenever the active thread changes.
    private struct LastRequest {
        var responseMode: ResponseMode
        var injectedUserTurn: String?
        var imageData: Data?
    }
    private var lastRequest: LastRequest?

    /// Retry the last send after a failure. The last user message stays
    /// in the history; a new assistant placeholder is created and the
    /// failed request is replayed exactly as it originally went out.
    public func retry() {
        guard case .failed = phase else { return }
        // Remove the failed assistant bubble if present.
        if let last = messages.last, last.role == .assistant, case .failed = last.status {
            messages.removeLast()
        }
        guard let request = lastRequest ?? fallbackRequestFromVisibleThread() else {
            phase = .idle
            return
        }
        let placeholder = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(placeholder)
        phase = .sending
        lastResponseMode = request.responseMode

        let assistantId = placeholder.id
        streamingTask = Task { [weak self] in
            if let imageData = request.imageData {
                // Re-send the last user turn, re-uploading its photo.
                await self?.runSend(assistantId: assistantId,
                                    responseMode: request.responseMode,
                                    imageData: imageData)
            } else {
                await self?.runStream(assistantId: assistantId,
                                      responseMode: request.responseMode,
                                      injectedUserTurn: request.injectedUserTurn)
            }
        }
    }

    /// Reconstruct a replayable request from the visible thread — the
    /// pre-capture behavior, kept as a fallback. A lesson whose wire-only
    /// opener failed has no visible user turn, but the wire prefix still
    /// carries the opener, so a bare stream re-sends it.
    private func fallbackRequestFromVisibleThread() -> LastRequest? {
        guard let lastUser = messages.last(where: { $0.role == .user }) else {
            return lessonWirePrefix != nil
                ? LastRequest(responseMode: .balanced, injectedUserTurn: nil, imageData: nil)
                : nil
        }
        return LastRequest(responseMode: lastResponseMode,
                           injectedUserTurn: nil,
                           imageData: lastUser.imageData)
    }

    /// Cancel any in-flight request. The assistant bubble is marked
    /// failed so the user sees why it stopped.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        markCurrentFailed(
            reason: "Cancelled.",
            isRetryable: true,
            assistantId: messages.last?.id
        )
    }

    /// Report an assistant message as objectionable (App Store Guideline 1.2).
    /// Fire-and-forget — the UI confirms optimistically; a failed submission is
    /// silently dropped rather than nagging the user.
    public func reportMessage(_ message: ChatMessage) {
        guard let reporting, message.role == .assistant else { return }
        // Strip the lesson [CHECK]…[/CHECK] callout markers so the moderation
        // payload carries clean reply text, not the internal markup.
        let content = message.content
            .replacingOccurrences(of: "[CHECK]", with: "")
            .replacingOccurrences(of: "[/CHECK]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let sessionIdProvider = self.sessionIdProvider
        Task {
            guard let sessionId = try? sessionIdProvider() else { return }
            try? await reporting.reportResponse(content: content, reason: nil, sessionId: sessionId)
        }
    }

    // MARK: - Engagement (streaks + achievements)

    /// Achievements that fire from sending a message: first conversation, deep
    /// diver (20+ user turns in this conversation), and the current mode's badge.
    private func awardSendAchievements() {
        achievementStore?.award(AchievementCatalog.firstConversation)
        let userTurns = messages.filter { $0.role == .user }.count
        if userTurns >= 20 { achievementStore?.award(AchievementCatalog.deepDiver) }
        awardModeAchievementsIfNeeded()
    }

    /// Record streak signals from a chat `complete` event: cache the
    /// server's authoritative streak and award any streak-milestone
    /// badges. Idempotent.
    private func recordSessionSignals(_ response: ChatResponse) {
        if let streak = response.streak {
            streakStore?.update(streak: streak)
            for id in AchievementCatalog.streakMilestones(for: streak) {
                achievementStore?.award(id)
            }
        }
    }

    /// Award badges tied to the current mode (currently: Debate). Idempotent.
    private func awardModeAchievementsIfNeeded() {
        if currentMode == .debate { achievementStore?.award(AchievementCatalog.debater) }
    }

    /// Start a fresh conversation.
    ///
    /// - Cancels any in-flight streaming task silently (no "Cancelled"
    ///   bubble is left behind — unlike `cancel()`, which is for the
    ///   user pressing stop during a reply).
    /// - Clears all visible messages and the draft.
    /// - Resets `phase` to `.idle`.
    /// - If a persistence store is attached, opens a brand-new
    ///   conversation record. Prior conversations stay on disk so
    ///   history could be surfaced later, but are no longer shown.
    ///
    /// Mode is **preserved** on purpose — it's a user preference that
    /// shouldn't be disturbed by starting a new chat. The new record is
    /// always tagged with `currentMode` so the "every conversation is
    /// mode-locked" invariant holds.
    public func startNewConversation() {
        streamingTask?.cancel()
        streamingTask = nil
        let hadMessages = !messages.isEmpty
        messages = []
        draft = ""
        phase = .idle
        lastRequest = nil
        // Don't mint another record when the active thread is already a
        // fresh empty one — repeated New Chat taps would otherwise litter
        // Chat History with permanent zero-message "New chat" rows.
        if let store, conversationId == nil || hadMessages {
            conversationId = store.createConversation(mode: currentMode)
        }
    }

    /// Reopen an archived conversation by id. Loads its messages,
    /// adopts its mode (firing the server-side switchMode if the mode
    /// differs from the current one), and makes it the active thread.
    ///
    /// No-op if the store is missing or the id is unknown.
    /// Cancels any in-flight stream before swapping — letting the
    /// stream finish into a different conversation than the user
    /// is now looking at would be confusing.
    @discardableResult
    public func openConversation(id: UUID) async -> Bool {
        guard let store, let convo = store.loadConversation(conversationId: id) else {
            return false
        }
        // A record whose mode this build no longer knows (e.g. the retired
        // "direct" from shipped betas) can't become the writable active
        // thread — new turns would persist under a mode tag that lies about
        // the contents. Curriculum threads carry their own tag and open
        // through `resumeLesson`.
        guard ChatMode(rawValue: convo.mode) != nil || convo.mode == ChatStoreTag.curriculum else {
            return false
        }

        streamingTask?.cancel()
        streamingTask = nil
        phase = .idle
        draft = ""
        lastRequest = nil   // a failed request must not replay into this thread

        // Adopt mode FIRST (server side) so the conversation we're
        // about to render matches the model's behavior. Use the
        // private `_serverSyncMode` rather than the public
        // `switchMode` so the latter's "swap to latest in mode"
        // step doesn't fight us — we want to load THIS specific
        // conversation, not the most recent one in its mode.
        //
        // If the server-side switch fails we still load the
        // conversation (the user explicitly asked to reopen it)
        // and surface the error via `modeSwitchError`. Subsequent
        // sends would hit the wrong server mode in that edge case,
        // but the UI makes the failure visible.
        if let mode = ChatMode(rawValue: convo.mode), mode != currentMode {
            await _serverSyncMode(to: mode)
        }

        applyLoadedConversation(convo)
        return true
    }

    /// Lightweight read of the saved conversation list, used by the
    /// Chat History screen. Returns an empty list if no store is
    /// attached.
    public func archivedConversations() -> [ConversationSummary] {
        store?.listConversations() ?? []
    }

    /// Delete an archived conversation. If the deleted one is the
    /// active conversation, behavior matches `startNewConversation`
    /// for the current mode so the chat surface doesn't end up
    /// pointing at a phantom id.
    public func deleteConversation(id: UUID) {
        guard let store else { return }
        let wasActive = (conversationId == id)
        store.delete(conversationId: id)
        if wasActive {
            startNewConversation()
        }
    }

    /// Ask the server to switch the active teaching mode.
    ///
    /// Returns a discardable error for callers that want to surface it;
    /// the UI typically just reads `modeSwitchError` instead.
    public private(set) var modeSwitchError: String?

    @discardableResult
    public func switchMode(to mode: ChatMode) async -> Bool {
        let succeeded = await _serverSyncMode(to: mode)
        if succeeded {
            // Abandon any in-flight reply before swapping (mirrors
            // `openConversation`): a stream finishing into a conversation
            // the user just swapped away from would render nothing, persist
            // nothing, and let its stale `.complete` snap `currentMode`
            // back to the old mode.
            streamingTask?.cancel()
            streamingTask = nil
            phase = .idle
            // Mode-switch (via the pill) feels like switching
            // workspaces — the chat thread changes too, not just a
            // setting somewhere off-screen. `openConversation` calls
            // `_serverSyncMode` directly and bypasses this swap so
            // it can load a specific archived conversation.
            swapActiveConversation(forMode: currentMode)
        }
        return succeeded
    }

    /// Server side of the mode switch — talks to the backend,
    /// updates `currentMode` / `modeSwitchError` /
    /// `modeSwitchInFlight`. Does NOT touch `conversationId` or
    /// `messages`; the caller decides whether to swap the active
    /// thread.
    @discardableResult
    private func _serverSyncMode(to mode: ChatMode) async -> Bool {
        guard mode != currentMode else { return true }
        guard modeSwitchInFlight == nil else {
            // Surface the skip: `openConversation` ignores the returned Bool,
            // and a silent skip would leave the thread rendering in one mode
            // while the server session sits in another.
            modeSwitchError = "Another mode switch is in progress. Try again."
            return false
        }

        modeSwitchError = nil
        modeSwitchInFlight = mode

        let sessionId: String
        do {
            sessionId = try sessionIdProvider()
        } catch {
            modeSwitchInFlight = nil
            modeSwitchError = "Could not resolve session."
            return false
        }

        do {
            let result = try await modeClient.changeMode(to: mode, sessionId: sessionId)
            if let parsed = ChatMode(rawValue: result.mode) {
                currentMode = parsed
            }
            awardModeAchievementsIfNeeded()
            modeSwitchInFlight = nil
            return true
        } catch let error as APIError {
            modeSwitchInFlight = nil
            modeSwitchError = error.userFacingMessage
            return false
        } catch {
            modeSwitchInFlight = nil
            modeSwitchError = "Could not change mode. Try again."
            return false
        }
    }

    /// Swap the visible thread to the latest conversation in `mode`,
    /// creating a fresh one if no prior conversation exists for that
    /// mode. Used by the public `switchMode` and by tests.
    private func swapActiveConversation(forMode mode: ChatMode) {
        guard let store else { return }
        lastRequest = nil   // a failed request must not replay into this thread
        if let id = store.latestConversationId(in: mode),
           let convo = store.loadConversation(conversationId: id) {
            applyLoadedConversation(convo)
        } else {
            let newId = store.createConversation(mode: mode)
            conversationId = newId
            messages = []
        }
    }

    /// Apply an already-fetched conversation: update id + hydrate
    /// in-memory messages. Shared by `swapActiveConversation` and
    /// `openConversation`.
    private func applyLoadedConversation(_ convo: StoredConversation) {
        conversationId = convo.id
        messages = convo.messages.compactMap(Self.hydratedMessage)
    }

    /// Dismiss the current mode-switch error from the UI.
    public func clearModeSwitchError() {
        modeSwitchError = nil
    }

    /// The `[CURRICULUM: Unit X, Lesson Y]` tag extracted from the lesson's
    /// wire prefix, for re-tagging follow-up turns (legacy-server bridge).
    private var curriculumTurnTag: String? {
        guard let content = lessonWirePrefix?.content, content.hasPrefix("["),
              let close = content.firstIndex(of: "]") else { return nil }
        return String(content[...close])
    }

    /// Bound the outbound history to what the server will actually use:
    /// at most `maxMessages` (matching the server's own trim) and roughly
    /// `maxBytes` of content (safely under the 32kb JSON body limit),
    /// dropping oldest turns first. Never drops the latest turn, and never
    /// leaves an assistant turn first — Anthropic requires the replayed
    /// thread to start with a user message.
    static func cappedHistory(
        _ history: [ChatMessageDTO],
        maxMessages: Int = 40,
        maxBytes: Int = 24_000
    ) -> [ChatMessageDTO] {
        var trimmed = Array(history.suffix(maxMessages))
        var bytes = trimmed.reduce(0) { $0 + $1.content.utf8.count }
        while bytes > maxBytes, trimmed.count > 1 {
            bytes -= trimmed.removeFirst().content.utf8.count
        }
        while let first = trimmed.first, first.role == "assistant", trimmed.count > 1 {
            trimmed.removeFirst()
        }
        return trimmed
    }

    // MARK: - Streaming

    /// `injectedUserTurn`: an extra user-role wire message appended to
    /// the request history but NOT shown in the local chat UI. Used by
    /// `explainMore()` so the "go deeper, don't repeat" instruction
    /// reaches the model without polluting the visible thread. Nil
    /// for normal sends.
    private func runStream(
        assistantId: UUID,
        responseMode: ResponseMode,
        injectedUserTurn: String? = nil,
        imageId: String? = nil
    ) async {
        let sessionId: String
        do {
            sessionId = try sessionIdProvider()
        } catch {
            markCurrentFailed(
                reason: "Could not resolve session. Please restart the app.",
                isRetryable: false,
                assistantId: assistantId
            )
            return
        }

        var history = messages
            .filter { $0.id != assistantId }
            .map(\.dto)
        // Cap the outbound thread. The server rebuilds ordinary-chat context
        // from its own DB and trims curriculum replays to its last 40 anyway,
        // while express's 32kb JSON body cap 413s an unbounded payload long
        // before that — permanently, since Retry would re-send the same bytes.
        history = Self.cappedHistory(history)
        // Lesson turns carry the [CURRICULUM: …] opener as a hidden first wire
        // message so the server keeps the whole lesson in curriculum mode —
        // including the graded follow-ups where [LESSON_COMPLETE] is emitted.
        if let lessonWirePrefix {
            history.insert(lessonWirePrefix, at: 0)
            // Legacy-server bridge: the deployed production generation detects
            // curriculum mode from the LAST user message only, so tag the
            // outgoing final user turn too. Wire-only — the visible thread is
            // untouched, and the current server's any-message detection is
            // unaffected by the extra tag.
            if let tag = curriculumTurnTag,
               let lastUserIdx = history.lastIndex(where: { $0.role == "user" }),
               !history[lastUserIdx].content.hasPrefix("[CURRICULUM") {
                history[lastUserIdx] = ChatMessageDTO(
                    role: "user",
                    content: tag + " " + history[lastUserIdx].content
                )
            }
        }
        if let injectedUserTurn {
            history.append(ChatMessageDTO(role: "user", content: injectedUserTurn))
        }

        do {
            let stream = chatClient.streamChat(
                messages: history,
                sessionId: sessionId,
                responseMode: responseMode,
                imageId: imageId
            )
            var sawAnyDelta = false
            sawPassMarkerThisTurn = false

            for try await event in stream {
                if Task.isCancelled { return }

                switch event {
                case .delta(let text):
                    sawAnyDelta = true
                    if phase == .sending { phase = .streaming }
                    appendDelta(text, to: assistantId)

                case .complete(let response):
                    finalize(assistantId: assistantId, fullReply: response.reply)
                    // Server is the source of truth for mode.
                    if let serverMode = ChatMode(rawValue: response.mode) {
                        currentMode = serverMode
                    }
                    recordSessionSignals(response)
                    // Lesson completion: the current backend sets `lessonComplete`;
                    // the legacy backend only emits a pass marker inline. Either
                    // one advances the lesson (and triggers the celebration).
                    let lessonPassed = response.lessonComplete == true
                        || (isLessonConversation && LessonMarker.indicatesCompletion(response.reply))
                    if lessonPassed {
                        onLessonComplete?()
                        lessonCompletionEvents += 1
                    }
                    awardModeAchievementsIfNeeded()
                    phase = .idle
                    return

                case .streamError(let message):
                    // Server-side and upstream errors sometimes arrive
                    // with raw JSON / status-code-prefixed bodies baked
                    // into the SSE error event. Sanitize before
                    // showing — internal API JSON is never useful to a
                    // student.
                    markCurrentFailed(
                        reason: Self.sanitize(streamErrorMessage: message),
                        isRetryable: true,
                        assistantId: assistantId
                    )
                    return
                }
            }

            // A cancelled consumer ends stream iteration by returning nil
            // (it does NOT throw), so control falls through to here. The
            // canceller (Stop, New Chat, opening another thread) has already
            // reset or re-marked state — never finalize a truncated reply or
            // plant a failure over what it set.
            if Task.isCancelled { return }

            // Stream ended without a `.complete` event. If we saw deltas,
            // commit whatever we have; otherwise treat as failure.
            if sawAnyDelta {
                finalizeFromDeltas(assistantId: assistantId)
                // A legacy stream can drop after the pass marker but before
                // `.complete`; honor the completion we saw in the deltas.
                if isLessonConversation, sawPassMarkerThisTurn {
                    onLessonComplete?()
                    lessonCompletionEvents += 1
                }
                phase = .idle
            } else {
                markCurrentFailed(
                    reason: "The server closed the connection without a response.",
                    isRetryable: true,
                    assistantId: assistantId
                )
            }
        } catch let error as APIError {
            markCurrentFailed(
                reason: error.userFacingMessage,
                isRetryable: error.isRetryable,
                assistantId: assistantId
            )
        } catch is CancellationError {
            markCurrentFailed(reason: "Cancelled.", isRetryable: true, assistantId: assistantId)
        } catch {
            markCurrentFailed(
                reason: "Something went wrong. Try again.",
                isRetryable: true,
                assistantId: assistantId
            )
        }
    }

    // MARK: - State mutations

    private func appendDelta(_ text: String, to id: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let combined = messages[idx].content + text
        if isLessonConversation {
            // Note any pass marker in the RAW stream before scrubbing, so a
            // truncated stream (no `.complete`) still registers completion.
            if !sawPassMarkerThisTurn, LessonMarker.indicatesCompletion(combined) {
                sawPassMarkerThisTurn = true
            }
            // Scrub control markers as they stream so a legacy `[TEST_PASSED]`
            // never flashes in the transcript.
            messages[idx].content = LessonMarker.removingMarkers(combined)
        } else {
            messages[idx].content = combined
        }
    }

    private func finalize(assistantId: UUID, fullReply: String) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        // Prefer the server's full reply over concatenated deltas in case any
        // deltas were dropped.
        guard isLessonConversation else {
            messages[idx].content = fullReply
            messages[idx].status = .idle
            persistMessage(messages[idx])
            return
        }
        // In a lesson, strip any inline control markers a backend may have left.
        // If the reply was NOTHING but a marker (cleans to empty), substitute a
        // short confirmation — never render or persist the raw token. Mirrors the
        // server's fallback in lib/lessonOutcome.js.
        let cleaned = LessonMarker.cleaned(fullReply)
        messages[idx].content = cleaned.isEmpty ? "Lesson complete — nice work." : cleaned
        messages[idx].status = .idle
        persistMessage(messages[idx])
    }

    private func finalizeFromDeltas(assistantId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        if isLessonConversation {
            // Mirror `finalize()`: deltas were marker-scrubbed as they
            // streamed, so a truncated marker-only reply leaves empty
            // content — substitute rather than render/persist a blank
            // bubble (an empty assistant turn would also be rejected when
            // the curriculum thread is replayed on later turns).
            let cleaned = LessonMarker.cleaned(messages[idx].content)
            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[idx].content = sawPassMarkerThisTurn
                    ? "Lesson complete — nice work."
                    : "Got it."
            } else {
                messages[idx].content = cleaned
            }
        }
        messages[idx].status = .idle
        persistMessage(messages[idx])
    }

    /// Defensive sanitizer for the message that arrives via an SSE
    /// `error` event. Three cases, in priority order:
    ///
    /// 1. **Recognized billing / quota errors** (Anthropic credits,
    ///    Stripe-style "billing", or `invalid_request_error` from
    ///    upstream) → a service-down message. The student can't fix
    ///    this; surfacing the raw text just embarrasses us.
    /// 2. **Anything that looks like raw JSON** (starts with `{` /
    ///    `[`, or `<status_code> {…}`) → a generic "can't reach the AI"
    ///    message. JSON is never appropriate UI text.
    /// 3. **Otherwise** → trust it and pass through (covers the
    ///    legitimate "rate limit" / "upstream_timeout" / etc. cases
    ///    where the server already produces user-readable strings).
    ///
    /// Internal so unit tests in the same package can pin the
    /// individual branches; `static` because it has no view-model
    /// state dependency.
    static func sanitize(streamErrorMessage raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        // 1. Known billing / quota signatures.
        let billingMarkers = [
            "credit balance",
            "billing",
            "invalid_request_error",
            "insufficient_quota",
        ]
        if billingMarkers.contains(where: lowered.contains) {
            return "Mercurius can't reach the AI right now. We're aware — please try again in a few minutes."
        }

        // 2. Any JSON-shaped payload — "{...}", "[...]", or
        //    "<digits> {..." (a status-code prefix from a layer that
        //    unhelpfully concatenated the response body).
        let firstChar = trimmed.first
        let looksLikeJSON = firstChar == "{" || firstChar == "["
        let looksLikeStatusPrefixedJSON: Bool = {
            guard let firstChar, firstChar.isNumber else { return false }
            return trimmed.contains("{") || trimmed.contains("[")
        }()
        if looksLikeJSON || looksLikeStatusPrefixedJSON {
            return "Mercurius can't reach the AI right now. Please try again."
        }

        // 3. Trust the server's text.
        return trimmed.isEmpty ? "Something went wrong. Try again." : trimmed
    }

    private func markCurrentFailed(reason: String, isRetryable: Bool, assistantId: UUID?) {
        if let id = assistantId, let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].status = .failed(reason: reason)
        }
        phase = .failed(reason: reason, isRetryable: isRetryable)
    }
}
