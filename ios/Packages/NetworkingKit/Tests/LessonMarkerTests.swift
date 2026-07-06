import Testing
import Foundation
@testable import NetworkingKit

@Suite("LessonMarker")
struct LessonMarkerTests {

    // MARK: - Completion detection

    @Test("A pass marker on its own line signals completion")
    func passMarkersDetected() {
        #expect(LessonMarker.indicatesCompletion("Great work.\n\n[LESSON_COMPLETE]"))
        #expect(LessonMarker.indicatesCompletion("You nailed it.\n[TEST_PASSED]"))
        #expect(LessonMarker.indicatesCompletion("   [TEST_PASSED]   "))  // whitespace-padded, single line
    }

    @Test("A pass token quoted mid-sentence does NOT complete (false-positive guard)")
    func midSentenceTokenNotCompletion() {
        // A lesson teaching about the markers, or echoing a student, must not
        // silently advance — the token has to be on a line by itself.
        #expect(!LessonMarker.indicatesCompletion("You should never write [TEST_PASSED] yourself."))
        #expect(!LessonMarker.indicatesCompletion("The model emits [LESSON_COMPLETE] when you pass."))
    }

    @Test("A fail marker does NOT signal completion")
    func failMarkerNotCompletion() {
        #expect(!LessonMarker.indicatesCompletion("Not quite yet.\n[TEST_FAILED]"))
    }

    @Test("Ordinary text without a marker is not completion")
    func plainTextNotCompletion() {
        #expect(!LessonMarker.indicatesCompletion("Let's keep going — what do you think happens next?"))
    }

    // MARK: - Stripping

    @Test("cleaned removes every control marker and trims")
    func cleanedStripsAll() {
        #expect(LessonMarker.cleaned("Nice reasoning.\n\n[LESSON_COMPLETE]") == "Nice reasoning.")
        #expect(LessonMarker.cleaned("Solid defense. [TEST_PASSED]") == "Solid defense.")
        #expect(LessonMarker.cleaned("Try again. [TEST_FAILED]") == "Try again.")
    }

    @Test("cleaned removes a doubled marker")
    func cleanedHandlesDoubledMarker() {
        #expect(LessonMarker.cleaned("Done.\n[LESSON_COMPLETE]\n[LESSON_COMPLETE]") == "Done.")
    }

    @Test("cleaned returns empty for a marker-only reply (caller substitutes)")
    func cleanedMarkerOnly() {
        #expect(LessonMarker.cleaned("[TEST_PASSED]").isEmpty)
    }

    @Test("removingMarkers strips tokens but preserves surrounding whitespace")
    func removingMarkersNoTrim() {
        // Mid-stream: the trailing space before the (not-yet-arrived) next word
        // must survive so words don't collide.
        #expect(LessonMarker.removingMarkers("Good point [TEST_PASSED] ") == "Good point  ")
    }

    @Test("text with no marker is returned unchanged")
    func noMarkerUnchanged() {
        let s = "Tokens are sub-word pieces — not whole words."
        #expect(LessonMarker.cleaned(s) == s)
        #expect(LessonMarker.removingMarkers(s) == s)
    }
}
