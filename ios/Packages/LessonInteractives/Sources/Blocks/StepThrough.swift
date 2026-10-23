import Foundation

/// Discrete steps walked with Next and Back (BUILD_PLAN.md §1.6): built for
/// The Page with a Secret (the agent's run, one step at a time) and reused
/// by The Citation That Wasn't (one slot at a time). Pure: the bounds, the
/// steps reached so far, and what VoiceOver says at each step.
///
/// A Next button alone isn't interaction (RESEARCH.md §1.5): a card puts a
/// prediction or a choice at one of its steps (`gate`), and Next stays off
/// there until the card opens the gate.
public struct StepThrough: Equatable, Sendable {
    public let count: Int
    public private(set) var index: Int
    /// The furthest step reached (Back doesn't undo what was shown).
    public private(set) var furthest: Int
    /// A step Next can't leave until `openGate()` (nil: none).
    public let gate: Int?
    public private(set) var gateOpen: Bool

    public init(count: Int, start: Int = 0, gate: Int? = nil) {
        precondition(count > 0, "a step-through needs a step")
        self.count = count
        let first = min(max(start, 0), count - 1)
        index = first
        furthest = first
        self.gate = gate
        gateOpen = gate == nil
    }

    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == count - 1 }
    public var canGoBack: Bool { index > 0 }
    public var canGoNext: Bool { !isLast && (gateOpen || index != gate) }
    /// 1-based, for the screen and VoiceOver.
    public var number: Int { index + 1 }

    /// "Step 4 of 6".
    public var position: String { InteractiveShellCopy.stepPosition(number, of: count) }

    @discardableResult
    public mutating func next() -> Bool {
        guard canGoNext else { return false }
        index += 1
        furthest = max(furthest, index)
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        guard canGoBack else { return false }
        index -= 1
        return true
    }

    /// Lets Next leave the gated step (the card's prediction was locked).
    public mutating func openGate() { gateOpen = true }

    /// Whether step `step` has been shown (a stacked layout shows every
    /// step up to `furthest`).
    public func hasShown(_ step: Int) -> Bool { step <= furthest }

    /// What VoiceOver says as a step arrives: "Step 4 of 6: Plan. New line:
    /// add …".
    public func announcement(_ stepLine: String) -> String { "\(position): \(stepLine)" }
}
