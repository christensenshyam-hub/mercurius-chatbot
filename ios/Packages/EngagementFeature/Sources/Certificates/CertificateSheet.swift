import SwiftUI
import DesignSystem
#if os(macOS)
import AppKit
#endif

/// "Your certificate": the learner types their name as it should appear,
/// watches the certificate take it, then prints it or saves / shares the
/// PDF. The name is kept on this device only (`CertificateStore`), and the
/// sheet says so.
///
/// iPhone: a navigation sheet with Print (the system print sheet) and
/// Share or Save as PDF (the share sheet). Mac (Night Studio's sheet):
/// Close (Esc), Save as PDF… (⌘S, the save panel) and Print… (Return or ⌘P,
/// the print panel).
public struct CertificateSheet: View {
    private let center: CertificateCenter
    private let kind: CertificateKind
    private let onClose: () -> Void

    @State private var name: String
    @State private var date: Date?
    @State private var problem: String?
    #if os(macOS)
    @FocusState private var nameFocused: Bool
    #else
    @Environment(\.dynamicTypeSize) private var typeSize
    #endif

    public init(center: CertificateCenter, kind: CertificateKind, onClose: @escaping () -> Void) {
        self.center = center
        self.kind = kind
        self.onClose = onClose
        _name = State(initialValue: center.store.name ?? "")
    }

    /// The name as it prints.
    private var printedName: String { CertificateNameFit.normalized(name) }

    private var document: CertificateDocument? {
        guard !printedName.isEmpty, let date else { return nil }
        return CertificateDocument(kind: kind, name: printedName, date: date)
    }

    public var body: some View {
        content
            .onAppear {
                // The certificate is made now: its date is fixed from here on.
                date = center.completionDate(kind)
                if center.justEarned == kind { center.justEarned = nil }
            }
            .onChange(of: name) { _, newValue in
                if newValue.count > CertificateNameFit.maxLength {
                    name = String(newValue.prefix(CertificateNameFit.maxLength))
                    return
                }
                center.store.setName(newValue)
            }
            .onDisappear { CertificateDocument.removeTemporaryFiles() }
    }

    // MARK: - iPhone

    #if os(iOS)
    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.xl) {
                    CertificatePreview(kind: kind, name: printedName, date: date)
                        .padding(.top, BrandSpacing.xs)

                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        Text(CertificateSheetCopy.nameLabel)
                            .font(BrandFont.bodyEmphasized)
                            .foregroundStyle(BrandColor.text)
                            .accessibilityHidden(true)
                        // At the accessibility sizes a long name wraps in the
                        // field instead of being cut off.
                        TextField(CertificateSheetCopy.namePrompt, text: $name,
                                  axis: typeSize.isAccessibilitySize ? .vertical : .horizontal)
                            .lineLimit(1...4)
                            .font(BrandFont.body)
                            .foregroundStyle(BrandColor.text)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.sm)
                            .frame(minHeight: 48)
                            .background(BrandColor.surface,
                                        in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                                .strokeBorder(BrandColor.border, lineWidth: 1))
                            .accessibilityLabel(CertificateSheetCopy.nameLabel)
                            .accessibilityIdentifier("certificate.name")
                        privacyNote
                    }

                    VStack(spacing: BrandSpacing.sm) {
                        BrandButton(CertificateSheetCopy.print, style: .primary, isEnabled: document != nil) {
                            guard let document else { return }
                            if !CertificatePrinting.print(document) { problem = CertificateSheetCopy.couldNotMake }
                        }
                        .accessibilityHint("Opens the print options for your certificate")
                        shareButton
                        if let problem {
                            Text(problem)
                                .font(BrandFont.caption)
                                .foregroundStyle(BrandColor.errorText)
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.lg)
                .padding(.vertical, BrandSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(BrandColor.background.ignoresSafeArea())
            .navigationTitle(CertificateSheetCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .font(BrandFont.bodyEmphasized)
                }
            }
        }
        .tint(BrandColor.accentText)
    }

    private var privacyNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: BrandSpacing.xs) {
            Image(systemName: "lock.fill")
                .accessibilityHidden(true)
            Text(CertificateSheetCopy.privacy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(BrandFont.caption)
        .foregroundStyle(BrandColor.textSecondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var shareButton: some View {
        let label = Label(CertificateSheetCopy.share, systemImage: "square.and.arrow.up")
            .font(BrandFont.bodyEmphasized)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, BrandSpacing.lg)
            .foregroundStyle(BrandColor.text)
            .background(
                BrandColor.surfaceElevated
                    .overlay(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous)
                        .strokeBorder(BrandColor.border, lineWidth: 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        if let document {
            ShareLink(item: document,
                      preview: SharePreview(kind.fileName, image: Image(systemName: "doc.richtext"))) {
                label
            }
            .accessibilityHint("Shares the certificate as a PDF, or saves it to Files")
        } else {
            label
                .opacity(0.5)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Type your name first")
        }
    }
    #endif

    // MARK: - Mac

    #if os(macOS)
    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        NightEyebrow(kind.courseName, systemImage: "rosette")
                        Text(CertificateSheetCopy.title)
                            .nightFont(.display)
                            .foregroundStyle(Night.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    CertificatePreview(kind: kind, name: printedName, date: date)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(CertificateSheetCopy.nameLabel)
                            .nightFont(.headline)
                            .foregroundStyle(Night.ink)
                            .accessibilityHidden(true)
                        TextField("", text: $name,
                                  prompt: Text(CertificateSheetCopy.namePrompt).foregroundStyle(Night.ink3))
                            .textFieldStyle(.plain)
                            .nightFont(.body)
                            .foregroundStyle(Night.ink)
                            // Return in the field is the sheet's default
                            // button: Print….
                            .focused($nameFocused)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(Night.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(nameFocused ? Night.focusRing : Night.fieldStroke,
                                              lineWidth: nameFocused ? 2 : 1))
                            .accessibilityLabel(CertificateSheetCopy.nameLabel)
                            .accessibilityIdentifier("certificate.name")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                            Text(CertificateSheetCopy.privacy)
                                .nightFont(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Night.ink2)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: 12) {
                if let problem {
                    Text(problem)
                        .nightFont(.caption)
                        .foregroundStyle(Night.errorText)
                }
                Spacer(minLength: 0)
                NightTextButton("Close", color: Night.ink2, action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .help("Close (Esc)")
                NightSecondaryButton(CertificateSheetCopy.save, systemImage: "arrow.down.doc", action: saveCertificate)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(document == nil)
                    .help("Save the certificate as a PDF (⌘S)")
                NightPrimaryButton(CertificateSheetCopy.printMac, systemImage: "printer", action: printCertificate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(document == nil)
                    .help("Print the certificate (Return or ⌘P)")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            // ⌘P as well as Return: a second, unseen button for the shortcut.
            .background {
                Button("Print", action: printCertificate)
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(document == nil)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .background(NightCanvas(pools: .indigo, stars: false))
        .frame(minWidth: 600, idealWidth: 640, minHeight: 700, idealHeight: 720)
        .onAppear {
            // Straight to the field when there's no name yet.
            if printedName.isEmpty { nameFocused = true }
        }
    }

    private func printCertificate() {
        guard let document else { return }
        problem = CertificatePrinting.print(document, in: NSApp.keyWindow) ? nil : CertificateSheetCopy.couldNotMake
    }

    private func saveCertificate() {
        guard let document else { return }
        CertificatePrinting.save(document, in: NSApp.keyWindow)
    }
    #endif
}

/// The sheet's words, in one place for the tests.
public enum CertificateSheetCopy {
    public static let title = "Your Certificate"
    public static let nameLabel = "Your name, as it should appear"
    public static let namePrompt = "Your name"
    public static let privacy = "Your name stays on this device. It\u{2019}s never sent to Mercurius\u{2019}s servers."
    public static let print = "Print"
    public static let printMac = "Print\u{2026}"
    public static let save = "Save as PDF\u{2026}"
    public static let share = "Share or Save as PDF"
    public static let couldNotMake = "The certificate couldn\u{2019}t be made. Try again."
}
