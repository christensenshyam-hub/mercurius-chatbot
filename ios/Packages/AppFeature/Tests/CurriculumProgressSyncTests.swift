import Foundation
import Testing
@testable import AppFeature
import CurriculumFeature
import NetworkingKit

@Suite("CurriculumProgressSync")
@MainActor
struct CurriculumProgressSyncTests {

    private func makeStore() -> CurriculumProgressStore {
        CurriculumProgressStore(preferences: InMemoryPreferenceStore())
    }

    private func makeSync(
        _ store: CurriculumProgressStore,
        _ remote: StubProgressRemote,
        sessionId: @escaping () throws -> String = { "sid-1" },
        debounce: Duration = .milliseconds(40),
        isEnabled: Bool = true
    ) -> CurriculumProgressSync {
        CurriculumProgressSync(
            progress: store, remote: remote, sessionId: sessionId,
            debounce: debounce, isEnabled: isEnabled
        )
    }

    /// Long enough for a 40 ms debounce plus the stub round trip.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    @Test("Pull merges the server's lessons and units; a device holding nothing extra doesn't PUT")
    func pullMerges() async throws {
        let at = Date(timeIntervalSince1970: 1_780_000_000)
        let remote = StubProgressRemote(remote: ProgressSnapshotDTO(
            curriculumVersion: MercuriusCurriculum.version,
            lessons: [.lesson("u1_l1", at: at), .lesson("u1_l2", "mastered"), .lesson("u1_l3", "someday")],
            units: [.lesson("unit_1", "mastered"), .lesson("unit_2", "completed")]
        ))
        let store = makeStore()
        let sync = makeSync(store, remote)

        await sync.pullOnLaunch()

        #expect(store.isCompleted("u1_l1"))
        #expect(store.isCompleted("u1_l2"), "a mastered lesson still counts as completed")
        #expect(!store.isCompleted("u1_l3"), "unknown statuses are ignored")
        #expect(store.isUnitMastered("unit_1"))
        #expect(!store.isUnitMastered("unit_2"), "only a mastered unit is mastery")
        #expect(store.completedAt("u1_l1") == at)
        #expect(await remote.fetches == ["sid-1"])
        #expect(await remote.puts.isEmpty)
    }

    @Test("When the device holds lessons the server lacks, the pull PUTs the merged snapshot exactly once")
    func localAheadPutsOnce() async throws {
        let remote = StubProgressRemote(remote: ProgressSnapshotDTO(
            curriculumVersion: MercuriusCurriculum.version,
            lessons: [.lesson("u1_l2")]
        ))
        let store = makeStore()
        store.markCompleted("u1_l1")
        store.markUnitMastered("unit_3")
        let sync = makeSync(store, remote)

        await sync.pullOnLaunch()
        // The merge moved `revision`, so the host would schedule a push too —
        // it must not re-send what the pull just sent.
        sync.pushSoon()
        try await settle()

        let puts = await remote.puts
        #expect(puts.count == 1)
        #expect(puts.first?.sessionId == "sid-1")
        #expect(puts.first?.curriculumVersion == MercuriusCurriculum.version)
        #expect(puts.first?.items == [
            ProgressPutItem(id: "u1_l1", type: .lesson, status: .completed),
            ProgressPutItem(id: "u1_l2", type: .lesson, status: .completed),
            ProgressPutItem(id: "unit_3", type: .unit, status: .mastered),
        ])
    }

    @Test("Nothing on either side: one GET, no PUT")
    func emptyBothNoPut() async throws {
        let remote = StubProgressRemote()
        let sync = makeSync(makeStore(), remote)

        await sync.pullOnLaunch()
        sync.pushSoon()
        try await settle()

        #expect(await remote.fetches.count == 1)
        #expect(await remote.puts.isEmpty)
    }

    @Test("A burst of changes goes out as one PUT after the debounce")
    func debounceCoalesces() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        let sync = makeSync(store, remote)

        store.markCompleted("u1_l1")
        sync.pushSoon()
        store.markCompleted("u1_l2")
        sync.pushSoon()
        store.markUnitMastered("unit_1")
        sync.pushSoon()
        #expect(await remote.puts.isEmpty, "nothing is sent before the debounce elapses")
        try await settle()

        let puts = await remote.puts
        #expect(puts.count == 1)
        #expect(puts.first.map { Set($0.items.map(\.id)) } == ["u1_l1", "u1_l2", "unit_1"])
    }

    @Test("A snapshot the server already holds isn't pushed again (opening a lesson moves revision too)")
    func unchangedSnapshotSkipsPush() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        let sync = makeSync(store, remote)

        store.markCompleted("u1_l1")
        sync.pushSoon()
        try await settle()
        store.markOpened("u1_l2")
        sync.pushSoon()
        try await settle()

        #expect(await remote.puts.count == 1)
    }

    @Test("A failed GET leaves the store as it was and sends nothing")
    func fetchFailureLeavesStore() async throws {
        let remote = StubProgressRemote(fetchFails: true)
        let store = makeStore()
        store.markCompleted("u1_l1")
        let before = store.snapshot()
        let sync = makeSync(store, remote)

        await sync.pullOnLaunch()

        #expect(store.snapshot() == before)
        #expect(await remote.puts.isEmpty)
    }

    @Test("A failed PUT keeps local progress and is retried on the next change")
    func putFailureRetries() async throws {
        let remote = StubProgressRemote(putFails: true)
        let store = makeStore()
        store.markCompleted("u1_l1")
        let sync = makeSync(store, remote)

        await sync.pullOnLaunch()
        #expect(store.isCompleted("u1_l1"))
        #expect(await remote.puts.count == 1)

        sync.pushSoon()
        try await settle()
        #expect(await remote.puts.count == 2, "a failed push isn't recorded as synced")
    }

    @Test("No readable session id: no GET, no PUT")
    func sessionIdThrows() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        store.markCompleted("u1_l1")
        let sync = makeSync(store, remote, sessionId: { throw StubFailure() })

        await sync.pullOnLaunch()
        sync.pushSoon()
        try await settle()

        #expect(await remote.fetches.isEmpty)
        #expect(await remote.puts.isEmpty)
    }

    @Test("The session id is read at send time, so a rotated id is what a later push uses")
    func sessionIdReadAtSendTime() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        var current = "sid-old"
        let sync = makeSync(store, remote, sessionId: { current })

        store.markCompleted("u1_l1")
        current = "sid-new"
        sync.pushSoon()
        try await settle()

        #expect(await remote.puts.map(\.sessionId) == ["sid-new"])
    }

    @Test("cancelPending drops a scheduled push (the reset path)")
    func cancelPendingDropsPush() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        let sync = makeSync(store, remote)

        store.markCompleted("u1_l1")
        sync.pushSoon()
        sync.cancelPending()
        store.reset()
        try await settle()

        #expect(await remote.puts.isEmpty)
    }

    @Test("A second pull moments later is skipped; after cancelPending it runs again")
    func pullThrottle() async throws {
        let remote = StubProgressRemote()
        let sync = makeSync(makeStore(), remote)

        await sync.pullOnLaunch()
        await sync.pullOnLaunch()
        #expect(await remote.fetches.count == 1)

        sync.cancelPending()
        await sync.pullOnLaunch()
        #expect(await remote.fetches.count == 2)
    }

    @Test("Disabled (UI tests): no calls at all")
    func disabledIsInert() async throws {
        let remote = StubProgressRemote()
        let store = makeStore()
        store.markCompleted("u1_l1")
        let sync = makeSync(store, remote, isEnabled: false)

        await sync.pullOnLaunch()
        sync.pushSoon()
        try await settle()

        #expect(await remote.fetches.isEmpty)
        #expect(await remote.puts.isEmpty)
    }

    @Test("PUT items: lessons then units, sorted, unknown ids kept so they round-trip")
    func itemsFromSnapshot() {
        let snapshot = CurriculumProgressStore.Snapshot(
            curriculumVersion: 1,
            completed: ["u2_l1", "u1_l1", "u9_l1"],
            mastered: ["unit_2", "unit_1"]
        )
        #expect(CurriculumProgressSync.items(from: snapshot).map(\.id)
                == ["u1_l1", "u2_l1", "u9_l1", "unit_1", "unit_2"])
        #expect(CurriculumProgressSync.items(from: snapshot).map(\.type)
                == [.lesson, .lesson, .lesson, .unit, .unit])
    }
}
