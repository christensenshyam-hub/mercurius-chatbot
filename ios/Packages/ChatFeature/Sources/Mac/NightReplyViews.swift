#if os(macOS)
import SwiftUI
import AppKit
import DesignSystem
import MarkdownUI
import NetworkingKit

/// One turn of a chat or lesson on the Mac, in Night Studio (SPEC.md §5.3,
/// §5.4): Merc's reply is type on the page (no bubble), the student's turns
/// are tinted cards. `MessageListView` draws this in place of
/// `MessageBubbleView` on the Mac; the iPhone keeps the bubble.
///
/// What the student can do with a turn is unchanged: Copy and Report in its
/// right-click menu (and as VoiceOver actions on each block), the [Q]
/// check's pick (now with Lock it in), the check question's tap to answer.
struct NightMessageRow: View {
    enum Style: Equatable { case lesson, chat }

    let message: ChatMessage
    let style: Style
    /// Lessons: this reply's parts (split once by the list, which counts
    /// them across the thread) and the number of the first.
    var sections: [NightSection] = []
    var firstPart: Int = 1
    /// Free chat: the latest completed reply's closing question becomes the
    /// Your turn card.
    var showsYourTurn = false
    /// The thread carried a crisis line at or before this reply
    /// (`NightCrisisGuard.guardedReplies`): drawn as plain text.
    var crisisThread = false
    /// Free chat: "Merc · AI tutor" heads the thread's first reply only.
    var showsMercLabel = false
    /// The live Merc state, on the latest reply's badge only.
    var mercMood: MercMood = .neutral
    var mercActivity: MercActivity = .idle
    var quizInteraction: MessageBubbleView.QuizInteraction?
    var onReport: (ReportReason) -> Void = { _ in }
    var onCheckTap: (() -> Void)?
    /// The list's coordinate space, where part marks report their place.
    var coordinateSpace = ""
    var onPartMarkMoved: (Int, CGFloat) -> Void = { _, _ in }
    /// Lesson 1.1: where this reply holds the interactive
    /// (`NightInteractiveAnchor`), nil for every other reply.
    var interactiveAfter: NightInteractivePosition?

    var body: some View {
        switch message.role {
        case .user: NightStudentCard(message: message)
        case .assistant: reply
        }
    }

    // MARK: Merc's reply

    private var isStreaming: Bool { message.status == .streaming }

    private var isEmptyTyping: Bool { message.content.isEmpty && isStreaming }

    private var pieces: [NightReplyPiece] {
        let crisis = crisisThread || NightCrisisGuard.applies(to: message.content)
        switch style {
        case .lesson:
            return NightReplyLayout.lesson(sections: sections, firstPart: firstPart, crisis: crisis,
                                           isStreaming: isStreaming, interactiveAfter: interactiveAfter)
        case .chat:
            return NightReplyLayout.chat(content: message.content, isStreaming: isStreaming,
                                         yourTurn: showsYourTurn, crisis: crisis)
        }
    }

    private var reply: some View {
        let bareFailure = MessageBubbleView.isEmptyFailure(message)
        let readsAsBlocks = MessageBubbleView.readsAsBlocks(message, lessonStyle: true)
        return VStack(alignment: .leading, spacing: 14) {
            if style == .chat && showsMercLabel && !bareFailure {
                NightMercLabel()
            }
            if isEmptyTyping {
                NightTypingIndicator()
            } else if !bareFailure {
                let pieces = pieces
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    pieceView(piece)
                }
            }
            if case .failed(let reason) = message.status {
                NightFailureLine(reason: reason)
            }
            if message.status == .interrupted {
                Label("Reply cut off here", systemImage: "scissors")
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NightRowMetrics.gutter)
        .contentShape(Rectangle())
        .contextMenu {
            if !message.content.isEmpty {
                Button("Copy", systemImage: "doc.on.doc") {
                    MacPasteboard.copy(MacMessageCopy.text(for: message))
                }
                Menu("Report response", systemImage: "flag") {
                    ForEach(ReportReason.allCases, id: \.self) { reason in
                        Button(reason.title) { onReport(reason) }
                            .accessibilityIdentifier("report.\(reason.rawValue)")
                    }
                }
            }
        }
        // A settled reply is a container: each paragraph, card and option is
        // its own stop (the source chip and the check's options stay real
        // buttons). A reply still streaming, or one that never arrived,
        // reads as one element (AUD-23).
        .accessibilityElement(children: readsAsBlocks ? .contain : .combine)
        .accessibilityLabel(readsAsBlocks ? Text("Merc's reply") : collapsedLabel)
    }

    private var collapsedLabel: Text {
        if isStreaming { return Text("Merc is replying") }
        if case .failed(let reason) = message.status {
            return Text("Merc's reply didn't arrive. \(reason)")
        }
        return Text("Merc replied: \(BlockParser.plainText(message.content))")
    }

    @ViewBuilder
    private func pieceView(_ piece: NightReplyPiece) -> some View {
        let reports = !message.content.isEmpty
        switch piece {
        case .partMark(let number, let name):
            NightPartMark(number: number, name: name)
                .id(NightPartMark.scrollID(number))
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.frame(in: .named(coordinateSpace)).minY
                } action: { minY in
                    onPartMarkMoved(number, minY)
                }
        case .markdown(let text), .plain(let text):
            // Merc's prose with curly quotes (Lexend draws straight ones as
            // inch marks); code and link addresses untouched.
            Markdown(NightTypography.curlQuotes(text))
                .nightReplyMarkdown()
                .accessibilityElement(children: .combine)
                .modifier(NightReportActions(enabled: reports, onReport: onReport))
        case .source(let source):
            NightSourceChip(source: source)
        case .example(let text):
            NightExampleCard(text: text)
                .modifier(NightReportActions(enabled: reports, onReport: onReport))
        case .key(let text):
            NightKeyCard(text: text)
                .modifier(NightReportActions(enabled: reports, onReport: onReport))
        case .openQuestion(let text):
            NightYourTurnCard(text: text, onTap: onCheckTap)
                .modifier(NightReportActions(enabled: reports, onReport: onReport))
        case .yourTurn(let text):
            NightYourTurnCard(text: text, onTap: nil)
                .modifier(NightReportActions(enabled: reports, onReport: onReport))
        case .quiz(let quiz):
            NightCheckCard(
                quiz: quiz,
                isEnabled: quiz.isWellFormed && quizInteraction?.isEnabled == true,
                answeredIndex: quizInteraction?.answeredIndex,
                onSelect: { index in quizInteraction?.onPick(quiz, index) },
                routeID: message.id
            )
        case .interactive:
            NightInteractiveCard()
                .id(NightInteractiveCard.scrollID)
        }
    }
}

extension NightMessageRow: Equatable {
    /// The closures are left out, as `MessageBubbleView`'s are: the list
    /// builds them from stable references.
    nonisolated static func == (lhs: NightMessageRow, rhs: NightMessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.style == rhs.style
            && lhs.sections == rhs.sections
            && lhs.firstPart == rhs.firstPart
            && lhs.showsYourTurn == rhs.showsYourTurn
            && lhs.crisisThread == rhs.crisisThread
            && lhs.showsMercLabel == rhs.showsMercLabel
            && lhs.mercMood == rhs.mercMood
            && lhs.mercActivity == rhs.mercActivity
            && lhs.coordinateSpace == rhs.coordinateSpace
            && lhs.interactiveAfter == rhs.interactiveAfter
            && (lhs.quizInteraction == nil) == (rhs.quizInteraction == nil)
            && lhs.quizInteraction?.isEnabled == rhs.quizInteraction?.isEnabled
            && lhs.quizInteraction?.answeredIndex == rhs.quizInteraction?.answeredIndex
    }
}

enum NightRowMetrics {
    /// The reading column's inner margin: 620 − 2 × 20 leaves the 580 pt
    /// reply measure.
    static let gutter: CGFloat = 20
    /// The student's cards: at most 75% of the column.
    static let studentMaxWidth: CGFloat = 465
}

// MARK: - Who is speaking

/// "Merc · AI tutor" over the first reply of a free chat, set as type (the
/// concept's way): the bubble-less, left-aligned reply already says who is
/// speaking after that. No bust: at 20 pt his face didn't read. It doesn't
/// name the mode: a thread's mode can change.
struct NightMercLabel: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(NightReplyCopy.merc)
                .nightFont(.headline)
                .foregroundStyle(Night.ink)
            Text(NightReplyCopy.aiTutor)
                .nightFont(.caption)
                .foregroundStyle(Night.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightReplyCopy.mercAccessibility)
    }
}

/// The student's turn: a tinted card at the trailing edge, at most 75% of
/// the column, with a 6 pt bottom-trailing corner. A photo sits inside it,
/// above the text.
struct NightStudentCard: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var scheme
    @NightSettings private var night

    var body: some View {
        let dark = scheme == .dark
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                           bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
        HStack(spacing: 0) {
            Spacer(minLength: 48)
            VStack(alignment: .leading, spacing: 10) {
                if let preview = message.image?.preview {
                    Image(preview, scale: 1, label: Text("Attached photo"))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
                        .accessibilityLabel("Attached photo")
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .nightFont(.body)
                        .foregroundStyle(Night.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Night.accent.opacity(Night.Tint.student(dark: dark)), in: shape)
            .overlay(shape.strokeBorder(night.increasedContrast ? Night.hairline
                                            : Night.lumen.opacity(Night.Tint.studentEdge(dark: dark)),
                                        lineWidth: 1))
            .frame(maxWidth: NightRowMetrics.studentMaxWidth, alignment: .trailing)
            .contextMenu {
                if !message.content.isEmpty {
                    Button("Copy", systemImage: "doc.on.doc") {
                        MacPasteboard.copy(MacMessageCopy.text(for: message))
                    }
                }
            }
        }
        .padding(.horizontal, NightRowMetrics.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NightReplyCopy.studentAccessibility(
            message.content.isEmpty ? "Attached photo" : message.content))
    }
}

// MARK: - Part marks

/// The mark before a lesson part (§5.3.2): "02", a short lumen stroke, the
/// part's name as an `ink3` eyebrow. A header for VoiceOver.
struct NightPartMark: View {
    let number: Int
    let name: String?
    @NightSettings private var night

    static func scrollID(_ number: Int) -> String { "night-part-\(number)" }

    var body: some View {
        HStack(spacing: 10) {
            Text(NightReplyCopy.partNumber(number))
                .font(NightType.lexend(12, semibold: true))
                .monospacedDigit()
                .foregroundStyle(Night.accentText)
            Capsule()
                .fill(night.increasedContrast
                      ? AnyShapeStyle(Night.accentText)
                      : AnyShapeStyle(LinearGradient(colors: [Night.lumen, Night.lumen.opacity(0)],
                                                     startPoint: .leading, endPoint: .trailing)))
                .frame(width: 28, height: 2)
            if let name {
                Text(name.uppercased())
                    .nightFont(.eyebrow)
                    .foregroundStyle(Night.ink3)
                    .lineLimit(1)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NightReplyCopy.partAccessibility(number, name: name))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cards

/// Inline Markdown (emphasis, code, links) in a `Text`, for the cards.
func nightInlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text,
                           options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

/// The words of `text` without Markdown, for VoiceOver.
func nightSpoken(_ text: String) -> String {
    String(nightInlineMarkdown(text).characters)
}

/// [EX]: a lit card. The eyebrow; a token line only when the example says
/// how a quoted word splits into quoted tokens (`NightTokenLine`); then the
/// example's own words, verbatim.
struct NightExampleCard: View {
    let text: String

    var body: some View {
        let match = NightTokenLine.recognize(text)
        VStack(alignment: .leading, spacing: 14) {
            NightEyebrow(NightReplyCopy.example, systemImage: "scope")
            if let match {
                NightFlow(spacing: 8, lineSpacing: 8) {
                    Text(match.word)
                        .nightFont(.machine)
                        .foregroundStyle(Night.ink)
                        .padding(.vertical, 5)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Night.ink3)
                        .padding(.vertical, 7)
                    ForEach(Array(match.pieces.enumerated()), id: \.offset) { _, piece in
                        NightTokenChip(piece)
                    }
                }
            }
            Text(nightInlineMarkdown(NightTypography.curlQuotes(text)))
                .nightFont(.body)
                .foregroundStyle(Night.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([NightReplyCopy.example + ":", match.map(NightReplyCopy.tokenLineAccessibility),
                              nightSpoken(text)] as [String?]).compactMap { $0 }.joined(separator: " "))
    }
}

/// [KEY]: a lit card under the lumen wash, the idea in the "keep" face
/// (New York). Nothing here says it was saved: there is no notebook.
struct NightKeyCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightEyebrow(NightReplyCopy.keyIdea, systemImage: "key.fill")
            Text(nightInlineMarkdown(NightTypography.curlQuotes(text)))
                .nightFont(.keep)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightWash()
        .nightLit(radius: Night.Radius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key idea: \(nightSpoken(text))")
    }
}

/// Merc's question to the student, as the thing to answer: a lit card under
/// the lumen wash, "Your turn", the question in the "keep" face. The free
/// chat's closing question stays selectable (and Copy copies the whole
/// reply). A lesson's [CHECK] question takes a click to the composer
/// instead (`onTap`), as the iPhone's callout does.
struct NightYourTurnCard: View {
    let text: String
    let onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { card(selectable: false) }
                .buttonStyle(NightCardButtonStyle(cornerRadius: Night.Radius.card))
                .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.card, style: .continuous))
                .help("Answer in the message box")
                .accessibilityLabel("Your turn: \(nightSpoken(text))")
                .accessibilityHint("Moves to the message box to answer")
        } else {
            card(selectable: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your turn: \(nightSpoken(text))")
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func card(selectable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NightEyebrow(NightReplyCopy.yourTurn, systemImage: "arrow.turn.down.right")
            question(selectable: selectable)
        }
        .padding(Night.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightWash()
        .nightLit(radius: Night.Radius.card)
    }

    @ViewBuilder
    private func question(selectable: Bool) -> some View {
        let label = Text(nightInlineMarkdown(NightTypography.curlQuotes(text)))
            .nightFont(.keep)
            .foregroundStyle(Night.ink)
            .fixedSize(horizontal: false, vertical: true)
        if selectable {
            label.textSelection(.enabled)
        } else {
            label
        }
    }
}

// MARK: - Source chip

/// A source Merc cited (§5.4): a lit row with the title and "Cited by Merc ·
/// domain". It opens only when there is an address `ReplyLinkPolicy`
/// allows; otherwise it is an inert citation (no arrow, no hover). Nothing
/// is fetched for it: no favicon, no preview.
struct NightSourceChip: View {
    let source: NightSource
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = source.url {
            Button { openURL(url) } label: { row(opens: true) }
                .buttonStyle(NightCardButtonStyle(cornerRadius: Night.Radius.row))
                .nightFocusRing(RoundedRectangle(cornerRadius: Night.Radius.row, style: .continuous))
                .macPointingHand()
                .onKeyPress(.return) {
                    openURL(url)
                    return .handled
                }
                .help(NightReplyCopy.sourceHelp)
                .accessibilityLabel(NightReplyCopy.sourceAccessibility(source, opens: true))
                .accessibilityAddTraits(.isLink)
        } else {
            row(opens: false)
                .help(NightReplyCopy.sourceInertHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NightReplyCopy.sourceAccessibility(source, opens: false))
        }
    }

    private func row(opens: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Night.accentText)
                .frame(width: 32, height: 32)
                .background(Night.lumen.opacity(Night.Tint.well),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .nightFont(.headline)
                    .foregroundStyle(Night.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NightReplyCopy.sourceCaption(domain: source.domain))
                    .nightFont(.caption)
                    .foregroundStyle(Night.ink3)
            }
            Spacer(minLength: 0)
            if opens {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Night.ink3)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightLit(radius: Night.Radius.row)
    }
}

// MARK: - States

/// Merc at work: three lumen dots that pulse (still under Reduce Motion),
/// always with the words, so the state never rests on motion alone.
struct NightTypingIndicator: View {
    @NightSettings private var night
    @State private var isOn = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Night.lumen)
                        .frame(width: 6, height: 6)
                        .opacity(night.reduceMotion ? 0.8 : (isOn ? 1 : 0.3))
                        .animation(night.reduceMotion ? nil
                                   : .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                       .delay(Double(index) * 0.15),
                                   value: isOn)
                }
            }
            Text("Merc is thinking…")
                .nightFont(.caption)
                .foregroundStyle(Night.ink3)
        }
        .frame(minHeight: 24)
        .onAppear { if !night.reduceMotion { isOn = true } }
        .onDisappear { isOn = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Merc is thinking")
    }
}

/// A reply that failed: the reason in reading text, after an `errorText`
/// mark. No colour wash, no sad Merc; Retry follows under the thread.
struct NightFailureLine: View {
    let reason: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Night.errorText)
                .accessibilityHidden(true)
            Text(reason)
                .nightFont(.body)
                .foregroundStyle(Night.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Report response" as VoiceOver actions, one per reason, on each block
/// (the reply's right-click menu, for a student focused on a block).
struct NightReportActions: ViewModifier {
    let enabled: Bool
    let onReport: (ReportReason) -> Void

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if enabled {
                ForEach(ReportReason.allCases, id: \.self) { reason in
                    Button("Report response: \(reason.title)") { onReport(reason) }
                }
            }
        }
    }
}

/// A reply chip under the latest reply ("Explain more", "Quiz me"): a 32 pt
/// capsule of floating chrome, `calloutStrong` `ink`, with a leading symbol
/// and hover.
struct NightReplyChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .nightFont(.calloutStrong)
                .foregroundStyle(Night.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .nightChrome(in: Capsule(), interactive: true)
                .overlay { Capsule().fill(Night.lumen.opacity(hovering ? Night.Tint.hover : 0)).allowsHitTesting(false) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .nightFocusRing(Capsule())
        .accessibilityLabel(title)
    }
}
#endif

#if os(macOS)
/// The mask that fades the thread into the canvas over its last 18 pt and,
/// when `top` is above zero, over its first `top` points (under a lesson's
/// part strip).
struct NightScrollFade: View {
    var top: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if top > 0 {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: top)
            }
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
        }
    }
}

extension View {
    /// The window title steps aside (a narrow window, so the toolbar's
    /// buttons keep their room). macOS 15 and later; on macOS 14 the title
    /// stays.
    @ViewBuilder
    func nightHidesToolbarTitle(_ hides: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.toolbar(removing: hides ? .title : nil)
        } else {
            self
        }
    }

    /// macOS 26 (built with Swift 6.2+): the soft scroll-edge effect at the
    /// top, where the window's toolbar meets a scrolling reader. Earlier
    /// systems and CI builds have no edge effect to set.
    @ViewBuilder
    func nightSoftScrollEdge() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
