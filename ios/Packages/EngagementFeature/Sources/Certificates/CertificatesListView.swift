import SwiftUI
import DesignSystem

/// Certificates: one row per certificate this build offers, earned or not,
/// with what's left. An earned one opens its sheet (`CertificateSheet`).
/// Pushed from the Progress hub's Certificates row, on iPhone and Mac.
public struct CertificatesListView: View {
    private let center: CertificateCenter
    @State private var open: CertificateKind?

    public init(center: CertificateCenter) {
        self.center = center
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                ForEach(center.kinds) { kind in
                    if let status = center.status(kind) {
                        CertificateRow(status: status, name: center.store.name ?? "",
                                       date: status.isEarned ? center.store.completionDate(kind) ?? status.lastMetAt : nil,
                                       onOpen: { open = kind })
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                    Text(CertificatesListCopy.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .accessibilityElement(children: .combine)
            }
            .padding(BrandSpacing.lg)
        }
        .background(BrandColor.background.ignoresSafeArea())
        .navigationTitle("Certificates")
        .sheet(item: $open) { kind in
            CertificateSheet(center: center, kind: kind, onClose: { open = nil })
        }
    }
}

/// One certificate in the list: a small picture of it, its course, and
/// either "Earned …" with its button or how far along the learner is and
/// what's left.
struct CertificateRow: View {
    let status: CertificateStatus
    let name: String
    let date: Date?
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // The thumbnail beside the words, or above them at the largest
            // text sizes.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: BrandSpacing.md))
                : AnyLayout(HStackLayout(alignment: .top, spacing: BrandSpacing.md))
            layout {
                thumbnail
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text(status.kind.courseName)
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                        .accessibilityAddTraits(.isHeader)
                    if status.isEarned {
                        Label(earnedLine, systemImage: "checkmark.seal.fill")
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.successText)
                    } else {
                        Text(status.progressText)
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.text)
                        if let remaining = status.remainingText {
                            Text(remaining)
                                .font(BrandFont.caption)
                                .foregroundStyle(BrandColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if status.isEarned {
                BrandButton(CertificatesListCopy.open, style: .primary, action: onOpen)
                    .accessibilityHint("Add your name, then print or save it")
            }
        }
        .padding(BrandSpacing.md)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
            .strokeBorder(BrandColor.border, lineWidth: 1))
    }

    private var earnedLine: String {
        guard let date else { return "Earned" }
        return "Earned \(CertificateCopy.dateText(date))"
    }

    private var thumbnail: some View {
        CertificatePreview(kind: status.kind, name: status.isEarned ? name : "", date: date, shadow: false)
            .frame(width: 128)
            .opacity(status.isEarned ? 1 : 0.45)
            .overlay {
                if !status.isEarned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BrandColor.textSecondary)
                        .padding(8)
                        .background(BrandColor.surface, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The Progress hub's row into the list: "Certificates", and a line on
/// where things stand.
public struct CertificatesHubRow: View {
    private let center: CertificateCenter

    public init(center: CertificateCenter) {
        self.center = center
    }

    public var body: some View {
        NavigationLink {
            CertificatesListView(center: center)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: "rosette")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(BrandColor.accentText)
                    .frame(width: 40, height: 40)
                    .background(BrandColor.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Certificates")
                        .font(BrandFont.subheading)
                        .foregroundStyle(BrandColor.text)
                    Text(CertificatesListCopy.summary(center.kinds.compactMap { center.status($0) }))
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.certificates")
    }
}

public enum CertificatesListCopy {
    public static let open = "Get Your Certificate"
    public static let footnote = "Your name stays on this device. It\u{2019}s never sent to Mercurius\u{2019}s servers."

    /// The hub row's second line: "1 earned · 1 in progress", or what earns
    /// the first one.
    public static func summary(_ statuses: [CertificateStatus]) -> String {
        let earned = statuses.filter(\.isEarned).count
        let open = statuses.count - earned
        switch (earned, open) {
        case (0, _):
            if statuses.count == 1, let only = statuses.first {
                return only.kind == .deepDive ? "Pass all eight unit checks to earn yours" : "Finish every lesson to earn yours"
            }
            return "Finish a course to earn one"
        case (_, 0):
            return earned == 1 ? "1 earned" : "\(earned) earned"
        default:
            return "\(earned) earned · \(open) in progress"
        }
    }
}
