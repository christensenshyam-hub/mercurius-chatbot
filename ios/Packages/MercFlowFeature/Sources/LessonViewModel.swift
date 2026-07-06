import SwiftUI
import Combine
import DesignSystem

/// The lesson flow + reaction state machine — from `MERC_HANDOFF.md` Part B §3,
/// mirroring `Mercurius Flow.dc.html`. Self-contained demo content (the streamed
/// reply + exercise are scripted); wiring to the real backend is a later step.

enum Stage { case intro, chat, exercise, celebrate, done }

struct ChatMessage: Identifiable { let id = UUID(); let role: Role; var text: String
    enum Role { case merc, user } }

@MainActor
final class LessonViewModel: ObservableObject {
    @Published var stage: Stage = .intro
    @Published var merc: MercState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var progress: Double = 0.62      // 5/8
    @Published var answered = false
    @Published var showWrong = false
    @Published var hintOpen = false

    private var idleTask: Task<Void, Never>?
    private var revertTask: Task<Void, Never>?
    private let idleTimeout: UInt64 = 60_000_000_000   // 60s (prototype used 12s)

    // MARK: lifecycle
    func onAppear() {
        setStage(.intro)                  // intro rests at idle; no sleep timer here
        merc = .wave                      // transient greeting, then settle
        revert(to: .idle, after: 1.8)
    }

    /// The resting state each stage shows, before transient overrides (wave on
    /// open, thinking while streaming). Sleep is NOT a base state — it's only
    /// reached via the idle timer, which is armed in `.chat` alone.
    private func baseState(for stage: Stage) -> MercState {
        switch stage {
        case .intro, .chat, .exercise, .done: return .idle
        case .celebrate:                       return .celebrate
        }
    }

    /// Route ALL stage changes through here so Merc's state is a deterministic
    /// function of the stage and the idle→sleep timer is armed only in `.chat`.
    func setStage(_ s: Stage) {
        stage = s
        merc = baseState(for: s)
        idleTask?.cancel()                // clear any pending sleep
        if s == .chat { resetIdle() }     // ONLY chat can drift to sleep
    }

    // MARK: intro → chat
    func startChat() {
        setStage(.chat)
        messages = [.init(role: .merc,
            text: "You aced Lesson 1 — now you're mid-way through Lesson 2. Here's the key idea: during pre-training the model adjusts billions of weights so patterns in its text become predictable. It keeps the patterns — not copies of the pages.")]
        bump()
    }

    // MARK: chat send → thinking → streamed reply
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, merc != .thinking else { return }
        messages.append(.init(role: .user, text: text))
        input = ""; merc = .thinking; resetIdle()

        Task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            await stream("Good question. It never stores the text itself — it learns the statistical shape of language so it can predict the next token. That's why we say it learns patterns, not pages.")
            merc = .idle; resetIdle()
        }
    }

    private func stream(_ full: String) async {
        var shown = ""
        messages.append(.init(role: .merc, text: ""))
        let idx = messages.count - 1
        for ch in full {
            shown.append(ch)
            messages[idx].text = shown
            try? await Task.sleep(nanoseconds: 12_000_000)   // ~12ms/char
        }
    }

    func goExercise() { setStage(.exercise); bump() }

    // MARK: exercise answer
    func answer(correct: Bool) {
        guard !answered else { return }
        if correct {
            answered = true
            progress = 0.75            // 6/8
            setStage(.celebrate)       // celebrate is the .celebrate base state
        } else {
            showWrong = true
        }
    }

    func toggleHint() { hintOpen.toggle(); resetIdle() }
    func finish() { setStage(.done) }
    func restart() {
        idleTask?.cancel(); revertTask?.cancel()
        messages = []; input = ""
        answered = false; showWrong = false; hintOpen = false; progress = 0.62
        onAppear()                     // setStage(.intro) + wave → idle
    }

    // MARK: idle → sleep
    func wake() { if merc == .sleep { merc = .idle }; resetIdle() }

    private func resetIdle() {
        idleTask?.cancel()
        guard stage == .chat else { return }   // sleep is a chat-only behavior
        let timeout = idleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout)
            // Re-check AFTER the delay: still in chat, still resting at idle.
            guard let self, !Task.isCancelled, self.stage == .chat, self.merc == .idle else { return }
            self.merc = .sleep
        }
    }
    private func revert(to s: MercState, after secs: Double) {
        revertTask?.cancel()
        revertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            if !Task.isCancelled { self?.merc = s; self?.resetIdle() }
        }
    }
    private func bump() { /* hook for haptics / scroll-to-bottom */ }
}
