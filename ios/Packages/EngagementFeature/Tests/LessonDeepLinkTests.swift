import Testing
import Foundation
@testable import EngagementFeature

/// Pins the `mercurius://lesson/<id>` link that reminders carry and
/// `NotificationRouter` parses on tap.
struct LessonDeepLinkTests {

    private func id(_ raw: String) -> String? {
        URL(string: raw).flatMap(LessonDeepLink.lessonId(from:))
    }

    @Test("Builds the lesson link and parses it back")
    func roundTrip() {
        let raw = LessonDeepLink.urlString(forLesson: "u1_l3")
        #expect(raw == "mercurius://lesson/u1_l3")
        #expect(id(raw) == "u1_l3")
    }

    @Test("Accepts a case-insensitive scheme and host")
    func caseInsensitive() {
        #expect(id("Mercurius://LESSON/u2_l1") == "u2_l1")
    }

    @Test("Rejects other schemes and hosts")
    func wrongSchemeOrHost() {
        #expect(id("https://lesson/u1_l3") == nil)
        #expect(id("mercurius://session") == nil)
        #expect(id("mercurius://session/u1_l3") == nil)
        #expect(id("mercurius://unit/unit_1") == nil)
    }

    @Test("Rejects a missing or malformed lesson id")
    func missingOrMalformedId() {
        #expect(id("mercurius://lesson") == nil)
        #expect(id("mercurius://lesson/") == nil)
        #expect(id("mercurius://lesson/u1%20l3") == nil)
        #expect(id("mercurius://lesson/u1_l3%2F..") == nil)
    }

    @Test("Uses the last path component")
    func lastComponent() {
        #expect(id("mercurius://lesson/extra/u3_l2") == "u3_l2")
    }

    @Test("Reads the link from notification userInfo")
    func fromUserInfo() {
        let info: [AnyHashable: Any] = [LessonDeepLink.userInfoKey: "mercurius://lesson/u1_l1"]
        #expect(LessonDeepLink.userInfoKey == "url")
        #expect(LessonDeepLink.lessonId(fromUserInfo: info) == "u1_l1")
        #expect(LessonDeepLink.lessonId(fromUserInfo: [:]) == nil)
        #expect(LessonDeepLink.lessonId(fromUserInfo: ["url": 42]) == nil)
        #expect(LessonDeepLink.lessonId(fromUserInfo: ["url": "not a url"]) == nil)
        #expect(LessonDeepLink.lessonId(fromUserInfo: ["url": "mercurius://session"]) == nil)
    }
}
