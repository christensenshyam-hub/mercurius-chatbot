import Foundation

// Models mirror the JSON shape served by mayoailiteracy.com's
// events-data.json and blog-content.json endpoints. Field-level optionality
// is chosen to match what the real server actually returns — some fields
// are consistently present (title, description), others are only on the
// upcoming meeting entries (label, keyQuestions), and a few are free to
// drift (topics, suggestedReading). Decoding is tolerant of missing
// optional fields so a shape change on the server doesn't brick the tab.

/// Regular-meeting metadata — where and when the club meets by default.
public struct ClubSchedule: Codable, Sendable, Equatable {
    public let day: String
    public let time: String
    public let location: String
    public let openTo: String?

    public init(day: String, time: String, location: String, openTo: String? = nil) {
        self.day = day
        self.time = time
        self.location = location
        self.openTo = openTo
    }
}

/// A meeting that hasn't happened yet. `label` is the server's tag
/// (e.g. "Next Meeting", "Advanced Seminar"); we surface it as a chip.
public struct UpcomingMeeting: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(date)_\(title)" }
    public let date: String            // ISO date (YYYY-MM-DD)
    public let label: String?
    public let title: String
    public let description: String
    public let topics: [String]?
    public let keyQuestions: [String]?
    public let suggestedReading: String?
    public let location: String?
    public let time: String?

    public init(
        date: String,
        label: String? = nil,
        title: String,
        description: String,
        topics: [String]? = nil,
        keyQuestions: [String]? = nil,
        suggestedReading: String? = nil,
        location: String? = nil,
        time: String? = nil
    ) {
        self.date = date
        self.label = label
        self.title = title
        self.description = description
        self.topics = topics
        self.keyQuestions = keyQuestions
        self.suggestedReading = suggestedReading
        self.location = location
        self.time = time
    }
}

/// A meeting that has already happened.
public struct PastMeeting: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(date)_\(title)" }
    public let date: String
    public let title: String
    public let description: String
    public let recapUrl: String?

    public init(date: String, title: String, description: String, recapUrl: String? = nil) {
        self.date = date
        self.title = title
        self.description = description
        self.recapUrl = recapUrl
    }
}

/// The full events-data.json document.
public struct ClubEvents: Codable, Sendable, Equatable {
    public let schedule: ClubSchedule
    public let upcoming: [UpcomingMeeting]
    public let past: [PastMeeting]

    public init(
        schedule: ClubSchedule,
        upcoming: [UpcomingMeeting] = [],
        past: [PastMeeting] = []
    ) {
        self.schedule = schedule
        self.upcoming = upcoming
        self.past = past
    }
}

/// A blog-content.json entry. `content` holds the full post body as
/// plain text (occasionally lightly formatted with paragraph breaks).
public struct BlogPost: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let date: String
    public let author: String
    public let category: String
    public let summary: String
    public let content: String

    public init(
        id: String,
        title: String,
        date: String,
        author: String,
        category: String,
        summary: String,
        content: String
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.author = author
        self.category = category
        self.summary = summary
        self.content = content
    }
}
