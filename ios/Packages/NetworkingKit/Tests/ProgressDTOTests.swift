import Testing
import Foundation
@testable import NetworkingKit

@Suite("Progress DTO decoding")
struct ProgressDTOTests {

    private func decode(_ json: String) throws -> ProgressSnapshotDTO {
        try JSONDecoder().decode(ProgressSnapshotDTO.self, from: Data(json.utf8))
    }

    private func decodeItem(_ json: String) throws -> ProgressItemDTO {
        try JSONDecoder().decode(ProgressItemDTO.self, from: Data(json.utf8))
    }

    @Test("Decodes the server's GET shape: version + lessons + units with epoch-ms updatedAt")
    func fullShape() throws {
        let json = #"""
        {"curriculumVersion":1,
         "lessons":[{"id":"u1_l1","status":"completed","updatedAt":1751234567890},
                    {"id":"u1_l2","status":"completed","updatedAt":1751234567891}],
         "units":[{"id":"unit_1","status":"mastered","updatedAt":1751234567892}]}
        """#
        let snapshot = try decode(json)
        #expect(snapshot.curriculumVersion == 1)
        #expect(snapshot.lessons.map(\.id) == ["u1_l1", "u1_l2"])
        #expect(snapshot.lessons.allSatisfy { $0.status == ProgressStatus.completed.rawValue })
        #expect(snapshot.units == [
            ProgressItemDTO(id: "unit_1", status: "mastered", updatedAt: Date(timeIntervalSince1970: 1_751_234_567.892))
        ])
        #expect(snapshot.lessons[0].updatedAt == Date(timeIntervalSince1970: 1_751_234_567.890))
    }

    @Test("An unknown session decodes as the empty snapshot")
    func unknownSession() throws {
        let snapshot = try decode(#"{"curriculumVersion":null,"lessons":[],"units":[]}"#)
        #expect(snapshot == ProgressSnapshotDTO(curriculumVersion: nil))
        #expect(snapshot.lessons.isEmpty)
        #expect(snapshot.units.isEmpty)
    }

    @Test("Missing arrays and a missing version decode as empty, not a failure")
    func missingKeys() throws {
        #expect(try decode("{}") == ProgressSnapshotDTO(curriculumVersion: nil))
        let lessonsOnly = try decode(#"{"lessons":[{"id":"u2_l1","status":"completed"}]}"#)
        #expect(lessonsOnly.lessons.count == 1)
        #expect(lessonsOnly.units.isEmpty)
        #expect(lessonsOnly.curriculumVersion == nil)
    }

    @Test("curriculumVersion as a numeric string (node-postgres) still decodes as Int")
    func stringVersion() throws {
        #expect(try decode(#"{"curriculumVersion":"2"}"#).curriculumVersion == 2)
        #expect(try decode(#"{"curriculumVersion":"not-a-number"}"#).curriculumVersion == nil)
    }

    @Test("updatedAt as epoch seconds decodes as that instant")
    func epochSeconds() throws {
        let item = try decodeItem(#"{"id":"u1_l1","status":"completed","updatedAt":1751234567}"#)
        #expect(item.updatedAt == Date(timeIntervalSince1970: 1_751_234_567))
    }

    @Test("updatedAt as a numeric string (node-postgres int8) decodes as epoch ms")
    func epochStringMillis() throws {
        let item = try decodeItem(#"{"id":"u1_l1","status":"completed","updatedAt":"1751234567890"}"#)
        #expect(item.updatedAt == Date(timeIntervalSince1970: 1_751_234_567.890))
    }

    @Test("updatedAt as ISO 8601 text decodes, with or without fractional seconds")
    func isoStrings() throws {
        let plain = try decodeItem(#"{"id":"u1_l1","status":"completed","updatedAt":"2026-05-30T12:00:00Z"}"#)
        #expect(plain.updatedAt == Date(timeIntervalSince1970: 1_780_142_400))
        let fractional = try decodeItem(#"{"id":"u1_l1","status":"completed","updatedAt":"2026-05-30T12:00:00.500Z"}"#)
        #expect(fractional.updatedAt == Date(timeIntervalSince1970: 1_780_142_400.5))
    }

    @Test("A missing, null or malformed updatedAt degrades to nil", arguments: [
        #"{"id":"u1_l1","status":"completed"}"#,
        #"{"id":"u1_l1","status":"completed","updatedAt":null}"#,
        #"{"id":"u1_l1","status":"completed","updatedAt":"yesterday"}"#,
        #"{"id":"u1_l1","status":"completed","updatedAt":true}"#,
        #"{"id":"u1_l1","status":"completed","updatedAt":{"ms":1}}"#,
        #"{"id":"u1_l1","status":"completed","updatedAt":-5}"#,
    ])
    func degradedUpdatedAt(_ json: String) throws {
        let item = try decodeItem(json)
        #expect(item.id == "u1_l1")
        #expect(item.updatedAt == nil)
    }

    @Test("An unknown status string is kept verbatim instead of failing the decode")
    func unknownStatus() throws {
        let snapshot = try decode(#"{"lessons":[{"id":"u1_l1","status":"archived","updatedAt":1}]}"#)
        #expect(snapshot.lessons.first?.status == "archived")
        #expect(ProgressStatus(rawValue: "archived") == nil)
    }

    @Test("Unknown keys on the snapshot and its items are ignored")
    func unknownKeys() throws {
        let snapshot = try decode(
            #"{"curriculumVersion":1,"lessons":[{"id":"u1_l1","status":"completed","score":0.9}],"units":[],"etag":"x"}"#
        )
        #expect(snapshot.lessons.map(\.id) == ["u1_l1"])
    }

    @Test("An item without an id or status is a decode failure, not a silent blank")
    func requiredItemFields() {
        #expect(throws: DecodingError.self) {
            _ = try decode(#"{"lessons":[{"status":"completed"}]}"#)
        }
        #expect(throws: DecodingError.self) {
            _ = try decode(#"{"lessons":[{"id":"u1_l1"}]}"#)
        }
    }

    @Test("ProgressPutItem encodes exactly {id, type, status} with the server's raw values")
    func putItemEncoding() throws {
        let data = try JSONEncoder().encode(ProgressPutItem(id: "unit_1", type: .unit, status: .mastered))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["id", "type", "status"])
        #expect(json["id"] as? String == "unit_1")
        #expect(json["type"] as? String == "unit")
        #expect(json["status"] as? String == "mastered")
    }

    @Test("Wire enums match the server's schema strings")
    func rawValues() {
        #expect(ProgressItemType.lesson.rawValue == "lesson")
        #expect(ProgressItemType.unit.rawValue == "unit")
        #expect(ProgressStatus.completed.rawValue == "completed")
        #expect(ProgressStatus.mastered.rawValue == "mastered")
    }
}
