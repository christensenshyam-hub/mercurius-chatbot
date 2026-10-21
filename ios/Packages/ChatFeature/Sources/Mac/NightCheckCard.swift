#if os(macOS)
import SwiftUI
import AppKit
import DesignSystem

/// The lesson's [Q] check on the Mac (SPEC.md §5.3.3, D9): pick an answer,
/// then **Lock it in**. Lock it in grades on the device, says the result to
/// VoiceOver, and calls `onSelect`, which sends "I picked B) …" exactly as
/// the iPhone's tap does; Merc's real follow-up then streams below. A pick
/// alone sends nothing.
///
/// From the keyboard: while it waits, the lesson's keys go to it (the
/// lesson's `nightCheckKeys`: A–D or 1–4 pick, ↑/↓ move the pick, Return
/// locks it in) unless the composer has focus, and it wears the focus ring
/// to say so. Tab to it or click it for the same keys through SwiftUI focus.
/// Typing in the composer never picks.
///
/// The check stays where it streamed: there is no docked tray on the Mac.
struct NightCheckCard: View {
    let quiz: QuizBlock
    /// Live only on the latest reply, complete, with nothing in flight.
    let isEnabled: Bool
    /// The student's earlier answer, from the "I picked X)" turn after it.
    let answeredIndex: Int?
    let onSelect: (Int) -> Void
    /// This card's place in the lesson's key routing (its reply's id).
    var routeID = UUID()

    /// Picked, not yet locked in.
    @State private var pick: Int?
    /// Locked in on this card (before the next turn carries it).
    @State private var locked: Int?
    @FocusState private var focused: Bool
    @NightSettings private var night
    @Environment(\.nightCheckRouter) private var router
    @Environment(\.nightComposerFocused) private var composerFocused

    /// The lesson's keys come here: this is the waiting check and the
    /// composer hasn't the keyboard.
    private var routed: Bool { answerable && router?.activeID == routeID && !composerFocused }

    private var gradedPick: Int? { locked ?? answeredIndex }
    private var graded: Bool { gradedPick != nil }
    private var answerable: Bool { isEnabled && !graded }
    /// A pick shows only while it can still be locked in.
    private var livePick: Int? { answerable ? pick : nil }

    private var eyebrow: String {
        if graded { return NightReplyCopy.checkAnswered }
        return isEnabled ? NightReplyCopy.checkOpen : NightReplyCopy.checkInert
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Night.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            NightEyebrow(eyebrow, systemImage: graded ? "checkmark.circle" : "circle.dashed")
            Text(NightTypography.curlQuotes(quiz.stem))
                .nightFont(.title2)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                    row(index: index, option: option)
                }
            }
            if let livePick {
                NightPrimaryButton(NightReplyCopy.lockIn, systemImage: "lock") { lockIn() }
                    .help(NightReplyCopy.lockInHelp)
                    .accessibilityLabel(NightReplyCopy.lockInAccessibility(letter: ChatAnnouncement.letter(livePick)))
                    .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        // In the Tab loop whatever the Full Keyboard Access setting, like the
        // unit check's cards, with Night's own ring.
        .focusable(answerable, interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            if (focused || routed) && answerable {
                shape.inset(by: -3 - night.focusRingWidth / 2)
                    .stroke(Night.focusRing, lineWidth: night.focusRingWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .help(answerable ? NightReplyCopy.checkCardHelp : "")
        .preference(key: NightUncommittedPickKey.self, value: livePick != nil)
        .animation(night.animation(Night.Motion.tap), value: pick)
        .animation(night.animation(Night.Motion.layout), value: locked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question: \(quiz.stem)")
        // While it waits, the lesson's keys route here (when the reply
        // settles, or the lesson opens on it), so A–D and Return reach it,
        // not the composer.
        .onAppear(perform: updateRoute)
        .onChange(of: answerable) { _, _ in updateRoute() }
        .onDisappear { router?.unregister(routeID) }
        #if DEBUG
        .onAppear(perform: applyDebugState)
        .onChange(of: isEnabled) { _, _ in applyDebugState() }
        #endif
    }

    private func updateRoute() {
        guard let router else { return }
        if answerable {
            router.register(routeID) { key in handle(key) }
        } else {
            router.unregister(routeID)
        }
    }

    /// A routed key: the same rules as `handleKey`.
    private func handle(_ key: NightCheckKeys.Key) -> Bool {
        guard answerable else { return false }
        switch key {
        case .option(let index):
            guard quiz.options.indices.contains(index) else { return false }
            choose(index)
        case .move(let step):
            pick = NightCheckKeys.moved(pick, by: step, optionCount: quiz.options.count)
        case .lockIn:
            guard pick != nil else { return false }
            lockIn()
        }
        return true
    }

    // MARK: Picking and locking in

    private func choose(_ index: Int) {
        guard answerable, quiz.options.indices.contains(index) else { return }
        pick = index
    }

    private func lockIn() {
        guard answerable, let pick else { return }
        locked = pick
        AccessibilityNotification.Announcement(ChatAnnouncement.quizPick(index: pick, quiz: quiz)).post()
        onSelect(pick)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard answerable, !press.modifiers.contains(.command) else { return .ignored }
        switch press.key {
        case .return:
            guard pick != nil else { return .ignored }
            lockIn()
            return .handled
        case .upArrow:
            pick = NightCheckKeys.moved(pick, by: -1, optionCount: quiz.options.count)
            return .handled
        case .downArrow:
            pick = NightCheckKeys.moved(pick, by: 1, optionCount: quiz.options.count)
            return .handled
        default:
            guard let index = NightCheckKeys.optionIndex(forKey: press.characters,
                                                         optionCount: quiz.options.count) else { return .ignored }
            choose(index)
            return .handled
        }
    }

    // MARK: Rows

    /// The shared answer row's state for option `index` (`NightAnswerRow`).
    private func mark(of index: Int) -> NightAnswerRow.Mark {
        if let gradedPick {
            if index == quiz.answerIndex { return .correct(picked: index == gradedPick) }
            if index == gradedPick { return .wrong }
            return .other
        }
        return livePick == index ? .picked : .rest
    }

    private func row(index: Int, option: String) -> some View {
        let mark = mark(of: index)
        let spoken = CheckQuizCard.optionAccessibility(index: index, option: option, pick: gradedPick,
                                                       answerIndex: quiz.answerIndex)
        return NightAnswerRow(letter: ChatAnnouncement.letter(index), text: NightTypography.curlQuotes(option), mark: mark,
                              isInteractive: answerable) {
            choose(index)
        }
        .accessibilityLabel(spoken.label)
        .accessibilityValue(spoken.value ?? (mark == .picked ? "Picked, not locked in" : ""))
        .accessibilityAddTraits(mark == .picked || mark == .wrong || mark == .correct(picked: true)
                                ? .isSelected : [])
        .accessibilityRemoveTraits(answerable ? [] : .isButton)
        .accessibilityHint(answerable ? "Picks this answer. Then lock it in." : "")
    }

    #if DEBUG
    /// `-NightCheckState picked|answered` (shots only): the live check with
    /// B picked, or B picked and locked in a moment later, which sends it
    /// through the real path. Once per launch.
    private func applyDebugState() {
        guard answerable, !NightCheckCard.didApplyDebugState,
              let state = UserDefaults.standard.string(forKey: "NightCheckState"),
              state == "picked" || state == "answered", quiz.options.count > 1 else { return }
        NightCheckCard.didApplyDebugState = true
        pick = 1
        if state == "answered" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { lockIn() }
        }
    }

    @MainActor static var didApplyDebugState = false
    #endif
}

// MARK: - The lesson's keys, to its waiting check

/// Where a lesson's keys go while its check waits for Lock it in: the
/// answerable check registers here, and the lesson's key watcher
/// (`nightCheckKeys`) hands it A–D, 1–4, ↑/↓ and Return whenever the
/// composer (or any text field) hasn't the keyboard. It doesn't depend on
/// SwiftUI focus, which a check deep in the lesson's scroll view didn't take
/// when asked.
@Observable
@MainActor
final class NightCheckKeyRouter {
    /// The waiting check's reply id.
    private(set) var activeID: UUID?
    @ObservationIgnored private var handler: ((NightCheckKeys.Key) -> Bool)?

    func register(_ id: UUID, handler: @escaping (NightCheckKeys.Key) -> Bool) {
        if activeID != id { activeID = id }
        self.handler = handler
    }

    func unregister(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
        handler = nil
    }

    /// Hands `key` to the waiting check; false when there is none or it
    /// didn't take it (Return with nothing picked).
    func route(_ key: NightCheckKeys.Key) -> Bool {
        handler?(key) ?? false
    }
}

private struct NightCheckRouterKey: EnvironmentKey {
    static let defaultValue: NightCheckKeyRouter? = nil
}

private struct NightComposerFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The lesson's key routing to its waiting check (nil in free chat).
    var nightCheckRouter: NightCheckKeyRouter? {
        get { self[NightCheckRouterKey.self] }
        set { self[NightCheckRouterKey.self] = newValue }
    }

    /// The lesson's composer has the keyboard: its keys are the composer's.
    var nightComposerFocused: Bool {
        get { self[NightComposerFocusedKey.self] }
        set { self[NightComposerFocusedKey.self] = newValue }
    }
}

/// What the lesson's key watcher reads when a key arrives (its closure
/// outlives the view value that installed it).
@MainActor
final class NightCheckKeyContext {
    weak var window: NSWindow?
    var router: NightCheckKeyRouter?
    /// Off while the lesson's intro or complete card covers it.
    var isEnabled = true
}

/// The lesson's key watcher: a key typed in the lesson's window, with no
/// text field taking it, goes to the waiting check (`NightCheckKeys.key`).
struct NightCheckKeyWatcher: ViewModifier {
    let router: NightCheckKeyRouter
    let isEnabled: Bool
    @State private var context = NightCheckKeyContext()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { [context] in context.window = $0 })
            .onChange(of: isEnabled, initial: true) { _, enabled in context.isEnabled = enabled }
            .onAppear {
                context.router = router
                guard monitor == nil else { return }
                let context = context
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // Not into a text field, and not from the sidebar's list
                    // (its type-to-select).
                    guard context.isEnabled, let window = event.window, window === context.window,
                          window.isKeyWindow, let router = context.router, router.activeID != nil,
                          !(window.firstResponder is NSText), !(window.firstResponder is NSTableView),
                          let key = NightCheckKeys.key(characters: event.charactersIgnoringModifiers,
                                                       keyCode: event.keyCode,
                                                       modifiers: event.modifierFlags)
                    else { return event }
                    return router.route(key) ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// A lesson's keys go to its waiting check (`NightCheckKeyRouter`)
    /// while `isEnabled`.
    func nightCheckKeys(_ router: NightCheckKeyRouter, isEnabled: Bool) -> some View {
        modifier(NightCheckKeyWatcher(router: router, isEnabled: isEnabled))
    }
}

/// Whether a check on screen holds a pick that isn't locked in: the lesson's
/// Escape must not throw it away.
struct NightUncommittedPickKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
#endif
