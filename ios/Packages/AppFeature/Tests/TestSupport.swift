import Foundation
import CurriculumFeature
import NetworkingKit
import SettingsFeature

/// In-memory `PreferenceStore`, so progress stores in these tests never
/// touch the host's defaults.
final class InMemoryPreferenceStore: PreferenceStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func string(for key: String) -> String? { storage[key] }
    func set(_ value: String?, for key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

/// A private, emptied `UserDefaults` suite per test.
func freshDefaults(_ name: String) -> UserDefaults {
    let suite = "appfeature.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

struct StubFailure: Error {}

/// Records every call; answers with `remote` or throws the configured error.
actor StubProgressRemote: ProgressSyncing {
    struct Put: Equatable {
        let sessionId: String
        let curriculumVersion: Int
        let items: [ProgressPutItem]
    }

    private(set) var fetches: [String] = []
    private(set) var puts: [Put] = []
    private var remote: ProgressSnapshotDTO
    private var fetchFails: Bool
    private var putFails: Bool

    init(
        remote: ProgressSnapshotDTO = ProgressSnapshotDTO(curriculumVersion: nil),
        fetchFails: Bool = false,
        putFails: Bool = false
    ) {
        self.remote = remote
        self.fetchFails = fetchFails
        self.putFails = putFails
    }

    func fetchProgress(sessionId: String) async throws -> ProgressSnapshotDTO {
        fetches.append(sessionId)
        if fetchFails { throw StubFailure() }
        return remote
    }

    func putProgress(
        sessionId: String,
        curriculumVersion: Int,
        items: [ProgressPutItem]
    ) async throws -> ProgressSnapshotDTO {
        puts.append(Put(sessionId: sessionId, curriculumVersion: curriculumVersion, items: items))
        if putFails { throw StubFailure() }
        return remote
    }
}

extension ProgressItemDTO {
    static func lesson(_ id: String, _ status: String = "completed", at: Date? = nil) -> ProgressItemDTO {
        ProgressItemDTO(id: id, status: status, updatedAt: at)
    }
}
