import Foundation

/// User-controlled length / depth dial for chat responses, separate
/// from the pedagogical `ChatMode`. Sent on the wire as `responseMode`
/// in the `/api/chat` request body; defaults server-side to `concise`
/// if absent.
///
/// - `oneLine`: 80–120 token cap, low temperature. Quick facts.
/// - `concise`: ~400 token cap. Default mobile experience.
/// - `balanced`: ~700 token cap. Moderate depth.
/// - `deep`: ~1400 token cap, slightly higher temperature. Reserved
///   for the "Explain more" follow-up flow — the iOS client flips
///   to `deep` for one round when the user taps that affordance,
///   then snaps back to `concise`.
public enum ResponseMode: String, Codable, Sendable, CaseIterable, Equatable {
    case oneLine = "one_line"
    case concise
    case balanced
    case deep
}
