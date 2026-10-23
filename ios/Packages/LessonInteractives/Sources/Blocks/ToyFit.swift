import Foundation

/// A toy trainer (BUILD_PLAN.md §1.6): logistic regression fitted to the
/// exact optimum of its loss by Newton's method, so a card can show the
/// weights a real fit gives and a test can re-run it. Built first by Delete
/// the Gender Box (U3L1).
///
/// The convention is fixed and recorded, because other conventions give
/// other numbers (the slate's ML judge):
///
///     loss = Σ log-loss(yᵢ, σ(b + w·xᵢ)) + ½·λ·‖w‖²,   λ = 0.5
///
/// - the intercept `b` is not penalised;
/// - the log-losses are summed, not averaged;
/// - Newton steps run until no coordinate moves by more than 1e-12 (a few
///   steps on a dozen rows), which is the optimum to machine precision.
///
/// `tools/check_slate_numbers.py` runs the same fit in Python; the card's
/// tests hold the two to each other at two decimals.
///
/// Pure and deterministic: no randomness, no state, nothing stored.
public struct ToyFit: Equatable, Sendable {
    /// One training row: its features (0 or 1 in the toy, any number in
    /// general) and whether it was a "yes" (hired).
    public struct Example: Equatable, Sendable {
        public let features: [Double]
        public let label: Bool

        public init(_ features: [Double], label: Bool) {
            self.features = features
            self.label = label
        }
    }

    /// The ridge strength of the slate's convention.
    public static let slateLambda: Double = 0.5

    /// The features the fit could see, as indices into an example's
    /// `features`, in the order of `weights`. A deleted column is one left
    /// out here.
    public let kept: [Int]
    /// `b`: the score's starting point before any feature (unpenalised).
    public let intercept: Double
    /// One weight per kept feature, in `kept`'s order.
    public let weights: [Double]
    public let lambda: Double
    /// Newton steps taken.
    public let iterations: Int
    /// Whether the last step was below the tolerance (the optimum reached).
    public let converged: Bool

    /// Fits `examples` using only the features in `kept`.
    public static func fit(_ examples: [Example], keeping kept: [Int], lambda: Double = slateLambda,
                           maxIterations: Int = 50, tolerance: Double = 1e-12) -> ToyFit {
        let size = kept.count + 1
        var parameters = [Double](repeating: 0, count: size)
        var iterations = 0
        var converged = false
        while iterations < maxIterations {
            iterations += 1
            let gradient = Self.gradient(examples, kept: kept, parameters: parameters, lambda: lambda)
            let hessian = Self.hessian(examples, kept: kept, parameters: parameters, lambda: lambda)
            guard let step = Self.solve(hessian, gradient) else { break }
            for index in 0..<size { parameters[index] -= step[index] }
            if (step.map { abs($0) }.max() ?? 0) < tolerance {
                converged = true
                break
            }
        }
        return ToyFit(kept: kept, intercept: parameters[0], weights: Array(parameters.dropFirst()),
                      lambda: lambda, iterations: iterations, converged: converged)
    }

    /// The weight the fit gave feature `index`, or nil if that feature was
    /// left out (deleted).
    public func weight(forFeature index: Int) -> Double? {
        kept.firstIndex(of: index).map { weights[$0] }
    }

    /// The fit's chance of a "yes" for `features`, 0 to 1.
    public func probability(_ features: [Double]) -> Double {
        Self.sigmoid(Self.linear(features, kept: kept, parameters: [intercept] + weights))
    }

    /// The chance as a score out of 100 (not rounded).
    public func score(_ features: [Double]) -> Double {
        100 * probability(features)
    }

    /// The loss's gradient at this fit, over `examples`: all zeros (to
    /// rounding) at the optimum. For the tests.
    public func gradient(on examples: [Example]) -> [Double] {
        Self.gradient(examples, kept: kept, parameters: [intercept] + weights, lambda: lambda)
    }

    /// The logistic function, without overflow at either end.
    public static func sigmoid(_ z: Double) -> Double {
        if z >= 0 {
            return 1 / (1 + exp(-z))
        }
        let e = exp(z)
        return e / (1 + e)
    }

    // MARK: The arithmetic

    /// `b + w·x` for the kept features.
    static func linear(_ features: [Double], kept: [Int], parameters: [Double]) -> Double {
        var total = parameters[0]
        for (offset, index) in kept.enumerated() {
            total += parameters[offset + 1] * features[index]
        }
        return total
    }

    /// The row with a leading 1 for the intercept.
    static func design(_ features: [Double], kept: [Int]) -> [Double] {
        [1] + kept.map { features[$0] }
    }

    static func gradient(_ examples: [Example], kept: [Int], parameters: [Double], lambda: Double) -> [Double] {
        var gradient = [Double](repeating: 0, count: parameters.count)
        for example in examples {
            let row = design(example.features, kept: kept)
            let residual = sigmoid(linear(example.features, kept: kept, parameters: parameters))
                - (example.label ? 1 : 0)
            for index in row.indices { gradient[index] += residual * row[index] }
        }
        for index in gradient.indices where index > 0 { gradient[index] += lambda * parameters[index] }
        return gradient
    }

    static func hessian(_ examples: [Example], kept: [Int], parameters: [Double], lambda: Double) -> [[Double]] {
        let size = parameters.count
        var hessian = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        for example in examples {
            let row = design(example.features, kept: kept)
            let p = sigmoid(linear(example.features, kept: kept, parameters: parameters))
            let curvature = p * (1 - p)
            for j in 0..<size {
                for k in 0..<size { hessian[j][k] += curvature * row[j] * row[k] }
            }
        }
        for index in 1..<max(size, 1) { hessian[index][index] += lambda }
        return hessian
    }

    /// Solves `a·x = b` by Gaussian elimination with partial pivoting; nil
    /// if `a` is singular.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let size = b.count
        guard size > 0, a.count == size, a.allSatisfy({ $0.count == size }) else { return nil }
        var rows = a.enumerated().map { $0.element + [b[$0.offset]] }
        for column in 0..<size {
            var pivot = column
            for row in column..<size where abs(rows[row][column]) > abs(rows[pivot][column]) { pivot = row }
            guard abs(rows[pivot][column]) > 1e-300 else { return nil }
            rows.swapAt(column, pivot)
            for row in 0..<size where row != column {
                let factor = rows[row][column] / rows[column][column]
                guard factor != 0 else { continue }
                for index in column...size { rows[row][index] -= factor * rows[column][index] }
            }
        }
        return (0..<size).map { rows[$0][size] / rows[$0][$0] }
    }
}
