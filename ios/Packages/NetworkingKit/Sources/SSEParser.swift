import Foundation

/// Parses a stream of Server-Sent Events lines into typed events.
///
/// Server-Sent Events spec: each event is a sequence of lines terminated
/// by `\n`. A blank line dispatches the event. We only support the
/// `data: <payload>` field — the server never emits `event:` or `id:`
/// fields, and ignoring them is compliant behavior.
///
/// Usage:
/// ```
/// var parser = SSEParser()
/// for try await line in stream.lines {
///     if let payload = parser.append(line: line) {
///         let event = try parseChatEvent(from: payload)
///         ...
///     }
/// }
/// ```
struct SSEParser {
    private var buffer: String = ""

    /// Feed a single line (without its trailing newline) into the
    /// parser. Returns a complete payload if the line was a dispatch
    /// boundary (blank line) or if the full event arrived on a single
    /// line starting with `data: `.
    mutating func append(line: String) -> String? {
        // Blank line = dispatch. If we have a buffered data payload,
        // emit it and reset.
        if line.isEmpty {
            if buffer.isEmpty {
                return nil
            }
            let payload = buffer
            buffer = ""
            return payload
        }

        // `data: ...` lines append to the buffer. Multiple `data:`
        // lines within one event are joined with newlines per spec.
        if line.hasPrefix("data: ") {
            let value = String(line.dropFirst("data: ".count))
            if buffer.isEmpty {
                buffer = value
            } else {
                buffer += "\n" + value
            }
            return nil
        }

        // `:` prefix is a comment. `event:`, `id:`, `retry:` are other
        // fields we don't use. All safely ignored.
        return nil
    }
}

/// Decode a single SSE payload into a `ChatStreamEvent`.
///
/// Throws `APIError.invalidModelOutput` if the payload violates the
/// server contract (missing required fields for a given type).
func parseChatEvent(from payload: String) throws -> ChatStreamEvent? {
    // Server sometimes terminates the stream with `data: [DONE]`.
    if payload == "[DONE]" {
        return nil
    }

    guard let data = payload.data(using: .utf8) else {
        throw APIError.invalidModelOutput(reason: "Non-UTF8 payload")
    }

    let decoded: SSEPayload
    do {
        decoded = try JSONDecoder().decode(SSEPayload.self, from: data)
    } catch {
        throw APIError.invalidModelOutput(reason: "Malformed SSE JSON: \(error.localizedDescription)")
    }

    switch decoded.type {
    case "delta":
        guard let text = decoded.text else {
            throw APIError.invalidModelOutput(reason: "delta event missing text")
        }
        return .delta(text: text)

    case "complete":
        guard let reply = decoded.reply,
              let sessionId = decoded.sessionId,
              let mode = decoded.mode
        else {
            throw APIError.invalidModelOutput(reason: "complete event missing required fields")
        }
        let response = ChatResponse(
            reply: reply,
            sessionId: sessionId,
            mode: mode,
            unlocked: decoded.unlocked ?? false,
            justUnlocked: decoded.justUnlocked,
            streak: decoded.streak,
            difficulty: decoded.difficulty,
            suggestSummary: decoded.suggestSummary
        )
        return .complete(response)

    case "error":
        let msg = decoded.error ?? "Unknown server error"
        return .streamError(message: msg)

    default:
        // Unknown types are ignored rather than throwing — forward
        // compatibility with future server event types.
        return nil
    }
}
