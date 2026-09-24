import Foundation
import CurriculumFeature
import NetworkingKit

/// Keeps lesson completion and unit mastery in step with the server
/// (`/api/progress/:sessionId`). Both directions are forward-only: a pull only
/// ever adds to the local store, and a push sends the whole local snapshot,
/// which the server folds in without downgrading anything. In-progress
/// lessons never sync — their resume pointers are device-local conversations.
///
/// Best-effort by design: every failure is swallowed. Progress lives on the
/// device first; the next pull or push catches up.
@MainActor
final class CurriculumProgressSync {
    private let progress: CurriculumProgressStore
    private let remote: ProgressSyncing
    /// Read at send time and re-checked when a reply lands: "Delete my data"
    /// rotates the id (and wipes the store) under a live shell, and nothing
    /// from the old identity may be merged into — or pushed under — the new one.
    private let sessionId: () throws -> String
    private let debounce: Duration
    /// A pull within this long of the last successful one is skipped, so the
    /// launch pull and the shell's pull on mount don't both hit the server.
    private let pullInterval: Duration
    private let isEnabled: Bool
    private let clock = ContinuousClock()

    private var pendingPush: Task<Void, Never>?
    private var pullInFlight: Task<Void, Never>?
    private var lastPull: ContinuousClock.Instant?
    /// What the server is known to hold for a session id. A push of the same
    /// snapshot is skipped — `revision` also moves when a lesson is merely
    /// opened, which changes nothing the server stores.
    private var synced: (sessionId: String, snapshot: CurriculumProgressStore.Snapshot)?

    init(
        progress: CurriculumProgressStore,
        remote: ProgressSyncing,
        sessionId: @escaping () throws -> String,
        debounce: Duration = .seconds(2),
        pullInterval: Duration = .seconds(60),
        isEnabled: Bool = true
    ) {
        self.progress = progress
        self.remote = remote
        self.sessionId = sessionId
        self.debounce = debounce
        self.pullInterval = pullInterval
        self.isEnabled = isEnabled
    }

    /// Fetch the server's progress, merge it in, and — only if this device
    /// holds something the server doesn't — push the merged snapshot once.
    /// Concurrent callers share one in-flight pull.
    func pullOnLaunch() async {
        guard isEnabled else { return }
        if let pullInFlight {
            await pullInFlight.value
            return
        }
        if let lastPull, lastPull.duration(to: clock.now) < pullInterval { return }
        let task = Task { await self.pull() }
        pullInFlight = task
        await task.value
        pullInFlight = nil
    }

    /// Push the snapshot after `debounce`; a newer call restarts the wait, so
    /// a burst of changes goes out as one request.
    func pushSoon() {
        guard isEnabled else { return }
        pendingPush?.cancel()
        pendingPush = Task { [debounce] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            await self.pushCurrentSnapshot()
        }
    }

    /// Stop any scheduled or running request and forget what the server was
    /// known to hold. Called before "Delete my data" erases the server
    /// session (so a late PUT can't recreate its progress) and around the
    /// local reset (so the wiped store is never pushed); the next identity's
    /// first pull and push both go out.
    func cancelPending() {
        pendingPush?.cancel()
        pendingPush = nil
        pullInFlight?.cancel()
        synced = nil
        lastPull = nil
    }

    // MARK: - Internals

    private func pull() async {
        guard let sid = try? sessionId(),
              let remoteSnapshot = try? await remote.fetchProgress(sessionId: sid),
              (try? sessionId()) == sid
        else { return }
        lastPull = clock.now

        let remoteState = Self.remoteState(remoteSnapshot)
        progress.merge(
            completed: remoteState.completed.sorted(),
            mastered: remoteState.mastered.sorted(),
            remoteVersion: remoteSnapshot.curriculumVersion
        )

        // Compared against the server's ids as sent: when a curriculum
        // migration renamed some, the device reads as ahead and one push
        // brings the server onto the current ids.
        let local = progress.snapshot()
        let serverHasEverything = local.completed.isSubset(of: remoteState.completed)
            && local.mastered.isSubset(of: remoteState.mastered)
        if serverHasEverything {
            synced = (sid, local)
        } else {
            await push(local, sessionId: sid)
        }
    }

    private func pushCurrentSnapshot() async {
        guard let sid = try? sessionId() else { return }
        await push(progress.snapshot(), sessionId: sid)
    }

    private func push(_ snapshot: CurriculumProgressStore.Snapshot, sessionId sid: String) async {
        if let synced, synced.sessionId == sid, synced.snapshot == snapshot { return }
        let items = Self.items(from: snapshot)
        guard !items.isEmpty else { return }
        do {
            _ = try await remote.putProgress(
                sessionId: sid,
                curriculumVersion: snapshot.curriculumVersion,
                items: items
            )
            if (try? sessionId()) == sid {
                synced = (sid, snapshot)
            }
        } catch {
            // Best-effort: the next pull re-sends whatever the server lacks.
        }
    }

    /// Server items → the sets `merge` takes. A mastered lesson still counts
    /// as completed; any status this build doesn't know is ignored.
    ///
    /// No completion dates: a row's `updatedAt` is when the server wrote it,
    /// and for a row this device uploaded (every pre-2.3.0 lesson, on the
    /// first sync) that is the upload time. Merged lessons stay undated, like
    /// those lessons are on the device that finished them, so they never
    /// count toward the weekly plan.
    static func remoteState(_ dto: ProgressSnapshotDTO) -> (completed: Set<String>, mastered: Set<String>) {
        let lessonStatuses: Set<String> = [ProgressStatus.completed.rawValue, ProgressStatus.mastered.rawValue]
        let lessons = dto.lessons.filter { lessonStatuses.contains($0.status) }
        let units = dto.units.filter { $0.status == ProgressStatus.mastered.rawValue }
        return (Set(lessons.map(\.id)), Set(units.map(\.id)))
    }

    /// The whole snapshot as PUT items, sorted so a request body is stable.
    /// Ids the current curriculum doesn't know are sent too: they came from
    /// another curriculum version and must round-trip, not be dropped.
    static func items(from snapshot: CurriculumProgressStore.Snapshot) -> [ProgressPutItem] {
        snapshot.completed.sorted().map { ProgressPutItem(id: $0, type: .lesson, status: .completed) }
            + snapshot.mastered.sorted().map { ProgressPutItem(id: $0, type: .unit, status: .mastered) }
    }
}
