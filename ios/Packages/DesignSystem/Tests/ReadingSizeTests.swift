import Testing
import SwiftUI
@testable import DesignSystem

/// The Basics reading-size floor (`ReadingSize`, `readingSizeFloor`).
@Suite("ReadingSize")
@MainActor
struct ReadingSizeTests {
    @Test("A floor, never a ceiling: the larger of the system's size and the choice")
    func floorNotCeiling() {
        #expect(ReadingSize.standard.applied(to: .large) == .large)
        #expect(ReadingSize.larger.applied(to: .large) == .xLarge)
        #expect(ReadingSize.largest.applied(to: .large) == .xxxLarge)
        #expect(ReadingSize.larger.applied(to: .accessibility3) == .accessibility3)
    }

    /// Review 2026-10-22: the modifier used to be `if let floor { … } else
    /// { self }`, two branches with two identities, so picking a size
    /// rebuilt the wrapped view and reset its state (the Text size panel
    /// closed, a lesson's chat was rebuilt). Every size must give the same
    /// concrete view type: one modifier, no `_ConditionalContent`.
    @Test("One modifier for every size, so the wrapped view keeps its identity")
    func oneIdentity() {
        let types = ReadingSize.allCases.map { size in
            String(describing: type(of: Text("Hi").readingSizeFloor(size)))
        }
        #expect(Set(types).count == 1)
        #expect(!types[0].contains("ConditionalContent"), "\(types[0])")
    }
}
