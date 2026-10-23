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

#Preview("Crisis support") {
    ScrollView {
        CrisisSupportView(onClose: {})
            .padding(BrandSpacing.lg)
    }
    .background(BrandColor.background)
}
