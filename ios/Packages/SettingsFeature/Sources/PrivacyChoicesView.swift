import SwiftUI
import DesignSystem

/// Pushed from Settings. A plain-language version of the disclosure the
/// student agreed to at first launch, plus the way to take that agreement
/// back. Withdrawing consent is the full deletion (server + device) followed
/// by the host re-showing the agreement, so nothing is sent until they
/// agree again.
struct PrivacyChoicesView: View {
    let model: SettingsViewModel

    @State private var showWithdrawConfirm = false
    @State private var withdrawFailure: String?
    @State private var resetFailure: String?

    var body: some View {
        Form {
            disclosureSection
            withdrawSection
        }
        .scrollContentBackground(.hidden)
        .background(BrandColor.background)
        .navigationTitle("Privacy choices")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Popping back mid-erasure would reach the Settings Done button's
        // sibling paths; keep the user here until the server has answered.
        .navigationBarBackButtonHidden(model.isDeleteInProgress)
#endif
        .alert(
            "Withdraw consent?",
            isPresented: $showWithdrawConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Withdraw", role: .destructive, action: withdraw)
        } message: {
            Text("This erases your chats, lessons, streak and progress on this device and on our server, gives you a new anonymous ID, and shows the agreement again before you can chat. This can't be undone.")
        }
        .modifier(DeleteFailureAlert(
            message: $withdrawFailure,
            retry: withdraw,
            resetDeviceOnly: withdrawLocally
        ))
        .modifier(ResetFailureAlert(message: $resetFailure))
    }

    // MARK: - Actions

    private func withdraw() {
        Task {
            let ok = await model.withdrawConsent()
            if !ok {
                withdrawFailure = model.deleteErrorMessage
                model.clearDeleteError()
            }
        }
    }

    private func withdrawLocally() {
        Task {
            let ok = await model.withdrawConsentLocally()
            if !ok {
                resetFailure = model.resetErrorMessage
                model.clearResetError()
            }
        }
    }

    // MARK: - Sections

    private var disclosureSection: some View {
        Section {
            DisclosureRow(
                title: "Where your messages go",
                text: "Your messages, and any photos you attach, are sent through our server to Anthropic's Claude, which writes Merc's replies. Your chats are stored on our server under your anonymous ID."
            )
            DisclosureRow(
                title: "No accounts",
                text: "There's no sign-up. This device holds a random ID, and that ID is the only thing linking you to your chats — no name or email. The age you pick during setup isn't saved."
            )
            DisclosureRow(
                title: "You can delete everything",
                text: "Deleting your data from Settings, or withdrawing consent below, erases your chats and progress on this device and on our server and gives you a new ID."
            )
            if let privacy = URL(string: "https://trymercurius.com/privacy") {
                Link("Read the full privacy policy", destination: privacy)
                    .foregroundStyle(BrandColor.accent)
            }
        } header: {
            Text("How Mercurius uses your data")
        }
    }

    private var withdrawSection: some View {
        Section {
            Button(role: .destructive) {
                showWithdrawConfirm = true
            } label: {
                HStack {
                    Text("Withdraw consent")
                    Spacer()
                    if model.isDeleteInProgress || model.isResetInProgress {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(model.isDeleteInProgress || model.isResetInProgress)
            .accessibilityIdentifier("settings.withdrawConsent")
        } footer: {
            Text("Deletes your data on this device and on our server, gives you a new anonymous ID, and shows the agreement again before you can chat.")
        }
    }
}

// MARK: - Small helpers

private struct DisclosureRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
            Text(text)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
