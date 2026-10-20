#if os(macOS)
import SwiftUI
import DesignSystem
import NetworkingKit

/// The Mac's Settings window (Mercurius ▸ Settings…, ⌘,): the iPhone's
/// Settings screen as three Mac tabs, on the same `SettingsViewModel`, so
/// every reset, erasure and withdrawal runs exactly the iPhone's code.
///
/// - General: appearance (and the progress nudges, while that flag is on).
/// - Privacy: the session ID with Copy, Delete my data & start over, and
///   Privacy choices (the disclosure and withdrawing consent).
/// - About: the version, How Mercurius teaches, Help & FAQ, Send feedback,
///   support, terms and the privacy policy.
public struct MacSettingsWindowView: View {
    @State private var model: SettingsViewModel
    private let onShowHowItTeaches: () -> Void

    @State private var showDeleteConfirm = false
    @State private var showPrivacyChoices = false
    @State private var showCopied = false
    @State private var deleteFailure: String?
    @State private var resetFailure: String?

    public init(
        model: SettingsViewModel,
        onShowHowItTeaches: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onShowHowItTeaches = onShowHowItTeaches
    }

    /// The tabs, for the window's own state and the snapshot harness.
    public enum Tab: String, CaseIterable, Hashable {
        case general, privacy, about
    }

    @SceneStorage("settings.tab") private var tab: Tab = .general

    public var body: some View {
        TabView(selection: $tab) {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            privacy
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(Tab.privacy)
            about
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 540)
        // Night's prominent indigo for the radio buttons, toggles and the
        // default button (white on it is 7.9:1).
        .tint(Night.prominent)
        .task { model.loadSessionId() }
        .onAppear(perform: applyDebugTab)
        .alert("Delete my data?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: deleteData)
        } message: {
            Text("This erases your chats, lessons, streak and progress on this Mac and on our server, and gives you a new anonymous ID. This can't be undone.")
        }
        .modifier(DeleteFailureAlert(
            message: $deleteFailure,
            retry: deleteData,
            notice: { model.deviceOnlyResetNotice() },
            resetDeviceOnly: resetDeviceOnly
        ))
        .modifier(ResetFailureAlert(message: $resetFailure))
        .sheet(isPresented: $showPrivacyChoices) {
            NavigationStack {
                PrivacyChoicesView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPrivacyChoices = false }
                                .disabled(isBusy)
                        }
                    }
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 600)
            .tint(Night.prominent)
        }
    }

    private var isBusy: Bool { model.isDeleteInProgress || model.isResetInProgress }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                Picker("Appearance", selection: $model.theme) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("System follows your Mac's Light or Dark appearance.")
                    .foregroundStyle(Night.ink3)
            }
            if GamificationFlag.clientEnabled {
                Section {
                    Toggle("Show progress nudges", isOn: $model.nudgesEnabled)
                } footer: {
                    Text("Brief, factual credit when you make a good reasoning move. Your progress counts either way.")
                        .foregroundStyle(Night.ink3)
                }
            }
        }
        .formStyle(.grouped)
        .nightSettingsPane()
        .frame(height: GamificationFlag.clientEnabled ? 300 : 200)
    }

    // MARK: - Privacy

    private var privacy: some View {
        Form {
            Section {
                LabeledContent("Session ID") {
                    HStack(spacing: BrandSpacing.sm) {
                        Text(model.sessionId.isEmpty ? "—" : model.sessionId)
                            .font(BrandFont.mono)
                            .foregroundStyle(Night.ink3)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("Session identifier: \(model.sessionId)")
                        Button {
                            copySessionId()
                        } label: {
                            Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        }
                        .disabled(!model.canCopySessionId)
                        .accessibilityLabel("Copy session ID")
                    }
                }
                HStack {
                    Button("Delete My Data & Start Over…", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .foregroundStyle(BrandColor.errorText)
                    .disabled(isBusy)
                    .accessibilityIdentifier("settings.deleteData")
                    if model.isDeleteInProgress {
                        ProgressView().controlSize(.small)
                    }
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Deleting your data erases your chats, lessons, streak and progress on this Mac and on our server right away, and gives you a new anonymous ID. Your session ID is the only thing that links this Mac to your data — copy it if you ever need to contact us about it.")
                    .foregroundStyle(Night.ink3)
            }

            Section {
                Button("Privacy Choices…") { showPrivacyChoices = true }
                    .disabled(isBusy)
                    .accessibilityIdentifier("settings.privacyChoices")
            } footer: {
                Text("Where your messages go, and how to withdraw consent.")
                    .foregroundStyle(Night.ink3)
            }
        }
        .formStyle(.grouped)
        .nightSettingsPane()
        .frame(height: 380)
    }

    // MARK: - About

    private var about: some View {
        Form {
            Section {
                LabeledContent("Version", value: "\(model.appVersion) (\(model.buildNumber))")
                Button("How Mercurius Teaches…", action: onShowHowItTeaches)
                    .accessibilityIdentifier("settings.howItTeaches")
            } footer: {
                Text("Mercurius AI is an AI literacy tutor — built to help you think critically about AI, not think for you.")
                    .foregroundStyle(Night.ink3)
            }
            Section("Help") {
                link("Help & FAQ", "https://trymercurius.com/support")
                link("Send Feedback", "https://trymercurius.com/feedback")
                    .accessibilityIdentifier("settings.sendFeedback")
                link("Contact Support", "mailto:support@trymercurius.com")
            }
            Section("Legal") {
                link("Terms of Use", "https://trymercurius.com/terms")
                link("Privacy Policy", "https://trymercurius.com/privacy")
            }
        }
        .formStyle(.grouped)
        .nightSettingsPane()
        .frame(height: 520)
    }

    @ViewBuilder
    private func link(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(Night.ink3)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(BrandColor.accentText)
            .macPointingHand()
        }
    }

    // MARK: - Actions (the iPhone's, on the same model)

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
        // The ID is the only key to this student's server data: off
        // Universal Clipboard, out of clipboard history, gone in two minutes.
        MacPasteboard.copy(model.sessionId, currentHostOnly: true, concealed: true, clearAfter: 120)
        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }

    /// DEBUG `-MacSettingsTab general|privacy|about`, for screenshots.
    private func applyDebugTab() {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "MacSettingsTab"), let debugTab = Tab(rawValue: raw) {
            tab = debugTab
        }
        #endif
    }
}

private extension View {
    /// A Settings pane in Night Studio (SPEC.md §5.8, D10): still the Mac's
    /// own grouped form, system type and controls, on Night's flat canvas
    /// instead of the window's grey. Footers use `ink3` (≥ 4.5:1 on it,
    /// where the system's secondary label is about 4:1).
    func nightSettingsPane() -> some View {
        scrollContentBackground(.hidden)
            .background(NightCanvas(pools: .flat, stars: false))
    }
}
#endif
