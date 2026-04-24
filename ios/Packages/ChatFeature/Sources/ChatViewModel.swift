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

    // MARK: - Private

    private var streamingTask: Task<Void, Never>?
    private var conversationId: UUID?

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
            store: store
        )
    }

    /// Designated initializer — useful in tests, where stub clients
    /// and a fixed session id can be injected.
    public init(
        chatClient: ChatStreaming,
        modeClient: ModeChanging,
        sessionIdProvider: @escaping @Sendable () throws -> String,
        store: ChatStore? = nil
    ) {
        self.chatClient = chatClient
        self.modeClient = modeClient
        self.sessionIdProvider = sessionIdProvider
        self.store = store
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
    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

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

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persistMessage(userMessage)
        draft = ""

        let assistantPlaceholder = ChatMessage(
            role: .assistant,
            content: "",
            status: .streaming
        )
        messages.append(assistantPlaceholder)
        let assistantId = assistantPlaceholder.id

        phase = .sending

        streamingTask = Task { [weak self] in
            await self?.runStream(assistantId: assistantId)
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
        _ = lastUser  // ensure we have one
        let placeholder = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(placeholder)
        phase = .sending

        let assistantId = placeholder.id
        streamingTask = Task { [weak self] in
            await self?.runStream(assistantId: assistantId)
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

    private func runStream(assistantId: UUID) async {
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

        let history = messages
            .filter { $0.id != assistantId }
            .map(\.dto)

        do {
            let stream = chatClient.streamChat(messages: history, sessionId: sessionId)
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
                    markCurrentFailed(reason: message, isRetryable: true, assistantId: assistantId)
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

    private func markCurrentFailed(reason: String, isRetryable: Bool, assistantId: UUID?) {
        if let id = assistantId, let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].status = .failed(reason: reason)
        }
        phase = .failed(reason: reason, isRetryable: isRetryable)
    }
}
