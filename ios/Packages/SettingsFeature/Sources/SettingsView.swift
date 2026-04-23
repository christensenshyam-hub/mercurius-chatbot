import SwiftUI
import DesignSystem

/// Settings screen. Presented as a sheet from the chat header.
///
/// Sections:
/// - Appearance — theme preference
/// - Session — session id preview + "Start Over" reset
/// - About — version, credits, website
public struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var showResetConfirm = false

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
                sessionSection
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
                }
            }
            .task { model.loadSessionId() }
            .alert(
                "Start over?",
                isPresented: $showResetConfirm
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Start Over", role: .destructive) {
                    Task { await model.resetSession() }
                }
            } message: {
                Text("This clears your session ID and your chat history on this device. Your streak, leaderboard rank, and chat memory on the server won't be deleted, but future activity won't be associated with them.")
            }
            .alert(
                "Couldn't reset",
                isPresented: Binding(
                    get: { model.resetErrorMessage != nil },
                    set: { if !$0 { model.clearResetError() } }
                )
            ) {
                Button("OK", role: .cancel) { model.clearResetError() }
            } message: {
                Text(model.resetErrorMessage ?? "")
            }
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

    @ViewBuilder
    private var sessionSection: some View {
        Section {
            HStack {
                Text("Session ID")
                Spacer()
                Text(model.sessionId.isEmpty ? "—" : "\(model.sessionId.prefix(8))…")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(BrandColor.textSecondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Session identifier: \(model.sessionId)")
            }

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                HStack {
                    Text("Start Over")
                    Spacer()
                    if model.isResetInProgress {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(model.isResetInProgress)
        } header: {
            Text("Session")
        } footer: {
            Text("Resets the identifier Mercurius uses for this device. Useful if you're handing your phone to someone else to try.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledRow(title: "Version", value: "\(model.appVersion) (\(model.buildNumber))")
            LabeledRow(title: "Built by", value: "Mayo AI Literacy Club")

            Link(destination: URL(string: "https://mayoailiteracy.com")!) {
                HStack {
                    Text("mayoailiteracy.com")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(BrandColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Open mayoailiteracy.com in Safari")

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
