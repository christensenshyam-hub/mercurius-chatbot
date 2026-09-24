import Foundation

/// The single entry point for every request to the Mercurius backend.
///
/// Responsibilities:
/// - Construct requests with correct headers (tracing, JSON, session).
/// - Enforce timeouts.
/// - Translate `URLSession`/HTTP responses into `APIError` cases.
/// - Decode and validate response bodies.
///
/// Immutable, `Sendable`, safe to share across tasks.
public final class APIClient: Sendable {
    let environment: APIEnvironment
    let urlSession: URLSession
    let sessionIdentity: SessionIdentity

    public init(
        environment: APIEnvironment = .production,
        sessionIdentity: SessionIdentity = SessionIdentity(),
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.environment = environment
        self.sessionIdentity = sessionIdentity

        let config = sessionConfiguration
        config.timeoutIntervalForRequest = environment.requestTimeout
        config.timeoutIntervalForResource = environment.requestTimeout * 2
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)
    }

    // Convenience accessors used by `APIClient+Chat`.
    var environmentBaseURL: URL { environment.baseURL }
    var streamingTimeout: TimeInterval { environment.streamingTimeout }

    // MARK: - Health

    /// Pings the backend's health endpoint. Returns `true` only if the
    /// backend reports `status: "ok"`.
    public func checkHealth() async -> Bool {
        do {
            let response: HealthResponse = try await send(
                method: "GET",
                path: "/api/health",
                body: Optional<Empty>.none
            )
            return response.status == "ok"
        } catch {
            return false
        }
    }

    // MARK: - Generic request

    /// Send a JSON request and decode the JSON response.
    ///
    /// `Body: Encodable` — pass `Optional<Empty>.none` for GET.
    /// `Response: Decodable` — the expected body shape.
    func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws -> Response {
        var request = try buildRequest(method: method, path: path)

        if let body {
            do {
                let encoder = JSONEncoder()
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.invalidRequest(reason: "Failed to encode body")
            }
        }

        return try await perform(request: request)
    }

    // MARK: - Request construction

    private func buildRequest(method: String, path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: environment.baseURL)?.absoluteURL else {
            throw APIError.invalidRequest(reason: "Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = environment.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-trace-id")

        return request
    }

    // MARK: - Perform

    private func perform<Response: Decodable>(request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError {
            throw Self.mapURLError(urlError)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.unknown(underlying: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(underlying: "Non-HTTP response")
        }

        try Self.validate(statusCode: http.statusCode, data: data)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: String(describing: error))
        }
    }

    // MARK: - Response validation
    //
    // `validate` and `mapURLError` are `public static` so sibling
    // networking layers in other packages can share the same status-code
    // → `APIError` mapping. Keeps error UX consistent across every
    // network call in the app.

    public static func validate(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return
        case 400:
            throw APIError.invalidRequest(reason: errorBody(from: data)?.message)
        case 401, 403:
            throw APIError.unauthorized
        case 413:
            // express's JSON body cap. Non-retryable — a retry re-sends the
            // same oversized payload — and actionable, unlike `.unknown`.
            throw APIError.invalidRequest(
                reason: errorBody(from: data)?.message
                    ?? "That message is too long. Try a shorter one, or start a new chat."
            )
        case 429:
            // `daily_limit` is the day's allowance, not the per-minute limiter:
            // it carries copy the student should read and must not be retried.
            let body = errorBody(from: data)
            if body?.error == ServerRefusalCode.dailyLimit.rawValue {
                throw APIError.quotaExceeded(
                    message: body?.humanMessage ?? Self.quotaFallbackMessage,
                    retryAfter: body?.retryAfterSec
                )
            }
            throw APIError.rateLimited
        case 503:
            // A refusal (spend cap, paused, busy, restarting) or any 503 the
            // server bothered to explain. Bare/HTML 503s from the proxy fall
            // through to the generic server error.
            if let body = errorBody(from: data) {
                let code = body.error ?? body.code
                let message = body.humanMessage
                if ServerRefusalCode.isRefusal(code) || message != nil {
                    throw APIError.serviceUnavailable(
                        code: code ?? "service_unavailable",
                        message: message ?? Self.unavailableFallbackMessage,
                        retryAfter: body.retryAfterSec
                    )
                }
            }
            throw APIError.server(status: statusCode)
        case 500...599:
            throw APIError.server(status: statusCode)
        default:
            throw APIError.unknown(underlying: "HTTP \(statusCode)")
        }
    }

    private static func errorBody(from data: Data) -> ErrorBody? {
        try? JSONDecoder().decode(ErrorBody.self, from: data)
    }

    // Used only when a refusal arrives without its human copy — the server
    // always sends one, so these are belt-and-braces.
    private static let quotaFallbackMessage =
        "You've reached today's usage limit. Mercurius will be ready again tomorrow."
    private static let unavailableFallbackMessage =
        "Mercurius is temporarily unavailable. Please try again soon."

    public static func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        default:
            return .unknown(underlying: error.localizedDescription)
        }
    }
}

// MARK: - Supporting types

struct Empty: Codable {}

/// The server's JSON error envelope. `error` is the machine code on every
/// route; `code` is accepted too because the SSE refusal frame spells it that
/// way. `message` and `reply` carry the same human copy — `reply` is the
/// legacy field older routes still populate.
struct ErrorBody: Decodable {
    let error: String?
    let code: String?
    let message: String?
    let scope: String?
    let retryAfterSec: TimeInterval?
    let reply: String?

    /// The human copy, whichever field the route used.
    var humanMessage: String? {
        [message, reply]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Shape of the /api/health response.
struct HealthResponse: Decodable {
    let status: String
    let timestamp: String?
}
