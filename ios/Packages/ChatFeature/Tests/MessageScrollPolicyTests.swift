import Testing
import CoreGraphics
@testable import ChatFeature

// AUD-09: how the message list scrolls as replies arrive and stream, and
// AUD-08: when the lesson coach card makes room while the student types.

/// A list layout: `offset` is how far the student has scrolled down.
private func layout(offset: CGFloat = 0, content: CGFloat, viewport: CGFloat = 600,
                    latestTop: CGFloat = .infinity) -> MessageListGeometry {
    MessageListGeometry(contentMinY: -offset, contentHeight: content,
                        viewportHeight: viewport, latestMessageMinY: latestTop)
}

/// A policy that has seen `geometry` as its latest layout.
private func policy(at geometry: MessageListGeometry) -> MessageScrollPolicy {
    var policy = MessageScrollPolicy()
    _ = policy.geometryChanged(geometry)
    if geometry.latestMessageMinY.isFinite { policy.latestMessageMoved(minY: geometry.latestMessageMinY) }
    return policy
}

@Suite("MessageListGeometry")
struct MessageListGeometryTests {

    @Test("Distance from the bottom is what is left below the reading area")
    func distance() {
        #expect(layout(offset: 0, content: 1_000).distanceFromBottom == 400)
        #expect(layout(offset: 400, content: 1_000).distanceFromBottom == 0)
        #expect(layout(offset: 380, content: 1_000).isAtBottom, "within the tolerance")
        #expect(!layout(offset: 300, content: 1_000).isAtBottom)
    }

    @Test("A thread shorter than the reading area is at its top and its bottom")
    func shortThread() {
        let short = layout(content: 300)
        #expect(short.distanceFromBottom == 0)
        #expect(short.isAtBottom && short.isAtTop)
    }
}

@Suite("MessageScrollPolicy (AUD-09)")
struct MessageScrollPolicyTests {

    @Test("A new reply placeholder glides to the bottom; a loaded thread jumps there")
    func newLatestMessage() {
        var policy = MessageScrollPolicy()
        let result1 = policy.latestMessageChanged(isNewReply: true)
        #expect(result1 == .scrollToBottom(animated: true))
        let result2 = policy.latestMessageChanged(isNewReply: false)
        #expect(result2 == .scrollToBottom(animated: false))
        #expect(policy.isFollowing)
    }

    @Test("A reply that fits the reading area is followed to its end and never held")
    func shortReplyIsFollowed() {
        var policy = policy(at: layout(offset: 400, content: 1_000, latestTop: 380))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 380)
        for top in stride(from: CGFloat(380), through: 120, by: -40) {
            policy.latestMessageMoved(minY: top)
            let result3 = policy.latestMessageGrew()
            #expect(result3 == .scrollToBottom(animated: false))
        }
        #expect(!policy.didHoldCurrentReply)
    }

    @Test("A long reply is held at its first line once its top reaches the top of the reading area")
    func longReplyOpensAtItsTop() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 200)
        let result4 = policy.latestMessageGrew()
        #expect(result4 == .scrollToBottom(animated: false))

        // Following has lifted the reply until its top is about two lines
        // from the top: hold it there, once.
        policy.latestMessageMoved(minY: MessageScrollPolicy.holdThreshold - 10)
        let result5 = policy.latestMessageGrew()
        #expect(result5 == .showLatestMessageTop)
        #expect(!policy.isFollowing)

        // The rest of the reply streams in below without moving the text.
        policy.latestMessageMoved(minY: 0)
        let result6 = policy.latestMessageGrew()
        #expect(result6 == .none)
        let result7 = policy.latestMessageGrew()
        #expect(result7 == .none)
    }

    @Test("A reply that starts at the top of the list is held at once (a lesson opener with no coach card)")
    func openerAtTopIsHeldAtOnce() {
        var policy = policy(at: layout(content: 120))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 12)
        let result8 = policy.latestMessageGrew()
        #expect(result8 == .showLatestMessageTop)
    }

    @Test("A reply held while the thread still fits stays held as it grows past the screen")
    func holdSurvivesShortThread() {
        var policy = policy(at: layout(content: 200))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 12)
        let held = policy.latestMessageGrew()
        #expect(held == .showLatestMessageTop)

        // Still shorter than the screen: trivially "at the bottom".
        _ = policy.geometryChanged(layout(content: 450, latestTop: 12))
        #expect(!policy.isFollowing)
        // Now longer than the screen, and the student hasn't moved.
        _ = policy.geometryChanged(layout(content: 900, latestTop: 12))
        let next = policy.latestMessageGrew()
        #expect(next == .none, "the reply keeps its first line at the top")
        #expect(policy.showsJumpPill)
    }

    @Test("A previous message's position never stands in for the new reply's")
    func staleLatestPositionIgnored() {
        var policy = policy(at: layout(offset: 400, content: 1_000, latestTop: 0))
        _ = policy.latestMessageChanged(isNewReply: true)
        #expect(policy.geometry.latestMessageMinY == .infinity)
        let result9 = policy.latestMessageGrew()
        #expect(result9 == .scrollToBottom(animated: false),
                "the old reply's top (0) must not hold the new one")
    }

    @Test("Scrolling up mid-stream stops the following — no yank back on the next delta")
    func scrollingUpStopsFollowing() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 300)
        _ = policy.geometryChanged(layout(offset: 400, content: 1_000, latestTop: 300))

        // The student drags up 80 pt; the content did not get shorter.
        let result10 = policy.geometryChanged(layout(offset: 320, content: 1_000))
        #expect(result10 == .none)
        #expect(!policy.isFollowing)
        let result11 = policy.latestMessageGrew()
        #expect(result11 == .none)
    }

    @Test("New text below is not mistaken for the student scrolling")
    func growthIsNotAScroll() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.latestMessageChanged(isNewReply: true)
        // The content grew; its top didn't move.
        _ = policy.geometryChanged(layout(offset: 400, content: 1_040))
        #expect(policy.isFollowing)
    }

    @Test("Letting go at the end resumes following, without holding the same reply again")
    func returningResumes() {
        var policy = MessageScrollPolicy(knowsStudentScrolling: true)
        _ = policy.geometryChanged(layout(offset: 400, content: 1_000))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 20)
        let held = policy.latestMessageGrew()
        #expect(held == .showLatestMessageTop)

        // The student reads down to the end while it still streams.
        policy.studentScrolling(true)
        _ = policy.geometryChanged(layout(offset: 900, content: 1_500))
        policy.studentScrolling(false)
        #expect(policy.isFollowing)
        policy.latestMessageMoved(minY: -500)
        let next = policy.latestMessageGrew()
        #expect(next == .scrollToBottom(animated: false))
    }

    @Test("A hold that leaves the end just inside the tolerance stays a hold")
    func holdNearTheEndStays() {
        for reported in [false, true] {
            var policy = MessageScrollPolicy(knowsStudentScrolling: reported)
            _ = policy.geometryChanged(layout(offset: 105, content: 650, viewport: 532))
            _ = policy.latestMessageChanged(isNewReply: true)
            policy.latestMessageMoved(minY: 51)
            let held = policy.latestMessageGrew()
            #expect(held == .showLatestMessageTop)
            // Holding moved the reply's top up 51 pt; the end is now 29 pt
            // below the screen — "at the bottom", but not the student's doing.
            _ = policy.geometryChanged(layout(offset: 156, content: 717, viewport: 532, latestTop: 0))
            #expect(!policy.isFollowing, "reported: \(reported)")
            let next = policy.latestMessageGrew()
            #expect(next == .none)
        }
    }

    @Test("Without scroll phases (iOS 17), reaching the end alone doesn't resume following; the pill does")
    func iOS17ResumesByPill() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.geometryChanged(layout(offset: 300, content: 1_000))
        #expect(!policy.isFollowing)
        _ = policy.geometryChanged(layout(offset: 400, content: 1_000))
        #expect(!policy.isFollowing)
        let jump = policy.jumpToLatest()
        #expect(jump == .scrollToBottom(animated: true))
        #expect(policy.isFollowing)
    }

    @Test("The next reply gets its own hold")
    func eachReplyHeldOnce() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.latestMessageChanged(isNewReply: true)
        policy.latestMessageMoved(minY: 20)
        let result14 = policy.latestMessageGrew()
        #expect(result14 == .showLatestMessageTop)

        _ = policy.latestMessageChanged(isNewReply: true)
        #expect(!policy.didHoldCurrentReply)
        policy.latestMessageMoved(minY: 20)
        let result15 = policy.latestMessageGrew()
        #expect(result15 == .showLatestMessageTop)
    }

    @Test("Where the platform reports the student's scrolling, a lazy stack's own offset jumps change nothing")
    func reportedScrollingIgnoresOffsetJitter() {
        var policy = policy(at: layout(offset: 1_700, content: 2_000, viewport: 300))
        policy.studentScrolling(false)
        #expect(policy.isFollowing)
        // The stack re-measured rows above: offset and height jump on their own.
        _ = policy.geometryChanged(layout(offset: 1_590, content: 1_950, viewport: 300))
        #expect(policy.isFollowing, "not the student")
    }

    @Test("A reported drag stops following; letting go at the end resumes it, elsewhere not")
    func reportedScrolling() {
        var policy = policy(at: layout(offset: 700, content: 1_000, viewport: 300))
        policy.studentScrolling(true)
        #expect(!policy.isFollowing)
        let during = policy.latestMessageGrew()
        #expect(during == .none)

        _ = policy.geometryChanged(layout(offset: 400, content: 1_000, viewport: 300))
        policy.studentScrolling(false)
        #expect(!policy.isFollowing, "let go mid-thread")

        policy.studentScrolling(true)
        _ = policy.geometryChanged(layout(offset: 700, content: 1_000, viewport: 300))
        policy.studentScrolling(false)
        #expect(policy.isFollowing, "let go at the end")
    }

    @Test("The keyboard rising keeps a student at the bottom at the bottom")
    func keyboardKeepsBottom() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        let result16 = policy.geometryChanged(layout(offset: 400, content: 1_000, viewport: 300))
        #expect(result16
                == .scrollToBottom(animated: false))
        #expect(policy.isFollowing, "a reading-area change is not the student scrolling")
    }

    @Test("The keyboard leaves a student who scrolled up where they are")
    func keyboardLeavesReaderAlone() {
        var policy = policy(at: layout(offset: 100, content: 1_000))
        let result17 = policy.geometryChanged(layout(offset: 100, content: 1_000, viewport: 300))
        #expect(result17 == .none)
    }

    @Test("A footer appearing is shown only to a student following the end")
    func footerFollowsOnlyWhenFollowing() {
        var following = policy(at: layout(offset: 400, content: 1_000))
        #expect(following.footerChanged() == .scrollToBottom(animated: true))

        _ = following.geometryChanged(layout(offset: 100, content: 1_000))
        #expect(following.footerChanged() == .none)
    }

    @Test("A failure line alone opens at its first line; one that fits still lands at the end")
    func bareFailureOpensAtItsTop() {
        let following = policy(at: layout(offset: 400, content: 1_000))
        // `showLatestMessageTop` scrolls the row's top to the top of the
        // reading area, which stops at the end of the thread: a short
        // failure lands where the bottom would, Retry in view; one taller
        // than the reading area (an SE at AX5) shows its first sentence.
        #expect(following.footerChanged(latestIsBareFailure: true) == .showLatestMessageTop)
        #expect(following.footerChanged(latestIsBareFailure: false) == .scrollToBottom(animated: true))

        var reading = policy(at: layout(offset: 400, content: 1_000))
        _ = reading.geometryChanged(layout(offset: 100, content: 1_000))
        #expect(reading.footerChanged(latestIsBareFailure: true) == .none,
                "a student who scrolled up to re-read stays where they are")
    }

    @Test("Jump to latest goes to the bottom and resumes following")
    func jumpToLatest() {
        var policy = policy(at: layout(offset: 400, content: 1_000))
        _ = policy.geometryChanged(layout(offset: 100, content: 1_000))
        #expect(!policy.isFollowing)
        let result18 = policy.jumpToLatest()
        #expect(result18 == .scrollToBottom(animated: true))
        #expect(policy.isFollowing)
    }

    @Test("The pill shows only when the end is well out of view and there is room for it")
    func pillVisibility() {
        #expect(!policy(at: layout(offset: 400, content: 1_000)).showsJumpPill, "at the bottom")
        #expect(!policy(at: layout(offset: 300, content: 1_000)).showsJumpPill, "only 100 pt away")
        #expect(policy(at: layout(offset: 200, content: 1_000)).showsJumpPill)
        #expect(!policy(at: layout(offset: 200, content: 1_000, viewport: 150)).showsJumpPill,
                "an SE at AX3 with the keyboard up has no room for it")
        #expect(policy(at: layout(offset: 200, content: 1_000, viewport: 272)).showsJumpPill,
                "an SE at the default size with the keyboard up does")
        #expect(!MessageScrollPolicy().showsJumpPill, "nothing laid out yet")
    }

    @Test("The pill's own strip can't make it hide itself again")
    func pillStripDoesNotFlicker() {
        // 200 pt to share: the pill shows, and its ~52 pt strip leaves the
        // list 148 pt. Judged on the list alone it would hide again (below
        // the 180 pt minimum), bring the 200 pt back, show, and so on.
        var area = layout(offset: 200, content: 1_000, viewport: 148)
        area.readingAreaHeight = 200
        #expect(policy(at: area).showsJumpPill)

        // The strip only moves the end further away: once the student is
        // within `pillDistance` with the strip in place, it goes, and taking
        // the strip out brings the end closer still.
        var near = layout(offset: 800, content: 1_000, viewport: 148)
        near.readingAreaHeight = 200
        #expect(!policy(at: near).showsJumpPill)
        var nearWithoutStrip = layout(offset: 800, content: 1_000, viewport: 200)
        nearWithoutStrip.readingAreaHeight = 200
        #expect(!policy(at: nearWithoutStrip).showsJumpPill)

        // A small area stays pill-free however it's measured.
        var small = layout(offset: 200, content: 1_000, viewport: 150)
        small.readingAreaHeight = 150
        #expect(!policy(at: small).showsJumpPill)
    }

    @Test("Showing or hiding the pill's strip doesn't move a student who isn't at the end")
    func pillStripResizeLeavesReaderAlone() {
        var policy = policy(at: layout(offset: 200, content: 1_000, viewport: 600))
        #expect(policy.geometryChanged(layout(offset: 200, content: 1_000, viewport: 548)) == .none)
        #expect(policy.geometryChanged(layout(offset: 200, content: 1_000, viewport: 600)) == .none)
    }
}

@Suite("CoachCardPresence (AUD-08)")
struct CoachCardPresenceTests {

    @Test("Focusing the composer takes the card out when it is on screen")
    func hidesWhenOnScreen() {
        var presence = CoachCardPresence()
        let toBottom = presence.composerFocusChanged(
            focused: true, coachOnScreen: true, geometry: layout(content: 500))
        #expect(presence.isHiddenForTyping)
        #expect(toBottom, "a short thread is at its bottom: keep the end in view")
    }

    @Test("A card already scrolled away stays — taking it out would move the text being read")
    func staysWhenOffScreen() {
        var presence = CoachCardPresence()
        let toBottom = presence.composerFocusChanged(
            focused: true, coachOnScreen: false, geometry: layout(offset: 300, content: 1_200))
        #expect(!presence.isHiddenForTyping)
        #expect(!toBottom)
    }

    @Test("It comes back when the keyboard goes, at the top or the bottom")
    func returnsAtTopOrBottom() {
        var atBottom = CoachCardPresence()
        _ = atBottom.composerFocusChanged(focused: true, coachOnScreen: true, geometry: layout(content: 500))
        let result19 = atBottom.composerFocusChanged(focused: false, coachOnScreen: false,
                                              geometry: layout(offset: 600, content: 1_200))
        #expect(result19)
        #expect(!atBottom.isHiddenForTyping)

        var atTop = CoachCardPresence()
        _ = atTop.composerFocusChanged(focused: true, coachOnScreen: true, geometry: layout(content: 500))
        let result20 = atTop.composerFocusChanged(focused: false, coachOnScreen: false,
                                            geometry: layout(offset: 0, content: 1_200))
        #expect(!result20)
        #expect(!atTop.isHiddenForTyping)
    }

    @Test("Mid-thread it waits until the student reaches the top or the bottom")
    func waitsMidThread() {
        var presence = CoachCardPresence()
        _ = presence.composerFocusChanged(focused: true, coachOnScreen: true, geometry: layout(content: 500))
        _ = presence.composerFocusChanged(focused: false, coachOnScreen: false,
                                          geometry: layout(offset: 300, content: 1_200))
        #expect(presence.isHiddenForTyping)

        let result21 = presence.geometryChanged(composerFocused: false, geometry: layout(offset: 250, content: 1_200))
        #expect(!result21)
        #expect(presence.isHiddenForTyping)
        let result22 = presence.geometryChanged(composerFocused: false, geometry: layout(offset: 600, content: 1_200))
        #expect(result22)
        #expect(!presence.isHiddenForTyping)
    }

    @Test("On screen is worked out from the scroll offset, not a remembered frame")
    func onScreenFromOffset() {
        // The card is the first row: 12 pt of padding, then 136 pt of card.
        #expect(CoachCardPresence.isOnScreen(coachHeight: 136, topInset: 12, geometry: layout(content: 900)))
        #expect(CoachCardPresence.isOnScreen(coachHeight: 136, topInset: 12,
                                             geometry: layout(offset: 140, content: 900)))
        #expect(!CoachCardPresence.isOnScreen(coachHeight: 136, topInset: 12,
                                              geometry: layout(offset: 156, content: 900)),
                "the SE case: scrolled 156 pt, the card ended 8 pt above the top")
        #expect(!CoachCardPresence.isOnScreen(coachHeight: 0, topInset: 12, geometry: layout(content: 900)),
                "not measured yet")
    }

    @Test("Never back while the student is still typing")
    func notWhileTyping() {
        var presence = CoachCardPresence()
        _ = presence.composerFocusChanged(focused: true, coachOnScreen: true, geometry: layout(content: 500))
        let result23 = presence.geometryChanged(composerFocused: true, geometry: layout(content: 500))
        #expect(!result23)
        #expect(presence.isHiddenForTyping)
    }
}

@Suite("Lesson header copy (AUD-51)")
struct LessonHeaderCopyTests {

    @Test("The eyebrow places the lesson in its unit instead of an unlabelled 0/4")
    func eyebrowSaysWhichLesson() {
        #expect(CurriculumLessonView.eyebrow(unitLabel: "UNIT 01", lessonNumber: 2, totalInUnit: 4)
                == "UNIT 01 · LESSON 2 OF 4")
        #expect(CurriculumLessonView.eyebrow(unitLabel: "UNIT 01", lessonNumber: 2, totalInUnit: 0)
                == "UNIT 01 · LESSON 2")
    }

    @Test("The title gets two lines in the header, and moves to the thread at accessibility sizes")
    func titleIsAlwaysSomewhere() {
        // One line truncated every title at the default size.
        #expect(LessonHeaderBar.titleLineLimit == 2)
        #expect(LessonHeaderBar.showsTitle(at: .large))
        #expect(LessonHeaderBar.showsTitle(at: .xxxLarge))
        // There the header keeps its room for the lesson (AUD-08) and the
        // lesson view hands the title to the thread's first row instead.
        #expect(!LessonHeaderBar.showsTitle(at: .accessibility1))
        #expect(!LessonHeaderBar.showsTitle(at: .accessibility5))
    }
}

@Suite("Lesson replay fixture")
struct LessonReplayFixtureTests {

    @Test("The recorded replies parse cleanly, each first reply check a well-formed [Q]")
    func recordedRepliesParse() {
        #expect(LessonReplay.replies.count == 3)
        for reply in LessonReplay.replies.prefix(2) {
            let quizzes = BlockParser.parse(reply).compactMap { block -> QuizBlock? in
                if case .quiz(let quiz) = block { return quiz }
                return nil
            }
            #expect(quizzes.count == 1)
            #expect(quizzes.first?.isWellFormed == true)
        }
    }
}

@Suite("The end of the thread (AUD-09, AUD-29)")
@MainActor
struct ThreadEndTests {

    @Test("A reply that failed before any text is a failure line alone")
    func bareFailure() {
        #expect(MessageListView.isBareFailure(
            ChatMessage(role: .assistant, content: "", status: .failed(reason: "This network may be blocking Mercurius."))))
        #expect(MessageListView.isBareFailure(
            ChatMessage(role: .assistant, content: "  \n", status: .failed(reason: "Network error. Try again."))))
    }

    @Test("A cut-off reply, a reply still streaming, a settled reply and the student's turn are not")
    func notBareFailure() {
        #expect(!MessageListView.isBareFailure(
            ChatMessage(role: .assistant, content: "Half a reply", status: .failed(reason: "Network error. Try again."))))
        #expect(!MessageListView.isBareFailure(ChatMessage(role: .assistant, content: "", status: .streaming)))
        #expect(!MessageListView.isBareFailure(ChatMessage(role: .assistant, content: "Done.")))
        #expect(!MessageListView.isBareFailure(ChatMessage(role: .user, content: "")))
        #expect(!MessageListView.isBareFailure(nil))
    }
}
