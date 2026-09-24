import Foundation

/// The words around the active meta line's countdown, as plain strings.
/// Outside the iOS-only guard so the lock card's length budget is tested on
/// the macOS host.
enum ActivityMetaCopy {
    static let separator = " · "
    static let countdownSuffix = " left"

    /// What precedes the countdown. The Dynamic Island has room for the unit
    /// ("2 lessons left in Unit 6"); the lock card (`compact`) keeps only the
    /// count ("2 to go"), because its text column is ~149pt on the narrowest
    /// cards and the countdown can read "23:59:59".
    static func lessonsLeftPhrase(lessonsLeft: Int, unitNumber: Int, compact: Bool) -> String {
        let left = max(lessonsLeft, 0)
        if compact {
            // Zero left: replaying a lesson in a unit that's already finished.
            return left == 0 ? "All done" : "\(left) to go"
        }
        let unit = unitNumber > 0 ? "Unit \(unitNumber)" : nil
        if left == 0 {
            return unit.map { "\($0) complete" } ?? "All lessons done"
        }
        let count = left == 1 ? "1 lesson left" : "\(left) lessons left"
        return unit.map { "\(count) in \($0)" } ?? count
    }
}
