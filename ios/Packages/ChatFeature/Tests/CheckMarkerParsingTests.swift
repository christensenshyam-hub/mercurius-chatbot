import Testing
@testable import ChatFeature

// Tests for the lesson [CHECK]…[/CHECK] callout parser + token scrub.

struct CheckMarkerParsingTests {

    @Test func noMarkerReturnsWholeStringAsBefore() {
        let (before, check, after) = MessageBubbleView.splitCheck("Just some teaching text.")
        #expect(before == "Just some teaching text.")
        #expect(check == nil)
        #expect(after == "")
    }

    @Test func splitsACompleteBlock() {
        let (before, check, after) = MessageBubbleView.splitCheck("Teach. [CHECK]Why?[/CHECK] More.")
        #expect(before == "Teach. ")
        #expect(check == "Why?")
        #expect(after == " More.")
    }

    @Test func unclosedBlockWhileStreamingHoldsTheQuestion() {
        let (before, check, after) = MessageBubbleView.splitCheck("Teach. [CHECK]Why is that")
        #expect(before == "Teach. ")
        #expect(check == "Why is that")
        #expect(after == "")
    }

    @Test func stripRemovesCompleteTokens() {
        #expect(MessageBubbleView.stripCheckTokens("a [CHECK]q[/CHECK] b") == "a q b")
        #expect(MessageBubbleView.stripCheckTokens("plain") == "plain")
    }

    @Test func stripHoldsBackAlmostCompletePartial() {
        #expect(MessageBubbleView.stripCheckTokens("Teach. [CHECK") == "Teach. ")
        #expect(MessageBubbleView.stripCheckTokens("Done. [/CHECK") == "Done. ")
    }

    @Test func stripLeavesOrdinaryBracketsAlone() {
        // A markdown link or stray bracket must not be eaten.
        #expect(MessageBubbleView.stripCheckTokens("see [the docs](u)") == "see [the docs](u)")
        #expect(MessageBubbleView.stripCheckTokens("array[0]") == "array[0]")
    }
}
