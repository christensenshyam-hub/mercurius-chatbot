import SwiftUI
import DesignSystem
import LessonInteractives

/// A lesson's interactive other than Lesson 1.1's, as this platform draws
/// it: the card's view from LessonInteractives (`InteractiveCardViews`),
/// given its row in the registry, whether it opens spoiled, and the
/// lesson's `InteractiveStateStore` (so a reply's re-render never resets
/// it). Lesson 1.1's card is drawn by `LessonTokenizerCard` (iPhone) and
/// `NightInteractiveCard` (Mac) as before; the bubble and the Mac's reply
/// route it there.
struct LessonInteractiveCardView: View {
    let card: LessonInteractiveCardRef
    @Environment(InteractiveStateStore.self) private var shared: InteractiveStateStore?
    @State private var local = InteractiveStateStore()

    var body: some View {
        if let spec = InteractiveRegistry.spec(for: card.id) {
            // `-InteractiveState spoiled` (DEBUG shots): the spoiled mode
            // whatever the tutor said.
            let spoiled = card.spoiled || InteractiveLaunchOptions.current.state == .spoiled
            InteractiveCardViews.card(InteractiveCardContext(spec: spec, spoiled: spoiled, store: shared ?? local))
        }
    }
}

extension View {
    /// The card's scroll ids in the lesson's list: the card itself, and in
    /// DEBUG its top and bottom edges (`-InteractiveScroll top|after`). A
    /// card marks its own reveal (`InteractiveScrollID.reveal`).
    func lessonInteractiveScrollMarks() -> some View {
        self
            .id(InteractiveScrollID.card)
            #if DEBUG
            .overlay(alignment: .top) {
                Color.clear.frame(height: 1).id(InteractiveScrollID.top)
            }
            .overlay(alignment: .bottom) {
                Color.clear.frame(height: 1).id(InteractiveScrollID.after)
            }
            #endif
    }
}

#if DEBUG
/// DEBUG `-InteractiveGallery <slug>`: one card alone, on the lesson's
/// background, with no lesson, server or replay, for screenshots. The card
/// is drawn by the same views as in a lesson (Lesson 1.1's included), with a
/// state store of its own; `-InteractiveState` sets its state as in a
/// lesson. The iPhone: the bubble's width and margins. The Mac: Night's
/// canvas and the reading column (a window under about 520 pt wide shows
/// the compact card, as a narrow lesson does).
public struct InteractiveGalleryView: View {
    private let id: InteractiveID
    @State private var store = InteractiveStateStore()
    @State private var tokenizer = TokenizerState()

    public init(id: InteractiveID) {
        self.id = id
    }

    public var body: some View {
        ZStack {
            #if os(macOS)
            NightCanvas(pools: .indigo, stars: false)
            #else
            BrandColor.background.ignoresSafeArea()
            #endif
            ScrollViewReader { proxy in
                ScrollView {
                    card
                        #if os(macOS)
                        .padding(.horizontal, NightRowMetrics.gutter)
                        .padding(.vertical, 24)
                        .macReadableColumn()
                        #else
                        .frame(maxWidth: 560, alignment: .leading)
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.xl)
                        .frame(maxWidth: .infinity)
                        #endif
                }
                // As in a lesson: a card brings a part of itself into view,
                // once the update that asked for it is laid out.
                .environment(\.interactiveScrollIntoView,
                             InteractiveScrollAction(key: "gallery") { id, animated in
                                 DispatchQueue.main.async {
                                     if animated {
                                         withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: nil) }
                                     } else {
                                         proxy.scrollTo(id, anchor: nil)
                                     }
                                 }
                             })
            }
        }
        .environment(store)
        .environment(tokenizer)
    }

    @ViewBuilder private var card: some View {
        if id == .tokenizer {
            #if os(macOS)
            NightInteractiveCard()
            #else
            LessonTokenizerCard()
            #endif
        } else {
            LessonInteractiveCardView(card: LessonInteractiveCardRef(id: id, spoiled: false))
        }
    }
}
#endif
