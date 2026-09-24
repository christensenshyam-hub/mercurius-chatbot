import Foundation

/// Structured error space for every API call. Features should switch on
/// these cases to decide UI behavior (show retry, show auth wall, show
/// generic error, etc.) rather than inspecting messages.
public enum APIError: Error, Equatable, Sendable {
    /// The device has no usable network connection or the request could
    /// not reach the server.
    case offline

    /// The request took longer than the configured timeout.
    case timeout

    /// The server rejected the input (400). `reason` is optional context
    /// from the server. Never surface this directly to users — it may be
    /// technical.
    case invalidRequest(reason: String?)

    /// The server requires authentication or authorization (401 / 403).
    case unauthorized

    /// The server rate-limited this client (429, per-minute limiter). The
    /// caller should back off and try again later.
    case rateLimited

    /// Today's usage allowance is used up (429 with `error == "daily_limit"`).
    /// `message` is the server's own human copy; `retryAfter` is seconds
    /// until the allowance resets. Retrying sooner re-hits the same wall.
    case quotaExceeded(message: String, retryAfter: TimeInterval?)

    /// The server is up but not serving right now (503 with a
    /// `ServerRefusalCode` such as `spend_cap` / `service_disabled` / `busy` /
    /// `restarting`, or any 503 that carries a human message). `message` is
    /// the server's copy; `retryAfter` is its suggested wait, when given.
    case serviceUnavailable(code: String, message: String, retryAfter: TimeInterval?)

    /// The server failed unexpectedly (5xx without a refusal payload).
    case server(status: Int)

    /// The response body did not match the expected shape.
    case decoding(underlying: String)

    /// A model-output validation error — the backend returned JSON but the
    /// content violates our invariants (e.g. missing required fields).
    case invalidModelOutput(reason: String)

    /// Request was explicitly cancelled (user navigated away, etc.).
    case cancelled

    /// Anything else.
    case unknown(underlying: String)

    /// A user-friendly, non-technical message safe to show in the UI.
    public var userFacingMessage: String {
        switch self {
        case .offline:
            return "You're offline. Reconnect and try again."
        case .timeout:
            return "That took too long. The server may be busy — try again."
        case .invalidRequest:
            return "Something about that request wasn't right. Try again."
        case .unauthorized:
            return "You're not signed in to do that."
        case .rateLimited:
            return "You're moving fast — give it a moment, then try again."
        case .quotaExceeded(let message, _), .serviceUnavailable(_, let message, _):
            // The server writes this copy for students; it already names
            // the reason and when to come back.
            return message
        case .server:
            return "The server hit an error. Try again in a moment."
        case .decoding, .invalidModelOutput:
            return "We got an unexpected response. Try again."
        case .cancelled:
            return "Cancelled."
        case .unknown:
            return "Something went wrong. Try again."
        }
    }

    /// Whether the error is likely transient and a retry could succeed.
    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .server, .rateLimited, .serviceUnavailable, .unknown:
            return true
        case .invalidRequest, .unauthorized, .quotaExceeded, .decoding, .invalidModelOutput, .cancelled:
            return false
        }
    }
}
