import SwiftUI

/// The Merc lesson flow entry point — from `MERC_HANDOFF.md` Part B §4: a single
/// `Stage`→view switch over one `LessonViewModel`.
///
/// Built incrementally per the handoff: `intro` is live (`IntroSpeechBubble`);
/// the remaining placements (`ChatBottomAnchor`, `ExerciseFloatingHelper`,
/// `CelebrationSheet`, `DoneView`) land one at a time and replace the
/// placeholders below.
public struct LessonView: View {
    @StateObject private var vm = LessonViewModel()

    public init() {}

    public var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            switch vm.stage {
            case .intro:     IntroSpeechBubble(vm: vm)
            case .chat:      ChatBottomAnchor(vm: vm)
            case .exercise:  ExerciseFloatingHelper(vm: vm)
            case .celebrate: CelebrationSheet(vm: vm)
            case .done:      DoneView(vm: vm)
            }
        }
        .onAppear {
            vm.onAppear()
            #if DEBUG
            // Jump straight to a placement for on-device checks.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-MercFlowChat") { vm.startChat() }
            if args.contains("-MercFlowExercise") { vm.startChat(); vm.goExercise() }
            if args.contains("-MercFlowCelebrate") { vm.startChat(); vm.goExercise(); vm.answer(correct: true) }
            if args.contains("-MercFlowDone") { vm.startChat(); vm.goExercise(); vm.answer(correct: true); vm.finish() }
            #endif
        }
    }

}
