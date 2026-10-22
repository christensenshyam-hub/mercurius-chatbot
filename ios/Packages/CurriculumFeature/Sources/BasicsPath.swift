import SwiftUI
import DesignSystem

/// The words on Basics' path (BEGINNER_GUIDE §2.1, §2.5): progress as lessons
/// finished, in words, never a streak or a percentage.
public enum BasicsPathCopy {
    /// The path's title and its tab, in place of "Curriculum".
    public static let title = "Lessons"

    static func finished(done: Int, total: Int) -> String {
        switch done {
        case 0: return "\(total) short lessons. Start with the first one."
        case total: return "You've finished all \(total) lessons."
        case 1: return "You've finished 1 lesson of \(total)."
        default: return "You've finished \(done) lessons of \(total)."
        }
    }

    static let textSize = "Text size"
    static let textSizeDetail = "Pick a size for the Basics lessons."
    static let done = "Done"
}

/// Basics' text size on the path: the one-time "Want the words bigger?"
/// offer, then a small "Text size" button that opens the same choice.
/// iPhone only: the Mac has no Dynamic Type for it to change.
struct BasicsReadingSizeControl: View {
    @Bindable var tracks: CurriculumTrackStore
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if os(iOS)
        // A system size at or above the largest choice makes every choice
        // the same: nothing to offer.
        if !tracks.basicsReadingSize.offersChoice(atFlooredSize: dynamicTypeSize) {
            EmptyView()
        } else if tracks.offersReadingSize {
            ReadingSizeOffer(current: tracks.basicsReadingSize,
                             onChoose: { tracks.setBasicsReadingSize($0) },
                             onDismiss: { tracks.markReadingSizeOfferHandled() })
                .frame(maxWidth: 420)
        } else if expanded {
            ReadingSizeOffer(current: tracks.basicsReadingSize,
                             detail: BasicsPathCopy.textSizeDetail,
                             dismissTitle: BasicsPathCopy.done,
                             onChoose: { tracks.setBasicsReadingSize($0) },
                             onDismiss: { expanded = false })
                .frame(maxWidth: 420)
        } else {
            Button { expanded = true } label: {
                Label(BasicsPathCopy.textSize, systemImage: "textformat.size")
                    .font(BrandFont.bodyEmphasized)
                    .foregroundStyle(BrandColor.accentText)
                    .frame(minHeight: 44)
                    .padding(.horizontal, BrandSpacing.md)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("basics.textSize")
        }
        #else
        EmptyView()
        #endif
    }
}
