import Foundation
import Observation
import NetworkingKit

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

    // MARK: - Private

    private var streamingTask: Task<Void, Never>?

    // MARK: - Init

    /// Production initializer — takes the real `APIClient` and a
    /// `SessionIdentity`.
    public convenience init(apiClient: APIClient, sessionIdentity: SessionIdentity) {
        self.init(
            chatClient: apiClient,
            modeClient: apiClient,
            sessionIdProvider: { try sessionIdentity.current() }
        )
    }

    /// Designated initializer — useful in tests, where stub clients
    /// and a fixed session id can be injected.
    public init(
        chatClient: ChatStreaming,
        modeClient: ModeChanging,
        sessionIdProvider: @escaping @Sendable () throws -> String
    ) {
        self.chatClient = chatClient
        self.modeClient = modeClient
        self.sessionIdProvider = sessionIdProvider
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
    }

    private func finalizeFromDeltas(assistantId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { return }
        messages[idx].status = .idle
    }

    private func markCurrentFailed(reason: String, isRetryable: Bool, assistantId: UUID?) {
        if let id = assistantId, let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].status = .failed(reason: reason)
        }
        phase = .failed(reason: reason, isRetryable: isRetryable)
    }
}
