import Testing
@testable import MercFlowFeature

// Synchronous transitions of the Part B LessonViewModel state machine.
// (The async reverts — wave→idle after 1.8s, idle→sleep after 60s — aren't
// timing-tested here; only the immediate event→state mapping is.)

@MainActor
struct LessonViewModelTests {

    @Test func startsInIntroIdle() {
        let vm = LessonViewModel()
        #expect(vm.stage == .intro)
        #expect(vm.merc == .idle)
    }

    @Test func onAppearWavesHello() {
        let vm = LessonViewModel()
        vm.onAppear()
        #expect(vm.merc == .wave)   // reverts to .idle after 1.8s (not tested here)
    }

    @Test func startChatSeedsTheFirstMercMessage() {
        let vm = LessonViewModel()
        vm.startChat()
        #expect(vm.stage == .chat)
        #expect(vm.messages.count == 1)
        #expect(vm.messages.first?.role == .merc)
    }

    @Test func sendPushesUserMessageAndThinks() {
        let vm = LessonViewModel()
        vm.input = "How does that work?"
        vm.send()
        #expect(vm.merc == .thinking)
        #expect(vm.input == "")
        #expect(vm.messages.last?.role == .user)
    }

    @Test func sendIgnoresEmptyInput() {
        let vm = LessonViewModel()
        vm.input = "   "
        vm.send()
        #expect(vm.merc == .idle)
        #expect(vm.messages.isEmpty)
    }

    @Test func correctAnswerCelebratesAndAdvancesProgress() {
        let vm = LessonViewModel()
        vm.answer(correct: true)
        #expect(vm.stage == .celebrate)
        #expect(vm.merc == .celebrate)
        #expect(vm.answered)
        #expect(vm.progress == 0.75)
    }

    @Test func wrongAnswerShowsRetryWithoutAdvancing() {
        let vm = LessonViewModel()
        vm.answer(correct: false)
        #expect(vm.showWrong)
        #expect(vm.answered == false)
        #expect(vm.stage == .intro)
    }

    @Test func wakeFromSleepReturnsToIdle() {
        let vm = LessonViewModel()
        vm.merc = .sleep
        vm.wake()
        #expect(vm.merc == .idle)
    }
}
