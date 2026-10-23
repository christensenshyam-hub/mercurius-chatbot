import SwiftUI

private struct UnitMasteryAccessoryKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

public extension EnvironmentValues {
    /// Shown on a passed unit check's result, under its score: the host's
    /// slot for what this pass unlocked (AppFeature puts the "Get your
    /// certificate" card here when the pass completed the course). The
    /// curriculum can't see the certificates, so the host fills it.
    var unitMasteryAccessory: AnyView? {
        get { self[UnitMasteryAccessoryKey.self] }
        set { self[UnitMasteryAccessoryKey.self] = newValue }
    }
}
