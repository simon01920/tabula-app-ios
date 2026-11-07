import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// QA fix pass after Phase 10: `ReminderEngine.run` never interleaves two runs (calls during a run are coalesced).

/// Counts run starts (`AlarmClient.authorization()`, the first call of every run) and run ends (the one state save of
/// a run without alarms), and the most runs that were in progress at once.
private final class EngineRunRecorder: @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var startCount = 0
    private var finishCount = 0
    private var maxInFlightCount = 0
    private var savedStates: [AppliedReminderState] = []

    var starts: Int { lock.withLock { startCount } }
    var finishes: Int { lock.withLock { finishCount } }
    var maxInFlight: Int { lock.withLock { maxInFlightCount } }
    var lastSaved: AppliedReminderState? { lock.withLock { savedStates.last } }

    func start() {
        lock.withLock {
            startCount += 1
            maxInFlightCount = max(maxInFlightCount, startCount - finishCount)
        }
    }

    func finish(_ state: AppliedReminderState) {
        lock.withLock {
            finishCount += 1
            savedStates.append(state)
        }
    }
}

/// Holds every caller until `open()`.
private actor RunGate {
    private var isOpen = false
    private var blocked: [CheckedContinuation<Void, Never>] = []

    var blockedCount: Int { blocked.count }

    func pass() async {
        if isOpen { return }
        await withCheckedContinuation { blocked.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = blocked
        blocked = []
        for continuation in waiting { continuation.resume() }
    }
}

/// `InMemoryAlarmClient` whose `authorization()` records a run start and waits at the gate.
private struct GatedAlarmClient: AlarmClient {
    let base: InMemoryAlarmClient
    let recorder: EngineRunRecorder
    let gate: RunGate

    func authorization() async -> AlarmAuthorization {
        recorder.start()
        await gate.pass()
        return await base.authorization()
    }

    func requestAuthorization() async -> AlarmAuthorization { await base.requestAuthorization() }
    func scheduledAlarms() async -> [ScheduledAlarmInfo]? { await base.scheduledAlarms() }
    func schedule(_ alarm: AlarmSpec) async -> AlarmScheduleOutcome { await base.schedule(alarm) }
    func cancel(id: UUID) async { await base.cancel(id: id) }
    func authorizationUpdates() -> AsyncStream<AlarmAuthorization> { base.authorizationUpdates() }
}

private final class RecordingStateStore: ReminderStateStore, @unchecked Sendable {
    let recorder: EngineRunRecorder

    init(recorder: EngineRunRecorder) {
        self.recorder = recorder
    }

    func load() -> AppliedReminderState? { recorder.lastSaved }
    func save(_ state: AppliedReminderState) { recorder.finish(state) }
}

@MainActor
@Suite("Phase 10 QA fix: reminder engine runs never interleave")
struct ReminderEngineReentrancyTests {
    /// Yields the main actor until `condition` holds (bounded, so a broken guard fails instead of hanging).
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }

    @Test func callsDuringARunAreCoalescedIntoOneMoreRunWithTheNewestInput() async throws {
        let recorder = EngineRunRecorder()
        let gate = RunGate()
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(),
                                    alarms: GatedAlarmClient(base: InMemoryAlarmClient(), recorder: recorder, gate: gate),
                                    store: RecordingStateStore(recorder: recorder))
        let database = Fixture.database(alarmsOn: false)
        let first = Task { await engine.run(Fixture.input(database, now: Fixture.now)) }
        try #require(await waitUntil { await gate.blockedCount == 1 })
        #expect(engine.isRunning)

        let second = Task { await engine.run(Fixture.input(database, now: Fixture.now.addingTimeInterval(60))) }
        let third = Task { await engine.run(Fixture.input(database, now: Fixture.now.addingTimeInterval(120))) }
        try #require(await waitUntil { engine.waitingRunCount == 2 })
        // Neither waiting call started a run of its own.
        #expect(recorder.starts == 1)
        #expect(await gate.blockedCount == 1)

        await gate.open()
        let results = [await first.value, await second.value, await third.value]

        // The first run plus ONE coalesced run with the newest input; never two at once.
        #expect(recorder.starts == 2)
        #expect(recorder.finishes == 2)
        #expect(recorder.maxInFlight == 1)
        #expect(engine.state.lastRunAt == Fixture.now.addingTimeInterval(120))
        #expect(recorder.lastSaved == engine.state)
        // Every caller gets the result of the last run.
        #expect(results[0] == results[1])
        #expect(results[1] == results[2])
        #expect(!engine.isRunning)
        #expect(engine.waitingRunCount == 0)

        // Afterwards a call runs at once again.
        _ = await engine.run(Fixture.input(database, now: Fixture.now.addingTimeInterval(180)))
        #expect(recorder.starts == 3)
        #expect(recorder.maxInFlight == 1)
    }
}
