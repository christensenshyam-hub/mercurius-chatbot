import Testing
import NetworkingKit

@Suite("ReasoningMoveDetector")
struct ReasoningMoveDetectorTests {
    @Test("detects each reasoning move")
    func detectsMoves() {
        #expect(ReasoningMoveDetector.detect(in: "Wait, I was wrong about that.") == .positionRevision)
        #expect(ReasoningMoveDetector.detect(in: "I made a mistake earlier.") == .selfCorrection)
        #expect(ReasoningMoveDetector.detect(in: "What do you mean by alignment?") == .clarifyingQuestion)
        #expect(ReasoningMoveDetector.detect(in: "I'm not sure that follows.") == .uncertaintyExpressed)
    }

    @Test("a clarifying phrase only counts as a question")
    func clarifyingNeedsQuestionMark() {
        #expect(ReasoningMoveDetector.detect(in: "what do you mean by that") == nil)
        #expect(ReasoningMoveDetector.detect(in: "what do you mean by that?") == .clarifyingQuestion)
    }

    @Test("neutral / answer-like text earns nothing (correctness is never a move)")
    func neutralEarnsNothing() {
        #expect(ReasoningMoveDetector.detect(in: "The capital of France is Paris.") == nil)
        #expect(ReasoningMoveDetector.detect(in: "Yes, that's correct.") == nil)
        #expect(ReasoningMoveDetector.detect(in: "") == nil)
    }

    @Test("the higher-effort move wins when several cues match")
    func priority() {
        #expect(ReasoningMoveDetector.detect(in: "I made a mistake, I'm not sure why.") == .selfCorrection)
    }
}
