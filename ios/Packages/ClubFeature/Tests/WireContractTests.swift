import Testing
import Foundation
@testable import ClubFeature

// Wire-contract tests for the Club endpoints.
//
// These run against *real production JSON* captured from
// mayoailiteracy.com and pinned as test resources. If the live server
// ever changes shape in a way that would break the Club tab on iOS,
// refreshing these fixtures (via `curl` — see the Phase 3m commit
// message for instructions) will produce a failing test long before
// any user taps that tab on a released build.
//
// Distinct from `ClubCodableTests`, which uses small synthesized JSON
// to verify Codable conformance and optional-field tolerance. These
// tests verify end-to-end that *the actual bytes the server sends*
// decode into the DTOs we ship.

// MARK: - Fixture loading

private enum Fixture {
    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case notFound(String)
        var description: String {
            switch self {
            case .notFound(let name):
                return "Fixture '\(name).json' not found in Bundle.module. Did you forget to add it to the `resources` list in Package.swift?"
            }
        }
    }
}

// MARK: - Live-shape decode tests

@Suite("Club wire contract — real production JSON")
struct WireContractTests {

    @Test("events-data.json fixture decodes into ClubEvents without fields being lost")
    func eventsDataDecodes() throws {
        let data = try Fixture.data(named: "events-data")
        let events = try JSONDecoder().decode(ClubEvents.self, from: data)

        // Spot-check the shape rather than exact values — the fixture
        // will be re-captured as the club's real calendar changes.
        #expect(!events.schedule.day.isEmpty)
        #expect(!events.schedule.time.isEmpty)
        #expect(!events.schedule.location.isEmpty)
        // At least one of upcoming or past should exist in any
        // released fixture. A completely empty calendar would itself
        // be worth noticing.
        #expect(!events.upcoming.isEmpty || !events.past.isEmpty)
    }

    @Test("blog-content.json fixture decodes into an array of BlogPost")
    func blogContentDecodes() throws {
        let data = try Fixture.data(named: "blog-content")
        let posts = try JSONDecoder().decode([BlogPost].self, from: data)

        // The club's blog has been actively published. If this is ever
        // empty, either the fixture was regenerated from a broken
        // server or the server cleared its blog — either is a signal.
        #expect(!posts.isEmpty)
        for post in posts {
            // Every field the UI reads must be present and non-empty.
            #expect(!post.id.isEmpty, "Post id must be non-empty")
            #expect(!post.title.isEmpty, "Post title must be non-empty")
            #expect(!post.author.isEmpty, "Post author must be non-empty")
            #expect(!post.summary.isEmpty, "Post summary must be non-empty")
            #expect(!post.content.isEmpty, "Post content must be non-empty")
        }
    }

    @Test("BlogPost ids are unique across the fixture")
    func blogPostIdsUnique() throws {
        let data = try Fixture.data(named: "blog-content")
        let posts = try JSONDecoder().decode([BlogPost].self, from: data)
        let ids = posts.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate post ids in the fixture: \(ids)")
    }

    @Test("Upcoming meetings have parseable YYYY-MM-DD dates")
    func upcomingDatesAreParseable() throws {
        let data = try Fixture.data(named: "events-data")
        let events = try JSONDecoder().decode(ClubEvents.self, from: data)

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(identifier: "UTC")

        for meeting in events.upcoming {
            #expect(
                parser.date(from: meeting.date) != nil,
                "Upcoming meeting '\(meeting.title)' has unparseable date '\(meeting.date)'"
            )
        }
    }
}

// MARK: - Defensive decoding

@Suite("Club DTOs — defensive decoding")
struct ClubDefensiveDecodingTests {

    @Test("Extra unknown fields on ClubEvents are ignored (forward compatibility)")
    func extraFieldsIgnored() throws {
        let json = #"""
        {
          "schedule": {
            "day": "Thursday",
            "time": "8:20 AM",
            "location": "Library",
            "openTo": "All MHS Students",
            "somethingNewTheServerAdded": "safe to ignore"
          },
          "upcoming": [],
          "past": [],
          "futureFieldWeDontKnowAbout": {"nested": true}
        }
        """#
        let events = try JSONDecoder().decode(ClubEvents.self, from: Data(json.utf8))
        #expect(events.schedule.day == "Thursday")
        // The main promise: adding fields to the server shouldn't break
        // older app versions.
    }

    @Test("Null optional fields decode as nil rather than throwing")
    func nullOptionalsAreNil() throws {
        let json = #"""
        {
          "date": "2026-04-10",
          "label": null,
          "title": "Test",
          "description": "Test desc",
          "topics": null,
          "keyQuestions": null,
          "suggestedReading": null,
          "location": null,
          "time": null
        }
        """#
        let meeting = try JSONDecoder().decode(UpcomingMeeting.self, from: Data(json.utf8))
        #expect(meeting.label == nil)
        #expect(meeting.topics == nil)
        #expect(meeting.keyQuestions == nil)
        #expect(meeting.suggestedReading == nil)
    }

    @Test("Missing required field on ClubSchedule throws a decoding error")
    func missingRequiredFieldThrows() {
        // Required fields: day, time, location. If the server ever
        // drops one, we want a loud failure (tests red) rather than a
        // silently-blank UI.
        let json = #"""
        {
          "day": "Thursday",
          "location": "Library"
        }
        """#
        do {
            _ = try JSONDecoder().decode(ClubSchedule.self, from: Data(json.utf8))
            Issue.record("Expected a decoding error for missing 'time' field")
        } catch is DecodingError {
            // expected — any DecodingError subcase is fine
        } catch {
            Issue.record("Expected DecodingError, got \(error)")
        }
    }

    @Test("Empty upcoming + past arrays decode cleanly")
    func emptyArraysOK() throws {
        let json = #"""
        {
          "schedule": { "day": "Thursday", "time": "8:20 AM", "location": "Library" },
          "upcoming": [],
          "past": []
        }
        """#
        let events = try JSONDecoder().decode(ClubEvents.self, from: Data(json.utf8))
        #expect(events.upcoming.isEmpty)
        #expect(events.past.isEmpty)
    }

    @Test("BlogPost rejects missing required fields")
    func blogPostMissingFields() {
        // Every BlogPost field listed in Models.swift is non-optional.
        // If the server ever drops one, the test should fail.
        let incomplete = #"""
        { "id": "x", "title": "t", "date": "2026-01-01", "author": "a", "summary": "s" }
        """#
        do {
            _ = try JSONDecoder().decode(BlogPost.self, from: Data(incomplete.utf8))
            Issue.record("Expected decoding error — missing category + content")
        } catch is DecodingError {
            // expected
        } catch {
            Issue.record("Expected DecodingError, got \(error)")
        }
    }
}
