import Foundation
import Observation

/// What the student has done with the lesson's card, for the open lesson:
/// one state object per card, made on first use, plus the Mac's opened
/// "Try it" cards. Owned by the lesson's list (as Lesson 1.1's
/// `TokenizerState` is), so a reply's re-render never resets a card, and a
/// new lesson screen starts fresh.
///
/// In memory only: it is never `Codable`, never written to UserDefaults,
/// SwiftData or a file, and never sent (`NoIOTests`, `StateStoreTests`).
@Observable
@MainActor
public final class InteractiveStateStore {
    /// One state object per card. Ignored by observation: each state object
    /// is `@Observable` itself, and making one mustn't redraw the list.
    @ObservationIgnored private var states: [InteractiveID: AnyObject] = [:]
    /// The Mac: cards whose compact "Try it" card was opened.
    public private(set) var expanded: Set<InteractiveID> = []

    public init() {}

    /// `id`'s state, made by `make` the first time it is asked for.
    public func state<State: AnyObject>(for id: InteractiveID, make: () -> State) -> State {
        if let existing = states[id] as? State { return existing }
        let made = make()
        states[id] = made
        return made
    }

    /// Whether `id`'s state exists yet (tests).
    public func hasState(for id: InteractiveID) -> Bool { states[id] != nil }

    public func isExpanded(_ id: InteractiveID) -> Bool { expanded.contains(id) }

    public func expand(_ id: InteractiveID) {
        if !expanded.contains(id) { expanded.insert(id) }
    }
}

/// What a card's view is given: its row in the registry, whether the
/// tutor's text spoiled its prediction, and the lesson's state store.
public struct InteractiveCardContext {
    public let spec: InteractiveSpec
    /// Open in the card's spoiled mode (`InteractiveSpec.spoilers`).
    public let spoiled: Bool
    public let store: InteractiveStateStore

    public init(spec: InteractiveSpec, spoiled: Bool, store: InteractiveStateStore) {
        self.spec = spec
        self.spoiled = spoiled
        self.store = store
    }

    public var id: InteractiveID { spec.id }

    /// The card's state, made by `make` (with this context) the first time.
    @MainActor
    public func state<State: AnyObject>(_ make: (InteractiveCardContext) -> State) -> State {
        store.state(for: spec.id) { make(self) }
    }
}
