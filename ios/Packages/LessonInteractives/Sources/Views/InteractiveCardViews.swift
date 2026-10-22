import SwiftUI

/// Each card's view on this platform, by id: the one switch a card builder
/// edits (replace the card's `InteractivePlaceholderCard` line with its
/// `<Card>PhoneCard` / `Night<Card>Card`, and add its id to `built`).
///
/// Lesson 1.1's tokenizer is drawn by ChatFeature (`LessonTokenizerCard`,
/// `NightInteractiveCard`), which routes it before asking here.
public enum InteractiveCardViews {
    /// The cards whose views exist on both platforms. Only these may be
    /// enabled (`RegistryTests`).
    public static let built: Set<InteractiveID> = [
        .tokenizer,

        .pageWithASecret,
    ]

    /// The card's view, with its context (spec, spoiled, the lesson's state).
    @MainActor @ViewBuilder
    public static func card(_ context: InteractiveCardContext) -> some View {
        #if os(macOS)
        mac(context)
        #else
        phone(context)
        #endif
    }

    #if os(iOS)
    @MainActor @ViewBuilder
    static func phone(_ context: InteractiveCardContext) -> some View {
        switch context.id {
        case .doubtDial:
            InteractivePlaceholderCard(context)

        case .pageWithASecret:
            PageWithASecretPhoneCard(context)

        case .citationThatWasnt:
            InteractivePlaceholderCard(context)

        case .deleteTheGenderBox:
            InteractivePlaceholderCard(context)

        case .patchTheReward:
            InteractivePlaceholderCard(context)

        case .whosInTheTest, .wardOf1000, .predictTheExam, .twoTestsOneLine, .grownFromStatic, .readMyMind:
            InteractivePlaceholderCard(context)

        case .tokenizer:
            // ChatFeature draws Lesson 1.1's card.
            InteractivePlaceholderCard(context)
        }
    }
    #endif

    #if os(macOS)
    @MainActor @ViewBuilder
    static func mac(_ context: InteractiveCardContext) -> some View {
        switch context.id {
        case .doubtDial:
            InteractivePlaceholderCard(context)

        case .pageWithASecret:
            NightPageWithASecretCard(context)

        case .citationThatWasnt:
            InteractivePlaceholderCard(context)

        case .deleteTheGenderBox:
            InteractivePlaceholderCard(context)

        case .patchTheReward:
            InteractivePlaceholderCard(context)

        case .whosInTheTest, .wardOf1000, .predictTheExam, .twoTestsOneLine, .grownFromStatic, .readMyMind:
            InteractivePlaceholderCard(context)

        case .tokenizer:
            // ChatFeature draws Lesson 1.1's card.
            InteractivePlaceholderCard(context)
        }
    }
    #endif
}

/// A card that has a place in its lesson and no view yet. A dark card
/// never reaches a student, so only DEBUG's `-Interactive <slug>` and
/// `-InteractiveGallery <slug>` show it: the framework's placement and
/// frame, with nothing pretending to be the card.
public struct InteractivePlaceholderCard: View {
    private let context: InteractiveCardContext

    public init(_ context: InteractiveCardContext) {
        self.context = context
    }

    public var body: some View {
        InteractiveCardShell(id: context.id, title: InteractiveShellCopy.placeholderTitle,
                             compactLine: InteractiveShellCopy.placeholderBody(context.id)) {
            PlaceholderBody(context: context)
        }
    }
}

private struct PlaceholderBody: View {
    let context: InteractiveCardContext
    @Environment(\.interactiveTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            Text(InteractiveShellCopy.placeholderBody(context.id))
                .interactiveText(.callout)
                .foregroundStyle(theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            #if DEBUG
            InteractiveTextTable([
                .init("Lesson", context.spec.lessonID),
                .init("Anchor", "\(context.spec.anchor)"),
                .init("Spoiled mode", context.spoiled ? "yes" : "no"),
            ])
            #endif
        }
    }
}
