import Foundation

/// The codes the server uses when it declines a request for a reason that is
/// not the caller's fault — quota, spend cap, maintenance, load. Shared by the
/// JSON path (`APIClient.validate`) and the SSE path (`parseChatEvent`) so
/// both classify the same wire codes the same way.
///
/// On JSON routes the code arrives as `{"error": "<code>"}` with HTTP 429
/// (`daily_limit`) or 503 (the rest). On `/api/chat` it arrives inside a 200
/// stream as `{"type":"error","code":"<code>","error":"<human text>"}`.
public enum ServerRefusalCode: String, Sendable, CaseIterable {
    case dailyLimit = "daily_limit"
    case spendCap = "spend_cap"
    case serviceDisabled = "service_disabled"
    case busy
    case restarting

    /// Whether a raw wire code is one of the refusal codes.
    public static func isRefusal(_ code: String?) -> Bool {
        guard let code else { return false }
        return ServerRefusalCode(rawValue: code) != nil
    }
}
