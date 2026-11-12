import SwiftUI
import DesignSystem

/// The step's one primary action, pinned above the keyboard and inside the
/// safe area. Secondary actions (a hint, Edit, Cancel) sit beside it.
struct ActionBar: View {
    let model: LessonPlayerModel

    var body: some View {
        let plan = ActionPlan(machine: model.machine)
        VStack(spacing: BrandSpacing.sm) {
            if let secondary = plan.secondary {
                Button(secondary.title) { model.send(secondary.action) }
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("player.secondary")
            }
            BrandButton(plan.primary.title, style: .primary, isEnabled: plan.primary.enabled) {
                if plan.primary.action == .leaveFinished {
                    model.send(.advance(from: model.step.id))
                } else if let action = plan.primary.playerAction {
                    model.send(action)
                }
            }
            // A new label replaces the old one outright: no cross-fade with
            // both titles half-drawn.
            .id(plan.primary.title)
            .transaction { $0.animation = nil }
            .accessibilityIdentifier("player.primary")
            .overlay(alignment: .leading) {
                if plan.primary.busy { ProgressView().padding(.leading, BrandSpacing.lg).accessibilityHidden(true) }
            }
        }
        .padding(.horizontal, BrandSpacing.lg)
        .padding(.top, BrandSpacing.sm)
        .padding(.bottom, BrandSpacing.sm)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(BrandColor.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}

/// Which actions a step offers, worked out from the machine alone so it's
/// testable without a view.
struct ActionPlan: Equatable {
    enum Kind: Equatable { case check, `continue`, tryAgain, retry, finish, checking, leaveFinished }

    struct Primary: Equatable {
        let title: String
        let enabled: Bool
        let busy: Bool
        let action: Kind
        let playerAction: PlayerAction?
    }

    struct Secondary: Equatable {
        let title: String
        let action: PlayerAction
    }

    let primary: Primary
    let secondary: Secondary?

    init(machine: LessonMachine) {
        let step = machine.currentStep
        let record = machine.currentRecord
        let advance = PlayerAction.advance(from: step.id)
        switch step.kind {
        case .teach:
            primary = Primary(title: PlayerCopy.continue, enabled: true, busy: false, action: .continue, playerAction: advance)
            secondary = nil
        case .finish:
            primary = Primary(title: PlayerCopy.finish, enabled: true, busy: false, action: .leaveFinished, playerAction: advance)
            secondary = nil
        case .activity(let activity):
            switch record.phase {
            case .viewing:
                let isPractice: Bool = { if case .practice = activity.kind { return true }; return false }()
                primary = Primary(title: isPractice ? PlayerCopy.send : PlayerCopy.check, enabled: machine.canSubmit,
                                  busy: false, action: .check, playerAction: .submit)
                secondary = record.hintsShown < activity.hints.count
                    ? Secondary(title: PlayerCopy.showHint, action: .showHint) : nil
            case .awaitingGrade:
                let isPractice: Bool = { if case .practice = activity.kind { return true }; return false }()
                primary = Primary(title: isPractice ? PlayerCopy.waitingForMerc : PlayerCopy.checking,
                                  enabled: false, busy: true, action: .checking, playerAction: nil)
                secondary = Secondary(title: PlayerCopy.cancel, action: .cancelEvaluation)
            case .feedback, .done:
                if machine.isCurrentStepResolved {
                    primary = Primary(title: PlayerCopy.continue, enabled: true, busy: false, action: .continue, playerAction: advance)
                    secondary = nil
                } else if case .ungraded? = record.lastSubmission?.status {
                    primary = Primary(title: PlayerCopy.retry, enabled: true, busy: false, action: .retry, playerAction: .retryEvaluation)
                    secondary = Secondary(title: PlayerCopy.editAnswer, action: .tryAgain)
                } else {
                    primary = Primary(title: activity.isDeterministic ? PlayerCopy.tryAgain : PlayerCopy.revise,
                                      enabled: true, busy: false, action: .tryAgain, playerAction: .tryAgain)
                    secondary = nil
                }
            }
        }
    }
}
