import Testing
import Foundation
@testable import ClubFeature
@testable import NetworkingKit

// MARK: - Stub client

final class StubClubClient: ClubDataProviding, @unchecked Sendable {
    var eventsResult: Result<ClubEvents, Error> = .success(
        ClubEvents(
            schedule: ClubSchedule(day: "Thursday", time: "8:20 AM", location: "Library"),
            upcoming: [],
            past: []
        )
    )
    var postsResult: Result<[BlogPost], Error> = .success([])
    var eventsFetchCount = 0
    var postsFetchCount = 0

    func fetchEvents() async throws -> ClubEvents {
        eventsFetchCount += 1
        return try eventsResult.get()
    }

    func fetchBlogPosts() async throws -> [BlogPost] {
        postsFetchCount += 1
        return try postsResult.get()
    }
}

// MARK: - Fixtures

private func sampleEvents(upcoming: Int = 1, past: Int = 2) -> ClubEvents {
    let upcomingMeetings = (0..<upcoming).map { i in
        UpcomingMeeting(
            date: "2026-04-\(10 + i)",
            label: i == 0 ? "Next Meeting" : nil,
            title: "Upcoming \(i + 1)",
            description: "Description \(i + 1)",
            topics: ["t1", "t2"],
            keyQuestions: ["Q\(i + 1)?"]
        )
    }
    let pastMeetings = (0..<past).map { i in
        PastMeeting(
            date: "2026-03-\(10 + i)",
            title: "Past \(i + 1)",
            description: "Past desc \(i + 1)"
        )
    }
    return ClubEvents(
        schedule: ClubSchedule(day: "Thursday", time: "8:20 AM", location: "Library"),
        upcoming: upcomingMeetings,
        past: pastMeetings
    )
}

private func samplePosts(_ count: Int = 2) -> [BlogPost] {
    (0..<count).map { i in
        BlogPost(
            id: "post-\(i)",
            title: "Post \(i + 1)",
            date: "2026-03-\(15 + i)",
            author: "Author",
            category: "opinion",
            summary: "Summary",
            content: "Full content here."
        )
    }
}

// MARK: - Tests

@Suite("ClubViewModel.load — state machine")
@MainActor
struct ClubLoadTests {

    @Test("Defaults to .idle and empty content")
    func defaults() {
        let client = StubClubClient()
        let model = ClubViewModel(client: client)
        #expect(model.phase == .idle)
        #expect(model.events == nil)
        #expect(model.posts.isEmpty)
        #expect(!model.hasAnyContent)
    }

    @Test("Successful load populates events + posts and ends in .loaded")
    func loadsBoth() async {
        let client = StubClubClient()
        client.eventsResult = .success(sampleEvents())
        client.postsResult = .success(samplePosts())

        let model = ClubViewModel(client: client)
        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.events?.upcoming.count == 1)
        #expect(model.posts.count == 2)
        #expect(model.hasAnyContent)
    }

    @Test("Events endpoint failure produces .failed (retryable for network)")
    func eventsFailFails() async {
        let client = StubClubClient()
        client.eventsResult = .failure(APIError.offline)
        client.postsResult = .success(samplePosts())

        let model = ClubViewModel(client: client)
        await model.load()

        if case .failed(_, let retryable) = model.phase {
            #expect(retryable, "Offline should be retryable")
        } else {
            Issue.record("Expected .failed phase, got \(model.phase)")
        }
    }

    @Test("Posts endpoint failure also produces .failed")
    func postsFailFails() async {
        let client = StubClubClient()
        client.eventsResult = .success(sampleEvents())
        client.postsResult = .failure(APIError.timeout)

        let model = ClubViewModel(client: client)
        await model.load()

        if case .failed = model.phase {
            // Expected
        } else {
            Issue.record("Expected .failed")
        }
    }

    @Test("Non-retryable error is marked non-retryable")
    func nonRetryableError() async {
        let client = StubClubClient()
        client.eventsResult = .failure(APIError.unauthorized)
        let model = ClubViewModel(client: client)
        await model.load()

        if case .failed(_, let retryable) = model.phase {
            #expect(!retryable)
        } else {
            Issue.record("Expected .failed")
        }
    }

    @Test("Both endpoints are fetched exactly once per load()")
    func eachEndpointHitOncePerLoad() async {
        let client = StubClubClient()
        let model = ClubViewModel(client: client)
        await model.load()
        #expect(client.eventsFetchCount == 1)
        #expect(client.postsFetchCount == 1)

        await model.load()
        #expect(client.eventsFetchCount == 2)
        #expect(client.postsFetchCount == 2)
    }

    @Test("Refresh keeps stale content visible by not flipping back to .loading")
    func refreshPreservesContent() async {
        // First load succeeds.
        let client = StubClubClient()
        client.eventsResult = .success(sampleEvents())
        client.postsResult = .success(samplePosts())
        let model = ClubViewModel(client: client)
        await model.load()
        #expect(model.phase == .loaded)

        // Second load fails — stale data should remain visible. The view
        // uses `hasAnyContent` to decide whether to show the failure UI
        // or keep the list up with the system refresh spinner.
        client.eventsResult = .failure(APIError.offline)
        await model.load()

        if case .failed = model.phase {
            // expected
        } else {
            Issue.record("Expected .failed on refresh fail")
        }
        #expect(model.events != nil, "Previously-loaded events should survive a failed refresh")
        #expect(!model.posts.isEmpty, "Previously-loaded posts should survive a failed refresh")
    }

    @Test("nextMeeting returns the first upcoming entry (nil when none)")
    func nextMeetingShortcut() async {
        let client = StubClubClient()
        client.eventsResult = .success(sampleEvents(upcoming: 2))
        let model = ClubViewModel(client: client)

        #expect(model.nextMeeting == nil, "No meetings loaded yet")

        await model.load()
        #expect(model.nextMeeting?.title == "Upcoming 1")
    }
}

// MARK: - Models — codable round-trip

@Suite("Club models — Codable round-trip")
struct ClubCodableTests {

    @Test("ClubEvents round-trips through JSON with all fields populated")
    func eventsRoundTrip() throws {
        let original = ClubEvents(
            schedule: ClubSchedule(
                day: "Thursday",
                time: "8:20 AM",
                location: "Library",
                openTo: "All MHS Students"
            ),
            upcoming: [
                UpcomingMeeting(
                    date: "2026-04-10",
                    label: "Next",
                    title: "Title",
                    description: "Desc",
                    topics: ["a"],
                    keyQuestions: ["Q?"],
                    suggestedReading: "Read X",
                    location: "Room",
                    time: "8:20 AM"
                ),
            ],
            past: [
                PastMeeting(
                    date: "2026-03-01",
                    title: "Past",
                    description: "D",
                    recapUrl: "https://example.com"
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClubEvents.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("BlogPost decodes the real schema served by mayoailiteracy.com")
    func blogPostDecodesProdShape() throws {
        // Mirrors the schema the live server actually returns.
        let json = #"""
        {
          "id": "post-123",
          "title": "AI in 2026",
          "date": "2026-03-15",
          "author": "Shyam Christensen",
          "category": "opinion",
          "summary": "One-paragraph teaser.",
          "content": "Full post body..."
        }
        """#
        let post = try JSONDecoder().decode(BlogPost.self, from: Data(json.utf8))
        #expect(post.id == "post-123")
        #expect(post.author == "Shyam Christensen")
        #expect(post.category == "opinion")
    }

    @Test("UpcomingMeeting tolerates missing optional fields")
    func upcomingWithMinimalFields() throws {
        let json = #"""
        {
          "date": "2026-04-10",
          "title": "Minimal",
          "description": "Just the basics"
        }
        """#
        let meeting = try JSONDecoder().decode(UpcomingMeeting.self, from: Data(json.utf8))
        #expect(meeting.title == "Minimal")
        #expect(meeting.label == nil)
        #expect(meeting.topics == nil)
        #expect(meeting.keyQuestions == nil)
    }
}
