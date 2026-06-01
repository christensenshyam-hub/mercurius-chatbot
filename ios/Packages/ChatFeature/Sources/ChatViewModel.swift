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

    /// Whether Direct Mode is unlocked for this session. Defaults to
    /// false; updated from the server's `unlocked` flag.
    public private(set) var isUnlocked: Bool = false

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

    // MARK: - Private

    private var streamingTask: Task<Void, Never>?
    private var conversationId: UUID?

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
        store: ChatStore? = nil
    ) {
        self.init(
            chatClient: apiClient,
            modeClient: apiClient,
            sessionIdProvider: { try sessionIdentity.current() },
            store: store,
            imageUploader: apiClient
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
        preparer: ImagePreparing = JPEGImagePreparer()
    ) {
        self.chatClient = chatClient
        self.modeClient = modeClient
        self.sessionIdProvider = sessionIdProvider
        self.store = store
        self.imageUploader = imageUploader
        self.preparer = preparer
        hydrateFromStore()
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
           let convo = store.loadConversation(conversationId: existingId) {
            conversationId = existingId
            if let parsed = ChatMode(rawValue: convo.mode) {
                currentMode = parsed
            }
            messages = convo.messages.compactMap { record -> ChatMessage? in
                guard let role = ChatMessage.Role(rawValue: record.role) else {
                    return nil  // skip unknown roles rather than crashing
                }
                return ChatMessage(
                    id: record.id,
                    role: role,
                    content: record.content,
                    createdAt: record.createdAt,
                    status: .idle
                )
            }
        } else {
            // Fresh install / cleared store: open the first conversation
            // in the default mode.
            conversationId = store.createConversation(mode: currentMode)
        }
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

        let userMessage = ChatMessage(role: .user, content: text, imageData: attachedImage)
        messages.append(userMessage)
        persistMessage(userMessage)
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

        streamingTask = Task { [weak self] in
            await self?.runSend(assistantId: assistantId, responseMode: responseMode, imageData: attachedImage)
        }
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
        streamingTask = Task { [weak self] in
            await self?.runStream(
                assistantId: assistantId,
                responseMode: .deep,
                injectedUserTurn: instruction
            )
        }
    }

    /// Retry the last send after a failure. The last user message stays
    /// in the history; a new assistant placeholder is created.
    public func retry() {
        guard case .failed = phase else { return }
        // Remove the failed assistant bubble if present.
        if let last = messages.last, last.role == .assistant, case .failed = last.status {
            messages.removeLast()
        }
        // Rebuild a fresh placeholder and re-run the stream.
        guard let lastUser = messages.last(where: { $0.role == .user }) else {
            phase = .idle
            return
        }
        // Re-send the last user turn, re-uploading its photo if it had one.
        let imageData = lastUser.imageData
        let placeholder = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(placeholder)
        phase = .sending

        let assistantId = placeholder.id
        let responseMode = lastResponseMode
        streamingTask = Task { [weak self] in
            await self?.runSend(assistantId: assistantId, responseMode: responseMode, imageData: imageData)
        }
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
    /// Mode and unlock state are **preserved** on purpose — they're user
    /// preferences that shouldn't be disturbed by starting a new chat.
    /// The new record is always tagged with `currentMode` so the
    /// "every conversation is mode-locked" invariant holds.
    public func startNewConversation() {
        streamingTask?.cancel()
        streamingTask = nil
        messages = []
        draft = ""
        phase = .idle
        if let store {
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

        streamingTask?.cancel()
        streamingTask = nil
        phase = .idle
        draft = ""

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
    /// Client-side guard: requesting Direct while locked returns an
    /// `APIError.unauthorized` — mapped to a user-facing error rather
    /// than silently dropping. The server is still the source of truth.
    ///
    /// Returns a discardable error for callers that want to surface it;
    /// the UI typically just reads `modeSwitchError` instead.
    public private(set) var modeSwitchError: String?

    @discardableResult
    public func switchMode(to mode: ChatMode) async -> Bool {
        let succeeded = await _serverSyncMode(to: mode)
        if succeeded {
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
    /// updates `currentMode` / `isUnlocked` / `modeSwitchError` /
    /// `modeSwitchInFlight`. Does NOT touch `conversationId` or
    /// `messages`; the caller decides whether to swap the active
    /// thread.
    @discardableResult
    private func _serverSyncMode(to mode: ChatMode) async -> Bool {
        guard mode != currentMode else { return true }
        guard modeSwitchInFlight == nil else { return false }

        // Client-side pre-check: don't even call the server for Direct
        // if we know we're locked. Saves a round trip + 403.
        if mode.requiresUnlock && !isUnlocked {
            modeSwitchError = "Pass the Socratic comprehension check to unlock Direct Mode."
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
            if result.unlocked { isUnlocked = true }
            modeSwitchInFlight = nil
            return true
        } catch APIError.unauthorized {
            modeSwitchInFlight = nil
            modeSwitchError = "Pass the Socratic comprehension check to unlock Direct Mode."
            return false
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
        messages = convo.messages.compactMap { record -> ChatMessage? in
            guard let role = ChatMessage.Role(rawValue: record.role) else { return nil }
            return ChatMessage(
                id: record.id,
                role: role,
                content: record.content,
                createdAt: record.createdAt,
                status: .idle
            )
        }
    }

    /// Dismiss the current mode-switch error from the UI.
    public func clearModeSwitchError() {
        modeSwitchError = nil
    }

    /// Test-only hook. Not exposed publicly; tests in the same package
    /// can call it via `@testable import`. The underscore prefix marks
    /// it as non-production API.
    func _testing_markUnlocked() {
        isUnlocked = true
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

            for try await event in stream {
                if Task.isCancelled { return }

                switch event {
                case .delta(let text):
                    sawAnyDelta = true
                    if phase == .sending { phase = .streaming }
                    appendDelta(text, to: assistantId)

                case .complete(let response):
                    finalize(assistantId: assistantId, fullReply: response.reply)
                    // Server is the source of truth for mode + unlock.
                    if let serverMode = ChatMode(rawValue: response.mode) {
                        currentMode = serverMode
                    }
                    if response.unlocked { isUnlocked = true }
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

            // Stream ended without a `.complete` event. If we saw deltas,
            // commit whatever we have; otherwise treat as failure.
            if sawAnyDelta {
                finalizeFromDeltas(assistantId: assistantId)
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
        messages[idx].content += text
    }

    private func finalize(assistantId: UUID, fullReply: String) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        // Prefer the server's full reply over concatenated deltas in case
        // any deltas were dropped.
        messages[idx].content = fullReply
        messages[idx].status = .idle
        persistMessage(messages[idx])
    }

    private func finalizeFromDeltas(assistantId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
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
