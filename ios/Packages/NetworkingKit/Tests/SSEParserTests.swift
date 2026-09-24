import Testing
@testable import NetworkingKit

@Suite("SSEParser — line framing")
struct SSEParserFramingTests {

    @Test("A single data line followed by blank dispatches one payload")
    func singleEvent() {
        var parser = SSEParser()
        #expect(parser.append(line: "data: hello") == nil)
        #expect(parser.append(line: "") == "hello")
    }

    @Test("Comment lines starting with `:` are ignored")
    func comments() {
        var parser = SSEParser()
        #expect(parser.append(line: ": keep-alive") == nil)
        #expect(parser.append(line: "data: body") == nil)
        #expect(parser.append(line: "") == "body")
    }

    @Test("Multiple `data:` lines join with newlines per SSE spec")
    func multilineData() {
        var parser = SSEParser()
        _ = parser.append(line: "data: line1")
        _ = parser.append(line: "data: line2")
        #expect(parser.append(line: "") == "line1\nline2")
    }

    @Test("Unknown fields (event:, id:, retry:) are ignored")
    func unknownFields() {
        var parser = SSEParser()
        _ = parser.append(line: "event: delta")
        _ = parser.append(line: "id: 42")
        _ = parser.append(line: "retry: 3000")
        _ = parser.append(line: "data: payload")
        #expect(parser.append(line: "") == "payload")
    }

    @Test("A blank line with no buffered data yields nothing")
    func emptyDispatch() {
        var parser = SSEParser()
        #expect(parser.append(line: "") == nil)
        #expect(parser.append(line: "") == nil)
    }

    @Test("Two events back-to-back")
    func twoEvents() {
        var parser = SSEParser()
        _ = parser.append(line: "data: one")
        let first = parser.append(line: "")
        _ = parser.append(line: "data: two")
        let second = parser.append(line: "")
        #expect(first == "one")
        #expect(second == "two")
    }
}

@Suite("parseChatEvent — payload decoding")
struct SSEParserDecodeTests {

    @Test("`delta` becomes .delta with text")
    func deltaEvent() throws {
        let event = try parseChatEvent(from: #"{"type":"delta","text":"hi"}"#)
        #expect(event == .delta(text: "hi"))
    }

    @Test("`complete` becomes .complete with all fields")
    func completeEvent() throws {
        let json = #"""
        {"type":"complete","reply":"Hello!","sessionId":"s1","mode":"socratic","unlocked":false,"streak":3}
        """#
        let event = try parseChatEvent(from: json)
        guard case .complete(let resp) = event else {
            Issue.record("Expected .complete")
            return
        }
        #expect(resp.reply == "Hello!")
        #expect(resp.sessionId == "s1")
        #expect(resp.mode == "socratic")
        #expect(resp.unlocked == false)
        #expect(resp.streak == 3)
    }

    @Test("`complete` carries lessonComplete=true when the server reports proficiency")
    func completeWithLessonComplete() throws {
        let json = #"""
        {"type":"complete","reply":"Great work.","sessionId":"s1","mode":"curriculum","unlocked":false,"lessonComplete":true}
        """#
        let event = try parseChatEvent(from: json)
        guard case .complete(let resp) = event else {
            Issue.record("Expected .complete")
            return
        }
        #expect(resp.lessonComplete == true)
    }

    @Test("`complete` from an older server (no lessonComplete field) decodes as nil, not a failure")
    func completeWithoutLessonCompleteIsNil() throws {
        let json = #"""
        {"type":"complete","reply":"Hello!","sessionId":"s1","mode":"socratic","unlocked":false}
        """#
        let event = try parseChatEvent(from: json)
        guard case .complete(let resp) = event else {
            Issue.record("Expected .complete")
            return
        }
        #expect(resp.lessonComplete == nil)
    }

    @Test("`error` without a code becomes .streamError with the message")
    func errorEvent() throws {
        let event = try parseChatEvent(from: #"{"type":"error","error":"rate limit"}"#)
        #expect(event == .streamError(message: "rate limit"))
    }

    @Test("`error` with a non-refusal code stays .streamError")
    func codedNonRefusalError() throws {
        let upstream = try parseChatEvent(
            from: #"{"type":"error","code":"upstream_error","error":"Mercurius hit a snag. Try again in a moment."}"#
        )
        #expect(upstream == .streamError(message: "Mercurius hit a snag. Try again in a moment."))

        let timeout = try parseChatEvent(
            from: #"{"type":"error","code":"timeout","error":"That reply took too long. Try again."}"#
        )
        #expect(timeout == .streamError(message: "That reply took too long. Try again."))
    }

    @Test("`error` with a refusal code becomes .refusal with code, copy and retryAfter")
    func refusalEvent() throws {
        let copy = "You've used today's chat turns. Mercurius will be ready again tomorrow."
        let event = try parseChatEvent(
            from: #"{"type":"error","code":"daily_limit","error":"\#(copy)","retryAfterSec":4200}"#
        )
        #expect(event == .refusal(code: "daily_limit", message: copy, retryAfter: 4200))
    }

    @Test("Every ServerRefusalCode maps to .refusal; retryAfter is nil when absent")
    func allRefusalCodes() throws {
        for code in ServerRefusalCode.allCases {
            let event = try parseChatEvent(
                from: #"{"type":"error","code":"\#(code.rawValue)","error":"nope"}"#
            )
            #expect(event == .refusal(code: code.rawValue, message: "nope", retryAfter: nil))
        }
    }

    @Test("`retryAfterSec: null` on a refusal decodes as nil, not a failure")
    func refusalNullRetryAfter() throws {
        let event = try parseChatEvent(
            from: #"{"type":"error","code":"spend_cap","error":"Daily usage limit reached — please try again tomorrow.","retryAfterSec":null}"#
        )
        #expect(event == .refusal(
            code: "spend_cap",
            message: "Daily usage limit reached — please try again tomorrow.",
            retryAfter: nil
        ))
    }

    @Test("A refusal frame with no text falls back to calm copy rather than a technical string")
    func refusalWithoutText() throws {
        let event = try parseChatEvent(from: #"{"type":"error","code":"busy","retryAfterSec":60}"#)
        guard case .refusal(let code, let message, let retryAfter) = event else {
            Issue.record("Expected .refusal, got \(String(describing: event))")
            return
        }
        #expect(code == "busy")
        #expect(retryAfter == 60)
        #expect(!message.isEmpty)
        #expect(message != "Unknown server error")
    }

    @Test("`[DONE]` sentinel produces no event")
    func doneSentinel() throws {
        #expect(try parseChatEvent(from: "[DONE]") == nil)
    }

    @Test("Unknown event types are ignored (forward-compat)")
    func unknownType() throws {
        #expect(try parseChatEvent(from: #"{"type":"future","text":"x"}"#) == nil)
    }

    @Test("Malformed JSON throws invalidModelOutput")
    func malformedJSON() {
        do {
            _ = try parseChatEvent(from: "{not json")
            Issue.record("Expected throw")
        } catch let error as APIError {
            guard case .invalidModelOutput = error else {
                Issue.record("Wrong APIError case: \(error)")
                return
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("`complete` missing required fields throws invalidModelOutput")
    func completeMissingFields() {
        do {
            _ = try parseChatEvent(from: #"{"type":"complete","reply":"x"}"#)
            Issue.record("Expected throw")
        } catch let error as APIError {
            guard case .invalidModelOutput = error else {
                Issue.record("Wrong APIError case: \(error)")
                return
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }
}
