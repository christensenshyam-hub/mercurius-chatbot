import Foundation
import Observation
import NetworkingKit

/// The user's "show progress nudges" preference — backing the Settings toggle.
///
/// Persists to the shared UserDefaults key in `GamificationFlag`, so
/// `GamificationStore` (in another module) reads the same value without a
/// cross-import. Defaults to ON; the user can turn the brief move credits off
/// for a quieter experience while the Progress card stays. Purely a
/// presentation preference — nothing to do with rank or competency.
@MainActor
@Observable
public final class NudgePreferenceStore {
    public var isEnabled: Bool {
        didSet { GamificationFlag.setNudgesEnabled(isEnabled, defaults) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = GamificationFlag.areNudgesEnabled(defaults)
    }
}
