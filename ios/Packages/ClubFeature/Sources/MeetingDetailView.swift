import SwiftUI
import DesignSystem

/// Detail view for a single upcoming meeting. Surfaces the topics,
/// key questions, and suggested-reading hints a student needs to
/// come prepared.
struct MeetingDetailView: View {
    let meeting: UpcomingMeeting

    var body: some View {
        List {
            headerSection
            if let topics = meeting.topics, !topics.isEmpty {
                topicsSection(topics)
            }
            if let questions = meeting.keyQuestions, !questions.isEmpty {
                questionsSection(questions)
            }
            if let reading = meeting.suggestedReading {
                readingSection(reading)
            }
            if meeting.location != nil || meeting.time != nil {
                logisticsSection
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollContentBackground(.hidden)
        .background(BrandColor.background)
        .navigationTitle(meeting.label ?? "Meeting")
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                if let label = meeting.label {
                    Text(label.uppercased())
                        .font(BrandFont.caption)
                        .tracking(1.4)
                        .foregroundStyle(BrandColor.accent)
                }
                Text(meeting.title)
                    .font(BrandFont.title)
                    .foregroundStyle(BrandColor.text)
                Text(formattedFullDate(meeting.date))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                Text(meeting.description)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .padding(.top, BrandSpacing.xs)
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    private func topicsSection(_ topics: [String]) -> some View {
        Section("Topics") {
            ForEach(topics, id: \.self) { topic in
                Text(topic)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
            }
        }
    }

    private func questionsSection(_ questions: [String]) -> some View {
        Section("Key questions") {
            ForEach(questions, id: \.self) { question in
                Text(question)
                    .font(BrandFont.body)
                    .foregroundStyle(BrandColor.text)
                    .padding(.vertical, 2)
            }
        }
    }

    private func readingSection(_ reading: String) -> some View {
        Section("Suggested reading") {
            Text(reading)
                .font(BrandFont.body)
                .foregroundStyle(BrandColor.text)
        }
    }

    private var logisticsSection: some View {
        Section("Logistics") {
            if let location = meeting.location {
                LabeledContent("Location", value: location)
            }
            if let time = meeting.time {
                LabeledContent("Time", value: time)
            }
        }
    }
}

// MARK: - Date helpers

private func formattedFullDate(_ raw: String) -> String {
    let parser = DateFormatter()
    parser.dateFormat = "yyyy-MM-dd"
    parser.timeZone = TimeZone(identifier: "UTC")
    guard let date = parser.date(from: raw) else { return raw }

    let out = DateFormatter()
    out.dateFormat = "EEEE, MMMM d, yyyy"
    out.timeZone = .current
    return out.string(from: date)
}
