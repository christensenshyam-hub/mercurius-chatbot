import SwiftUI
import DesignSystem

/// Root view for the Club tab. Shows the regular-meeting schedule,
/// upcoming + past meetings, and the club's blog posts.
///
/// Pulls data directly from `mayoailiteracy.com`'s public JSON files,
/// so the tab works offline only with cached content but requires no
/// auth or server-side state.
public struct ClubView: View {
    @Bindable var model: ClubViewModel

    public init(model: ClubViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Club")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .background(BrandColor.background)
                .task { await initialLoadIfNeeded() }
                .refreshable { await model.load() }
        }
        .tint(BrandColor.accent)
    }

    // MARK: - Phase switching

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .loading where !model.hasAnyContent:
            loadingView
        case .failed(let reason, let isRetryable) where !model.hasAnyContent:
            failureView(reason: reason, isRetryable: isRetryable)
        case .loaded, .loading, .failed:
            // Either fully loaded, or refreshing with stale content, or
            // a refresh failed but we still have prior content — all
            // three paths render the list.
            loadedList
        }
    }

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Loading the club…")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColor.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading club content")
    }

    private func failureView(reason: String, isRetryable: Bool) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(BrandColor.textSecondary)
            Text("Couldn't load the club")
                .font(BrandFont.title)
                .foregroundStyle(BrandColor.text)
            Text(reason)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            if isRetryable {
                BrandButton("Try again", style: .primary) {
                    Task { await model.load() }
                }
                .frame(maxWidth: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.xl)
        .background(BrandColor.background)
    }

    // MARK: - Loaded content

    private var loadedList: some View {
        List {
            if let schedule = model.events?.schedule {
                scheduleSection(schedule)
            }
            if let upcoming = model.events?.upcoming, !upcoming.isEmpty {
                upcomingSection(upcoming)
            }
            if !model.posts.isEmpty {
                postsSection(model.posts)
            }
            if let past = model.events?.past, !past.isEmpty {
                pastSection(past)
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#endif
        .scrollContentBackground(.hidden)
        .background(BrandColor.background)
    }

    private func scheduleSection(_ schedule: ClubSchedule) -> some View {
        Section {
            LabeledContent("When", value: "\(schedule.day), \(schedule.time)")
            LabeledContent("Where", value: schedule.location)
            if let openTo = schedule.openTo {
                LabeledContent("Open to", value: openTo)
            }
        } header: {
            Text("Regular meeting")
        }
    }

    private func upcomingSection(_ meetings: [UpcomingMeeting]) -> some View {
        Section("Upcoming") {
            ForEach(meetings) { meeting in
                NavigationLink {
                    MeetingDetailView(meeting: meeting)
                } label: {
                    UpcomingMeetingRow(meeting: meeting)
                }
            }
        }
    }

    private func postsSection(_ posts: [BlogPost]) -> some View {
        Section("Blog") {
            ForEach(posts) { post in
                NavigationLink {
                    BlogPostDetailView(post: post)
                } label: {
                    BlogPostRow(post: post)
                }
            }
        }
    }

    private func pastSection(_ meetings: [PastMeeting]) -> some View {
        Section("Past meetings") {
            ForEach(meetings) { meeting in
                PastMeetingRow(meeting: meeting)
            }
        }
    }

    // MARK: - Load gate

    private func initialLoadIfNeeded() async {
        guard case .idle = model.phase else { return }
        await model.load()
    }
}

// MARK: - Rows

private struct UpcomingMeetingRow: View {
    let meeting: UpcomingMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = meeting.label {
                Text(label.uppercased())
                    .font(BrandFont.caption)
                    .tracking(1.2)
                    .foregroundStyle(BrandColor.accent)
            }
            Text(meeting.title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
            Text(formattedDate(meeting.date))
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            Text(meeting.description)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PastMeetingRow: View {
    let meeting: PastMeeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
            Text(formattedDate(meeting.date))
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            Text(meeting.description)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct BlogPostRow: View {
    let post: BlogPost

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(post.category.uppercased())
                .font(BrandFont.caption)
                .tracking(1.2)
                .foregroundStyle(BrandColor.accent)
            Text(post.title)
                .font(BrandFont.bodyEmphasized)
                .foregroundStyle(BrandColor.text)
            Text("\(post.author) • \(formattedDate(post.date))")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
            Text(post.summary)
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.textSecondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Date helpers

/// Format a `YYYY-MM-DD` string as, e.g. "Thursday, March 26".
/// Falls through to the raw string if parsing fails — avoids
/// ever rendering the user a wall of broken dates.
private func formattedDate(_ raw: String) -> String {
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM-dd"
    parser.timeZone = TimeZone(identifier: "UTC")
    guard let date = parser.date(from: raw) else { return raw }

    let out = DateFormatter()
    out.dateFormat = "EEEE, MMMM d"
    out.timeZone = .current
    return out.string(from: date)
}
