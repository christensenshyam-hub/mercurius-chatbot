import SwiftUI
import DesignSystem
import NetworkingKit
#if canImport(UIKit)
import UIKit
#endif

/// Settings screen. Presented as a sheet from the chat header.
///
/// Sections:
/// - Appearance — theme preference
/// - Session — full, copyable session id + "Delete my data & start over"
/// - Privacy — pushes `PrivacyChoicesView` (disclosure + withdraw consent)
/// - About — version, policy / support links
public struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var showDeleteConfirm = false
    @State private var showCopied = false
    // Alerts are driven by view-local copies of the model's error text so a
    // pushed `PrivacyChoicesView` can show its own alert without this
    // screen's alert competing for the same presentation.
    @State private var deleteFailure: String?
    @State private var resetFailure: String?

    private let dismissAction: () -> Void

    public init(
        model: SettingsViewModel,
        dismissAction: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.dismissAction = dismissAction
    }

    public var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                // Standby gamification toggle — only shown when the client flag
                // is on, so the default Settings screen is unchanged.
                if GamificationFlag.clientEnabled {
                    nudgesSection
                }
                sessionSection
                privacySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(BrandColor.background)
            .navigationTitle("Settings")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismissAction)
                        .fontWeight(.semibold)
                        .foregroundStyle(BrandColor.accent)
                        // Leaving mid-erasure would let a send start under the
                        // OLD id: the server re-creates rows the user was told
                        // were gone, and the message vanishes at the local reset.
                        .disabled(model.isDeleteInProgress || model.isResetInProgress)
                }
            }
#if os(iOS)
            .interactiveDismissDisabled(model.isDeleteInProgress || model.isResetInProgress)
#endif
            .task { model.loadSessionId() }
            .alert(
                "Delete my data?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: deleteData)
            } message: {
                Text("This erases your chats, lessons, streak and progress on this device and on our server, and gives you a new anonymous ID. This can't be undone.")
            }
            .modifier(DeleteFailureAlert(
                message: $deleteFailure,
                retry: deleteData,
                resetDeviceOnly: resetDeviceOnly
            ))
            .modifier(ResetFailureAlert(message: $resetFailure))
        }
    }

    // MARK: - Actions

    private func deleteData() {
        Task {
            let ok = await model.deleteServerDataAndStartOver()
            if !ok {
                deleteFailure = model.deleteErrorMessage
                model.clearDeleteError()
            }
        }
    }

    private func resetDeviceOnly() {
        Task {
            let ok = await model.resetSession()
            if !ok {
                resetFailure = model.resetErrorMessage
                model.clearResetError()
            }
        }
    }

    private func copySessionId() {
        guard model.canCopySessionId else { return }
#if canImport(UIKit)
        UIPasteboard.general.string = model.sessionId
#endif
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $model.theme) {
                ForEach(ThemePreference.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var nudgesSection: some View {
        Section {
            Toggle("Show progress nudges", isOn: $model.nudgesEnabled)
                .tint(BrandColor.accent)
        } header: {
            Text("Progress")
        } footer: {
            Text("Brief, factual credit when you make a good reasoning move — asking a sharper question, revising your view, catching your own mistake. Turn this off for a quieter experience; your progress still counts.")
        }
    }

    @ViewBuilder
    private var sessionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack {
                    Text("Session ID")
                    Spacer()
                    Button(action: copySessionId) {
                        Label(
                            showCopied ? "Copied" : "Copy",
                            systemImage: showCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(BrandFont.caption)
                    }
                    .buttonStyle(.borderless)
                    .tint(BrandColor.accent)
                    .disabled(!model.canCopySessionId)
                    .accessibilityLabel("Copy session ID")
                }
                Text(model.sessionId.isEmpty ? "—" : model.sessionId)
                    .font(BrandFont.mono)
                    .foregroundStyle(BrandColor.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Session identifier: \(model.sessionId)")
            }
            .padding(.vertical, BrandSpacing.xxs)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Text("Delete my data & start over")
                    Spacer()
                    if model.isDeleteInProgress {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(model.isDeleteInProgress || model.isResetInProgress)
            .accessibilityIdentifier("settings.deleteData")
        } header: {
            Text("Session")
        } footer: {
            Text("Deleting your data erases your chats, lessons, streak and progress on this device and on our server right away, and gives you a new anonymous ID. Your session ID is the only thing that links this device to your data — copy it if you ever need to contact us about it.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyChoicesView(model: model)
            } label: {
                Text("Privacy choices")
            }
            .accessibilityIdentifier("settings.privacyChoices")
        } header: {
            Text("Privacy")
        } footer: {
            Text("Where your messages go, and how to withdraw consent.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledRow(title: "Version", value: "\(model.appVersion) (\(model.buildNumber))")

            if let faq = URL(string: "https://trymercurius.com/support") {
                Link("Help & FAQ", destination: faq)
                    .foregroundStyle(BrandColor.accent)
            }
            if let support = URL(string: "mailto:support@trymercurius.com") {
                Link("Contact support", destination: support)
                    .foregroundStyle(BrandColor.accent)
            }
            if let terms = URL(string: "https://trymercurius.com/terms") {
                Link("Terms of Use", destination: terms)
                    .foregroundStyle(BrandColor.accent)
            }
            if let privacy = URL(string: "https://trymercurius.com/privacy") {
                Link("Privacy Policy", destination: privacy)
                    .foregroundStyle(BrandColor.accent)
            }

            Text("Mercurius AI is an AI literacy tutor — built to help you think critically about AI, not think for you.")
                .font(.footnote)
                .foregroundStyle(BrandColor.textSecondary)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Small helpers

private struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
