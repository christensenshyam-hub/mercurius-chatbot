import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

/// Alert shown when "Delete my data" / "Withdraw consent" couldn't complete.
/// Offers a retry (the server endpoint is idempotent, so retrying is safe)
/// and the local-only fallback. Shared by `SettingsView` and
/// `PrivacyChoicesView`; each owns its own `message` state so only the
/// visible screen presents.
///
/// The fallback doesn't reset straight away (AUD-54): resetting drops the ID
/// that is the only key to the student's server data. It first opens
/// `DeviceOnlyResetSheet`, which says so and shows that ID with a Copy
/// button.
struct DeleteFailureAlert: ViewModifier {
    @Binding var message: String?
    let retry: () -> Void
    /// Reads the ID the data sits under, for the confirmation sheet.
    let notice: () -> DeviceOnlyResetNotice
    let resetDeviceOnly: () -> Void

    @State private var confirming: DeviceOnlyResetNotice?

    func body(content: Content) -> some View {
        content
            .alert(
                "Couldn't delete your data",
                isPresented: Binding(
                    get: { message != nil },
                    set: { if !$0 { message = nil } }
                )
            ) {
                Button("Try again", action: retry)
                Button("Reset this device only…") { confirming = notice() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(message ?? "")
            }
            .sheet(item: $confirming) { notice in
                DeviceOnlyResetSheet(
                    notice: notice,
                    onReset: {
                        confirming = nil
                        resetDeviceOnly()
                    },
                    onCancel: { confirming = nil }
                )
            }
    }
}

/// The last step before a device-only reset: what it leaves behind, the ID
/// to quote to privacy@, a Copy button, then the reset itself.
struct DeviceOnlyResetSheet: View {
    let notice: DeviceOnlyResetNotice
    let onReset: () -> Void
    let onCancel: () -> Void

    @State private var copied = false

    /// Long enough to paste the ID into an email or a note after the reset;
    /// still local to this device (never Universal Clipboard).
    static let pasteboardLifetime: TimeInterval = 10 * 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    Text(notice.message)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let id = notice.sessionId {
                        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                            Text(id)
                                .font(BrandFont.mono)
                                .foregroundStyle(BrandColor.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Session ID: \(id)")

                            Button(action: { copy(id) }) {
                                Label(copied ? "Copied" : "Copy ID",
                                      systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .font(BrandFont.bodyEmphasized)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(BrandColor.accentText)
                            .accessibilityIdentifier("settings.deviceReset.copyId")
                        }
                        .padding(BrandSpacing.md)
                        .background(BrandColor.surface,
                                    in: RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous))
                    }

                    Button(role: .destructive, action: onReset) {
                        Text("Reset this device only")
                            .font(BrandFont.bodyEmphasized)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    // Bordered, so the label is red text (`errorText`, AA in
                    // both themes) rather than white on a light red fill.
                    .buttonStyle(.bordered)
                    .tint(BrandColor.errorText)
                    .accessibilityIdentifier("settings.deviceReset.confirm")
                }
                .padding(BrandSpacing.xl)
            }
            .background(BrandColor.background)
            .navigationTitle(notice.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(BrandColor.accentText)
                }
            }
        }
    }

    private func copy(_ id: String) {
#if canImport(UIKit)
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: id]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(Self.pasteboardLifetime)]
        )
#elseif os(macOS)
        // The same care on the Mac: off Universal Clipboard, hidden from
        // clipboard history, wiped again after the same lifetime.
        MacPasteboard.copy(id, currentHostOnly: true, concealed: true, clearAfter: Self.pasteboardLifetime)
#endif
        copied = true
    }
}

/// Alert for the local-only reset failing (Keychain error). Nothing to
/// retry against a server here, so a single dismiss button.
struct ResetFailureAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't reset",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "")
        }
    }
}
