import SwiftUI

/// The crisis resources as links the app builds itself — never taken from
/// server or model text. US services, matching the server's `CRISIS_COPY`.
public enum CrisisResources {
    /// 988 Suicide & Crisis Lifeline, by phone.
    public static let call988 = URL(string: "tel:988")!
    /// 988 Suicide & Crisis Lifeline, by text.
    public static let text988 = URL(string: "sms:988")!
    /// Crisis Text Line: text HOME to 741741. `&body=` is the form iOS
    /// Messages reads to prefill the text.
    public static let textHomeTo741741 = URL(string: "sms:741741&body=HOME")!
    /// Emergency services.
    public static let call911 = URL(string: "tel:911")!
}

/// What a student sees when the server reads something they wrote as a
/// crisis: a warm line, the hotlines as tappable call/text links, a nudge to
/// tell a trusted adult, and one quiet way back. Deliberately no Merc, no
/// grade, no score and no retry — nothing that reads as a result.
public struct CrisisSupportView: View {
    private let closeTitle: String
    private let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let heading = "I'm really glad you told me"

    public init(closeTitle: String = "Close", onClose: @escaping () -> Void) {
        self.closeTitle = closeTitle
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            // The hotlines come right after the heading (and, at standard
            // sizes, one short line), so at the largest text sizes the first
            // one still shows without scrolling, even on an iPhone SE.
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                if !isLargeText {
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(BrandColor.accent)
                        .accessibilityHidden(true)
                }
                Text(Self.heading)
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !isLargeText {
                    Text("You deserve real support right now. These people are ready to listen, any time:")
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            #if os(macOS)
            // A Mac has no phone: tel:/sms: open FaceTime or Messages, which
            // may not be set up to call or text (or may do nothing). So the
            // numbers are the content — large, selectable, copyable — and
            // the call/text links come second.
            MacCrisisNumbers()
            #else
            VStack(spacing: BrandSpacing.sm) {
                resourceLink(
                    title: "Call 988",
                    detail: "Suicide & Crisis Lifeline · US, 24/7",
                    systemImage: "phone.fill",
                    url: CrisisResources.call988,
                    accessibilityLabel: "Call 9 8 8, the Suicide and Crisis Lifeline. US, 24/7.",
                    identifier: "crisis.call988"
                )
                resourceLink(
                    title: "Text 988",
                    detail: "Suicide & Crisis Lifeline · US, 24/7",
                    systemImage: "message.fill",
                    url: CrisisResources.text988,
                    accessibilityLabel: "Text 9 8 8, the Suicide and Crisis Lifeline. US, 24/7.",
                    identifier: "crisis.text988"
                )
                resourceLink(
                    title: "Text HOME to 741741",
                    detail: "Crisis Text Line · 24/7",
                    systemImage: "message.fill",
                    url: CrisisResources.textHomeTo741741,
                    accessibilityLabel: "Text HOME to 7 4 1 7 4 1, the Crisis Text Line. 24/7.",
                    identifier: "crisis.text741741"
                )
                resourceLink(
                    title: "Call 911",
                    detail: "If you might be in immediate danger",
                    systemImage: "phone.fill",
                    url: CrisisResources.call911,
                    accessibilityLabel: "Call 9 1 1 if you might be in immediate danger.",
                    identifier: "crisis.call911"
                )
            }
            #endif

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                if isLargeText {
                    Text("You deserve real support right now, and these people are ready to listen, any time.")
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("I'm an AI, so I can't be your support person. Please tell a trusted adult too, like a parent or school counselor.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything else can wait. Come back to it whenever you're ready.")
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BrandButton(closeTitle, style: .secondary, action: onClose)
                #if os(macOS)
                // Night Studio leaves this screen its palette only: calm,
                // unbranded, no glass, no capsule (SPEC.md §5.9).
                .environment(\.brandButtonClassic, true)
                #endif
                .accessibilityIdentifier("crisis.close")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // The screen just replaced what the student was doing; say so.
            AccessibilityNotification.Announcement(Self.heading).post()
        }
    }

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    private func resourceLink(
        title: String,
        detail: String,
        systemImage: String,
        url: URL,
        accessibilityLabel: String,
        identifier: String
    ) -> some View {
        Link(destination: url) {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                // At accessibility sizes the title already says call or
                // text; the icon column would only squeeze the words.
                if !isLargeText {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandColor.accent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(title)
                        .font(BrandFont.bodyEmphasized)
                        .foregroundStyle(BrandColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(BrandColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                    .stroke(BrandColor.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The digits spelled out so VoiceOver reads "nine eight eight", not
        // "nine hundred eighty-eight".
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }
}

#if os(macOS)
/// The crisis lines on a Mac, in one card: each number large and selectable,
/// with a Copy button, and the call/text links (FaceTime, Messages) under
/// it; the card ends with the note on when those links work. Used by
/// `CrisisSupportView` and the Mac Help window. The links and numbers are
/// the app's own (`CrisisResources`), never server or model text.
public struct MacCrisisNumbers: View {
    @State private var copied: String?

    public init() {}

    /// One crisis line as the Mac shows it.
    struct Line: Identifiable {
        let id: String
        /// What goes before the number ("Text HOME to"), if anything.
        let lead: String?
        /// The number, as shown and as copied.
        let number: String
        let detail: String
        /// VoiceOver: the digits spelled out ("9 8 8").
        let spoken: String
        let call: URL?
        let text: URL?
    }

    static let lines: [Line] = [
        Line(id: "988", lead: "Call or text", number: "988",
             detail: "Suicide & Crisis Lifeline · US, 24/7",
             spoken: "Call or text 9 8 8, the Suicide and Crisis Lifeline. US, 24/7.",
             call: CrisisResources.call988, text: CrisisResources.text988),
        Line(id: "741741", lead: "Text HOME to", number: "741741",
             detail: "Crisis Text Line · 24/7",
             spoken: "Text HOME to 7 4 1 7 4 1, the Crisis Text Line. 24/7.",
             call: nil, text: CrisisResources.textHomeTo741741),
        Line(id: "911", lead: "Call", number: "911",
             detail: "If you might be in immediate danger",
             spoken: "Call 9 1 1 if you might be in immediate danger.",
             call: CrisisResources.call911, text: nil),
    ]

    /// The caveat for the FaceTime / Messages buttons, inside the card,
    /// under the buttons it qualifies.
    static let linksNote = "Use your phone, or the buttons if this Mac is set up to call (FaceTime) or text (Messages)."

    public var body: some View {
        // One card: the three lines, then the note about the buttons. Every
        // word in it is body size (15 pt on the Mac) or larger — the 10 pt
        // footnote was the Mac's smallest text, on the screen that matters
        // most.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Divider().overlay(BrandColor.border)
                }
                row(line)
            }
            Divider().overlay(BrandColor.border)
            Label {
                Text(Self.linksNote)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
            }
            .font(BrandFont.body)
            .foregroundStyle(BrandColor.textSecondary)
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrandColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                .stroke(BrandColor.border, lineWidth: 1)
        )
    }

    private func row(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    if let lead = line.lead {
                        Text(lead)
                            .font(BrandFont.bodyEmphasized)
                            .foregroundStyle(BrandColor.text)
                    }
                    // Selectable, so it can be read off, selected and
                    // copied however the student likes.
                    Text(line.number)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BrandColor.text)
                        .textSelection(.enabled)
                    Text(line.detail)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.spoken)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("crisis.number\(line.id)")
                Spacer(minLength: BrandSpacing.sm)
                Button {
                    MacPasteboard.copy(line.number)
                    copied = line.id
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        if copied == line.id { copied = nil }
                    }
                } label: {
                    Label(copied == line.id ? "Copied" : "Copy",
                          systemImage: copied == line.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy \(line.number)")
                .accessibilityLabel("Copy \(line.number)")
                .accessibilityIdentifier("crisis.copy\(line.id)")
            }
            HStack(spacing: BrandSpacing.lg) {
                if let call = line.call {
                    Link(destination: call) {
                        Label("Call with FaceTime", systemImage: "phone.fill")
                    }
                    .accessibilityLabel("Call \(line.number) with FaceTime")
                }
                if let text = line.text {
                    Link(destination: text) {
                        Label("Text with Messages", systemImage: "message.fill")
                    }
                    .accessibilityLabel("Text \(line.id == "741741" ? "HOME to 741741" : line.number) with Messages")
                }
            }
            .font(BrandFont.bodyEmphasized)
            .foregroundStyle(BrandColor.accentText)
            .macPointingHand()
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
#endif

#Preview("Crisis support") {
    ScrollView {
        CrisisSupportView(onClose: {})
            .padding(BrandSpacing.lg)
    }
    .background(BrandColor.background)
}
