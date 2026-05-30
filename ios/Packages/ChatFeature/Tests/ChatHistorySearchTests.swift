import Testing
import Foundation
@testable import ChatFeature
import NetworkingKit
import PersistenceKit

// Unit tests for the chat-history search predicate (`ChatHistorySearch.matches`).

private func makeSummary(title: String, preview: String) -> ConversationSummary {
    ConversationSummary(
        id: UUID(),
        mode: ChatMode.socratic.rawValue,
        title: title,
        preview: preview,
        messageCount: 4,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

@Suite("ChatHistorySearch.matches")
struct ChatHistorySearchTests {
    private let convo = makeSummary(
        title: "How does an LLM actually work?",
        preview: "It depends what you mean by 'work' — the simplest answer is next-token prediction."
    )

    @Test("Empty or whitespace query matches everything")
    func emptyMatchesAll() {
        #expect(ChatHistorySearch.matches(convo, query: ""))
        #expect(ChatHistorySearch.matches(convo, query: "   "))
        #expect(ChatHistorySearch.matches(convo, query: "\n\t"))
    }

    @Test("Matches a substring of the title, case-insensitively")
    func matchesTitle() {
        #expect(ChatHistorySearch.matches(convo, query: "llm"))
        #expect(ChatHistorySearch.matches(convo, query: "LLM"))
        #expect(ChatHistorySearch.matches(convo, query: "actually work"))
    }

    @Test("Matches a substring of the preview snippet")
    func matchesPreview() {
        #expect(ChatHistorySearch.matches(convo, query: "next-token"))
        #expect(ChatHistorySearch.matches(convo, query: "PREDICTION"))
    }

    @Test("Returns false when neither title nor preview contains the query")
    func noMatch() {
        #expect(!ChatHistorySearch.matches(convo, query: "photosynthesis"))
        #expect(!ChatHistorySearch.matches(convo, query: "report card"))
    }

    @Test("Surrounding whitespace in the query is trimmed before matching")
    func trimsQuery() {
        #expect(ChatHistorySearch.matches(convo, query: "  llm  "))
    }

    @Test("Diacritic-insensitive (localizedStandardContains)")
    func diacriticInsensitive() {
        let cafe = makeSummary(title: "Notes on the café model", preview: "")
        #expect(ChatHistorySearch.matches(cafe, query: "cafe"))
    }
}
