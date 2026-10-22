import Foundation
import Testing
@testable import LessonInteractives

/// The ToyFit block: logistic regression at the exact optimum of the
/// slate's loss (summed log-loss + ½·λ·‖w‖², λ = 0.5, intercept
/// unpenalised). The fixture is the slate's own data (SLATE.md, Delete the
/// Gender Box), so the block is shown to reproduce
/// `tools/check_slate_numbers.py` before the card uses it.
@Suite("Interactives: the toy trainer")
struct ToyFitTests {
    /// (woman, women's, captain, coding → hired), SLATE.md.
    static let rows: [([Double], Bool)] = [
        ([0, 0, 1, 1], true), ([0, 0, 1, 0], true), ([0, 0, 0, 1], true), ([0, 0, 1, 1], true),
        ([0, 0, 0, 0], false), ([0, 0, 0, 1], true), ([0, 0, 1, 0], false), ([0, 0, 0, 0], true),
        ([1, 1, 1, 1], false), ([1, 0, 1, 1], true), ([1, 1, 0, 1], false), ([1, 0, 0, 0], false),
    ]
    static var examples: [ToyFit.Example] { rows.map { ToyFit.Example($0.0, label: $0.1) } }

    static func hundredths(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    @Test("All four columns: the check script's weights to two decimals")
    func keptWeights() {
        let fit = ToyFit.fit(Self.examples, keeping: [0, 1, 2, 3])
        #expect(fit.converged)
        #expect(Self.hundredths(fit.intercept) == 0.12)
        #expect(fit.weights.map(Self.hundredths) == [-1.04, -1.21, 0.33, 1.12])
        #expect((fit.score([1, 1, 1, 1]) * 10).rounded() / 10 == 33.6)
        #expect((fit.score([1, 0, 1, 1]) * 10).rounded() / 10 == 62.9)
    }

    @Test("The first column left out: the check script's refit")
    func deletedWeights() {
        let fit = ToyFit.fit(Self.examples, keeping: [1, 2, 3])
        #expect(fit.converged)
        #expect(Self.hundredths(fit.intercept) == -0.13)
        #expect(fit.weights.map(Self.hundredths) == [-1.53, 0.33, 1.01])
        #expect(fit.weight(forFeature: 0) == nil)
        #expect(fit.weight(forFeature: 1) == fit.weights[0])
        #expect((fit.score([1, 1, 1, 1]) * 10).rounded() / 10 == 42.1)
        #expect((fit.score([1, 0, 1, 1]) * 10).rounded() / 10 == 77.1)
    }

    @Test("It is the optimum: the loss's gradient is zero there, and Newton got there in a few steps")
    func optimum() {
        for kept in [[0, 1, 2, 3], [1, 2, 3], [3], []] {
            let fit = ToyFit.fit(Self.examples, keeping: kept)
            #expect(fit.converged, "\(kept)")
            #expect(fit.iterations < 15, "\(kept): \(fit.iterations) steps")
            let largest = fit.gradient(on: Self.examples).map { abs($0) }.max() ?? 1
            #expect(largest < 1e-9, "\(kept): gradient \(largest)")
        }
    }

    @Test("The convention matters: another λ gives other numbers")
    func convention() {
        let slate = ToyFit.fit(Self.examples, keeping: [0, 1, 2, 3])
        let weaker = ToyFit.fit(Self.examples, keeping: [0, 1, 2, 3], lambda: 0.1)
        #expect(Self.hundredths(weaker.weights[1]) != Self.hundredths(slate.weights[1]))
        #expect(slate.lambda == 0.5)
    }

    @Test("The intercept is unpenalised: alone, it gives the hire rate exactly")
    func interceptOnly() {
        let fit = ToyFit.fit(Self.examples, keeping: [])
        let hired = Double(Self.rows.filter(\.1).count)
        let rate = hired / Double(Self.rows.count)
        #expect(abs(fit.probability([0, 0, 0, 0]) - rate) < 1e-12)
        #expect(fit.weights.isEmpty)
    }

    @Test("The sigmoid holds at both ends; the solver finds exact answers and refuses singular systems")
    func arithmetic() {
        #expect(ToyFit.sigmoid(0) == 0.5)
        #expect(ToyFit.sigmoid(800) == 1)
        #expect(ToyFit.sigmoid(-800) == 0)
        #expect(abs(ToyFit.sigmoid(2) + ToyFit.sigmoid(-2) - 1) < 1e-15)
        let solved = ToyFit.solve([[2, 1], [1, 3]], [3, 5]) ?? []
        #expect(solved.count == 2)
        #expect(abs(solved[0] - 0.8) < 1e-12 && abs(solved[1] - 1.4) < 1e-12)
        #expect(ToyFit.solve([[1, 2], [2, 4]], [1, 2]) == nil)
        #expect(ToyFit.solve([], []) == nil)
    }

    @Test("Deterministic: the same rows give the same fit")
    func deterministic() {
        let first = ToyFit.fit(Self.examples, keeping: [0, 1, 2, 3])
        let second = ToyFit.fit(Self.examples, keeping: [0, 1, 2, 3])
        #expect(first == second)
    }
}
