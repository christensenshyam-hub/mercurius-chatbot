import SwiftUI
import DesignSystem
import PersistenceKit

/// Reminder controls for the Progress hub and onboarding: the weekly nudges
/// and the daily streak reminder (+ its time). Each switch turns on only its
/// own reminder, through `ReminderEnabler`, which asks for notification
/// permission on enable.
///
/// `plain` is the first-run "Your path" form (review 2026-10-22): one switch
/// in plain words for the weekly nudges, "Remind me to practice", and no
/// streak switch, since it sits next to the Basics choice and Basics has no
/// streak. The daily streak reminder stays in the Progress hub.
/// Self-contained in EngagementFeature so it doesn't pull SettingsFeature
/// into the dependency.
public struct RemindersSection: View {
    private let store: ReminderStore
    private let scheduler: NotificationScheduler
    /// Feeds the streak-defense layer: when the streak is fresh and unsaved
    /// today, the next reminder becomes "your N-day streak is on the line".
    /// Optional so previews/tests without a streak store still work.
    private let streakStore: StreakStore?
    /// The lesson a tapped reminder opens; `nil` opens the app as usual.
    private let nextLessonId: String?
    /// One plain weekly switch, no streak switch (onboarding).
    private let plain: Bool

    @Environment(\.scenePhase) private var scenePhase
    /// Whether iOS currently lets Mercurius post notifications. A switch only
    /// reads ON when its preference is set AND delivery is possible — a
    /// student who turned notifications off in iOS Settings must not see an
    /// ON switch that delivers nothing.
    @State private var authorized = false
    @State private var permissionDenied = false
    /// Switches whose permission request is in flight. They stay ON meanwhile
    /// (the request can sit under the system alert for as long as the user
    /// deliberates) instead of visibly snapping back to OFF, which reads as
    /// "the tap didn't take" and invites re-taps.
    @State private var pending: Set<ReminderEnabler.Kind> = []

    public init(
        store: ReminderStore,
        scheduler: NotificationScheduler,
        streakStore: StreakStore? = nil,
        nextLessonId: String? = nil,
        plain: Bool = false
    ) {
        self.store = store
        self.scheduler = scheduler
        self.streakStore = streakStore
        self.nextLessonId = nextLessonId
        self.plain = plain
    }

    /// The words on the switches.
    enum Copy {
        static let weeklyTitle = "Weekly nudges (Wed & Sun)"
        static let weeklyDetail = "Sunday at 6 PM and Wednesday at 7 PM. None once you've done two lessons that week."
        static let dailyTitle = "Daily streak reminder"
        static let dailyDetail = "Only while you have a streak going."
        static let plainTitle = "Remind me to practice"
        static let plainDetail = "Twice a week: Sunday at 6 PM and Wednesday at 7 PM."
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Reminders")
                .font(BrandFont.subheading)
                .foregroundStyle(BrandColor.text)

            if plain {
                toggle(.weekly, title: Copy.plainTitle, detail: Copy.plainDetail)
            } else {
                toggle(.weekly, title: Copy.weeklyTitle, detail: Copy.weeklyDetail)

                toggle(.daily, title: Copy.dailyTitle, detail: Copy.dailyDetail)
            }

            if !plain && store.enabled && authorized {
                DatePicker(
                    "Time",
                    selection: Binding(get: { timeAsDate() }, set: { setTime($0) }),
                    displayedComponents: .hourAndMinute
                )
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
            }

            if permissionDenied {
                Text(Self.permissionDeniedNote)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .padding(BrandSpacing.lg)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: BrandRadius.lg, style: .continuous))
        .task { await refreshAuthorization() }
        // Coming back from the iOS Settings app may have changed permission.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshAuthorization() }
            }
        }
    }

    /// Where to turn notifications back on, in the platform's words.
    static var permissionDeniedNote: String {
        #if os(macOS)
        "Notifications are off for Mercurius. Turn them on in System Settings ▸ Notifications to get reminders."
        #else
        "Notifications are off for Mercurius. Turn them on in the iOS Settings app to get reminders."
        #endif
    }

    private func toggle(_ kind: ReminderEnabler.Kind, title: String, detail: String) -> some View {
        Toggle(isOn: Binding(get: { isOn(kind) }, set: { setOn(kind, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                Text(detail)
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .tint(BrandColor.accent)
    }

    private func isOn(_ kind: ReminderEnabler.Kind) -> Bool {
        pending.contains(kind) || (preference(kind) && authorized)
    }

    private func preference(_ kind: ReminderEnabler.Kind) -> Bool {
        switch kind {
        case .weekly: return store.weeklyEnabled
        case .daily: return store.enabled
        }
    }

    private func setOn(_ kind: ReminderEnabler.Kind, _ on: Bool) {
        guard on else {
            pending.remove(kind)
            permissionDenied = false
            switch kind {
            case .weekly: store.weeklyEnabled = false
            case .daily: store.enabled = false
            }
            refreshSchedule()
            return
        }
        // Re-entry guard: a second flip while this switch's permission
        // request is in flight must not spawn a parallel request.
        guard !pending.contains(kind) else { return }
        pending.insert(kind)
        Task {
            let granted = await ReminderEnabler.enable(
                kind, store: store, scheduler: scheduler,
                streakStore: streakStore, nextLessonId: nextLessonId
            )
            authorized = granted
            permissionDenied = !granted
            pending.remove(kind)
        }
    }

    private func setTime(_ date: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        store.hour = comps.hour ?? 18
        store.minute = comps.minute ?? 0
        if store.enabled {
            refreshSchedule()
        }
    }

    private func refreshSchedule() {
        ReminderEnabler.refresh(store: store, scheduler: scheduler,
                                streakStore: streakStore, nextLessonId: nextLessonId)
    }

    private func refreshAuthorization() async {
        authorized = await scheduler.notificationsAuthorized()
        if authorized { permissionDenied = false }
    }

    private func timeAsDate() -> Date {
        Calendar.current.date(bySettingHour: store.hour, minute: store.minute, second: 0, of: Date()) ?? Date()
    }
}

/// The previous name, kept so existing hosts compile; the section now also
/// carries the weekly nudges.
@available(*, deprecated, renamed: "RemindersSection")
public typealias DailyReminderSection = RemindersSection
