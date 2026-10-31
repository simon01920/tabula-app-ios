#if TABULA_CLOUDKIT
// iCloud sync adapter (Phase 6 S1, PHASE6_PLAN decisions 1–4). Compiled only with TABULA_CLOUDKIT, which project.yml
// defines only when TABULA_PAID_ACCOUNT = 1: `CKContainer` traps without the CloudKit entitlement (RISKS #34).
// The mapping, ledger and first-sync logic are pure and Linux-tested (TimetableCore/Sync/CloudSync.swift); this file
// only moves `CloudRecord`s in and out of `CKSyncEngine`.
//
// Flow
//   start      CKSyncEngine on the private database with the persisted state (`cloudsync.json`, next to the store).
//   first sync Until `ledger.initialSyncDone`, fetched records are buffered and the engine state is held in memory
//              (a kill before the user's choice simply fetches again). When both sides hold data the Settings/shell
//              alert asks Merge / Keep This iPhone / Use iCloud; otherwise it merges.
//   fetch      records → `CloudRecordBatch` → `model.apply(.mergeRemote, origin: .sync)` (reminders, widgets, Live
//              Activities follow through `onChange`) → store flushed → ledger notes the server version.
//   send       after every change the ledger diff (payload hash ≠ server hash) adds `.saveRecord` pending changes; the
//              batch is built from the current database. serverRecordChanged → merge the server copy, which makes the
//              record pending again with the new change tag; zoneNotFound / unknownItem → re-create and re-send.
//   state      `.stateUpdate` is written only after the store is flushed (data before acknowledgement).
//   account    sign-out / switch / sign-in: local data stays (never dropped silently), the ledger is reset, so the
//              next fetch is a first sync again.
//   purged     zone deleted (Settings › iCloud › Manage, encrypted data reset): Apple says not to re-send; local data
//              stays and iCloud sync is switched off with a notice. Turning it on again uploads everything.
// Push: CKSyncEngine creates its own CKDatabaseSubscription and handles the silent pushes; the app only needs the
// entitlements + UIBackgroundModes remote-notification (CKSyncEngine docs). No registerForRemoteNotifications call.
// APIs (iOS 27 SDK CloudKit.swiftinterface, docs/ENVIRONMENT.md §36): CKSyncEngine (iOS 17), .Configuration,
//   .Event, .State.Serialization (Codable), .PendingRecordZoneChange, .PendingDatabaseChange,
//   .RecordZoneChangeBatch(pendingChanges:recordProvider:), CKSyncEngineDelegate, CKRecord.encodeSystemFields(with:),
//   CKError.serverRecord, CKContainer.accountStatus().
import CloudKit
import Foundation
import Observation
import TimetableCore
import TimetableUI

@MainActor
@Observable
final class CloudSyncController: CKSyncEngineDelegate {
    /// The status line (Settings › iCloud).
    private(set) var status: CloudSyncStatus
    /// `true` while the first-sync choice waits for the user (both this device and iCloud hold data).
    private(set) var isAwaitingFirstSyncChoice = false

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let ledgerURL: URL
    @ObservationIgnored private var ledger: CloudSyncLedger
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var firstSyncRecords: [CloudRecord] = []
    @ObservationIgnored private var firstSyncTags: [String: Data] = [:]
    @ObservationIgnored private var firstSyncUnknown: [String] = []
    /// Records whose server copy this build cannot merge (newer app version): never re-sent this session (no conflict loop).
    @ObservationIgnored private var unmergeable: Set<String> = []
    @ObservationIgnored private var heldState: CKSyncEngine.State.Serialization?
    @ObservationIgnored private var fetchFailed = false
    /// A merge could not be saved, or newer-version records were skipped: stop saving the engine state, so the next
    /// launch fetches again from the last saved state (after an app update the skipped records then apply).
    @ObservationIgnored private var stateBlocked = false
    @ObservationIgnored private var operationProblem: CloudSyncStatus?
    @ObservationIgnored private var oversized = false
    @ObservationIgnored private var newerDataSeen = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    nonisolated private static let zoneID = CKRecordZone.ID(zoneName: CloudSyncSchema.zoneName)

    /// The controller for the on-disk store; `nil` for `-TabulaSeed` runs (developer seed data never reaches iCloud).
    /// The onboarding "Just look around" sample timetable is ordinary data: it syncs, can trigger the first-sync alert
    /// on a second device that also has data, and its removal syncs as tombstones.
    static func install(on model: AppModel) -> CloudSyncController? {
        guard case .file(let directory, _) = model.environment.dataSource else { return nil }
        let controller = CloudSyncController(model: model, ledgerURL: directory.appendingPathComponent("cloudsync.json"))
        let previous = model.onChange
        model.onChange = { change in
            previous?(change)
            controller.modelChanged()
        }
        return controller
    }

    private init(model: AppModel, ledgerURL: URL) {
        self.model = model
        self.ledgerURL = ledgerURL
        ledger = CloudSyncLedger.load(from: ledgerURL)
        status = ledger.lastSyncedAt.map(CloudSyncStatus.synced) ?? .notSyncedYet
    }

    // MARK: Lifecycle

    private var syncAllowed: Bool {
        !model.isLoading && model.problem == nil && !model.isReadOnly && model.settings.syncEnabled
    }

    /// After load and every change: start/stop with the switch, and queue what changed.
    func modelChanged() {
        guard !model.isLoading else { return }
        if syncAllowed {
            if engine == nil { start() }
            scheduleScan()
        } else if engine != nil || status != .off {
            stop()
        }
    }

    private func start() {
        if status == .off || status == .iCloudDataDeleted { status = .notSyncedYet }
        let state = ledger.engineState.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let engine = CKSyncEngine(CKSyncEngine.Configuration(database: CKContainer.default().privateCloudDatabase,
                                                             stateSerialization: state, delegate: self))
        self.engine = engine
        Task {
            if let account = try? await CKContainer.default().accountStatus(), account == .noAccount || account == .restricted {
                status = .noAccount
            }
            if !ledger.initialSyncDone { try? await engine.fetchChanges() }
        }
    }

    private func stop() {
        let old = engine
        engine = nil
        scanTask?.cancel()
        Task { await old?.cancelOperations() }
        if status != .iCloudDataDeleted { status = .off }
    }

    // MARK: First sync

    /// The user's answer to the first-sync alert.
    func choose(_ choice: FirstSyncChoice) {
        guard isAwaitingFirstSyncChoice else { return }
        isAwaitingFirstSyncChoice = false
        Task { await completeFirstSync(choice) }
    }

    private func finishFirstFetch() async {
        guard !isAwaitingFirstSyncChoice else { return }
        guard !fetchFailed else { return }   // incomplete: keep buffering, the engine fetches again
        let remote = CloudRecordBatch(firstSyncRecords).database
        if CloudFirstSync.needsChoice(local: model.database, remote: remote) {
            isAwaitingFirstSyncChoice = true
        } else {
            await completeFirstSync(.merge)
        }
    }

    private func completeFirstSync(_ choice: FirstSyncChoice) async {
        guard await apply(firstSyncRecords, unknown: firstSyncUnknown, tags: firstSyncTags, choice: choice) != nil else { return }
        firstSyncRecords = []
        firstSyncTags = [:]
        firstSyncUnknown = []
        ledger.initialSyncDone = true
        if let heldState, !stateBlocked { ledger.engineState = try? JSONEncoder().encode(heldState) }
        heldState = nil
        saveLedger()
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        scheduleScan()
        finishOperation()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            if ledger.initialSyncDone { await persist(update.stateSerialization) } else { heldState = update.stateSerialization }
        case .accountChange(let change):
            accountChanged(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) { zoneDeleted() }
        case .fetchedRecordZoneChanges(let changes):
            await received(changes.modifications.map(\.record))
            // A CKRecord deletion is not a Tabula delete (tombstones are records): forget it, so ours is sent again.
            for deletion in changes.deletions where deletion.recordID.zoneID == Self.zoneID {
                ledger.serverHashes[deletion.recordID.recordName] = nil
                ledger.systemFields[deletion.recordID.recordName] = nil
            }
        case .sentRecordZoneChanges(let sent):
            await handleSent(sent)
        case .sentDatabaseChanges(let sent):
            if sent.failedZoneSaves.contains(where: { $0.error.code == .quotaExceeded }) { operationProblem = .quotaExceeded }
        case .willFetchChanges, .willSendChanges:
            fetchFailed = false
            operationProblem = nil
            if case .synced = status { status = .syncing } else if status == .notSyncedYet { status = .syncing }
        case .didFetchRecordZoneChanges(let done):
            if done.error != nil { fetchFailed = true }
        case .didFetchChanges:
            if ledger.initialSyncDone { finishOperation() } else { await finishFirstFetch() }
        case .didSendChanges:
            finishOperation()
        case .willFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine, ledger.initialSyncDone, let database = model.database else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let records = (try? database.cloudRecords()) ?? []
        let byName = Dictionary(records.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let tags = ledger.systemFields
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let record = byName[id.recordName], !record.isTooLarge else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
            return Self.ckRecord(record, systemFields: tags[id.recordName])
        }
    }

    // MARK: Fetch

    /// Applies fetched (or conflicting server) records; returns the names that could not be applied.
    @discardableResult
    private func received(_ ckRecords: [CKRecord]) async -> Set<String> {
        var records: [CloudRecord] = []
        var unknown: [String] = []
        var tags: [String: Data] = [:]
        for ckRecord in ckRecords where ckRecord.recordID.zoneID == Self.zoneID {
            guard let record = Self.cloudRecord(from: ckRecord) else { unknown.append(ckRecord.recordID.recordName); continue }
            records.append(record)
            tags[record.name] = Self.systemFields(of: ckRecord)
        }
        guard ledger.initialSyncDone else {
            firstSyncRecords += records
            firstSyncUnknown += unknown
            firstSyncTags.merge(tags) { _, new in new }
            return []
        }
        return await apply(records, unknown: unknown, tags: tags, choice: .merge) ?? []
    }

    /// Merges `records` into the store, saves it, then notes the server version. Returns the rejected names; `nil`
    /// when nothing could be applied.
    private func apply(_ records: [CloudRecord], unknown: [String], tags: [String: Data],
                       choice: FirstSyncChoice) async -> Set<String>? {
        let batch = CloudRecordBatch(records, unknownTypeNames: unknown)
        if batch.holdsBackState {
            newerDataSeen = true
            stateBlocked = true   // never acknowledge past records this build skipped
        }
        let rejected = Set(batch.rejected.keys)
        guard !batch.hashes.isEmpty else { return rejected }
        guard case .applied = model.apply(.mergeRemote(batch.database, choice: choice), origin: .sync),
              await model.flushForSync() else {
            stateBlocked = true
            return nil
        }
        for (name, hash) in batch.hashes {
            ledger.serverHashes[name] = hash
            ledger.systemFields[name] = tags[name]
        }
        saveLedger()
        return rejected
    }

    // MARK: Send

    private func handleSent(_ event: CKSyncEngine.Event.SentRecordZoneChanges) async {
        // Acknowledge only what is on disk: after a kill inside the save debounce, older data would otherwise be
        // pending against a ledger that names the newer server copy, and be sent over it.
        let persisted = await model.flushForSync()
        for record in event.savedRecords where persisted && record.recordID.zoneID == Self.zoneID {
            let name = record.recordID.recordName
            if let payload = record[CloudSyncSchema.payloadField] as? Data {
                ledger.serverHashes[name] = TabulaSHA256.hexDigest(payload)
            }
            ledger.systemFields[name] = Self.systemFields(of: record)
        }
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var conflicts: [CKRecord] = []
        for failure in event.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Merge the server copy; the record is then pending again with the server's change tag.
                if let server = failure.error.serverRecord { conflicts.append(server) }
            case .userDeletedZone:
                zoneDeleted()   // like a purge: keep local data, do not re-send
                return
            case .zoneNotFound, .unknownItem:
                if failure.error.code == .zoneNotFound {
                    engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                }
                ledger.serverHashes[id.recordName] = nil
                ledger.systemFields[id.recordName] = nil
                retry.append(.saveRecord(id))
            case .quotaExceeded:
                operationProblem = .quotaExceeded
            default:
                break   // transient errors are retried by the engine (CKSyncEngine docs, "Error Handling")
            }
        }
        saveLedger()
        if !conflicts.isEmpty { unmergeable.formUnion(await received(conflicts)) }
        if !retry.isEmpty { engine?.state.add(pendingRecordZoneChanges: retry) }
        scheduleScan()
    }

    /// Queues every record whose payload is not the server's (off the main actor; the database is a value).
    private func scheduleScan() {
        guard ledger.initialSyncDone, let engine, let database = model.database else { return }
        let ledger = self.ledger, skipping = unmergeable
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let pending = await Task.detached(priority: .utility) { ledger.pending((try? database.cloudRecords()) ?? [], skipping: skipping) }.value
            guard !Task.isCancelled, let self, engine === self.engine else { return }
            oversized = pending.contains(where: \.isTooLarge)
            let queued = Set(engine.state.pendingRecordZoneChanges)
            let changes = pending.filter { !$0.isTooLarge }
                .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0.name, zoneID: Self.zoneID)) }
                .filter { !queued.contains($0) }
            if !changes.isEmpty { engine.state.add(pendingRecordZoneChanges: changes) }
            if oversized { status = .itemsTooLarge }
        }
    }

    // MARK: Account, zone, state

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) {
        // The ledger described the previous account's server; the engine resets its own state (CKSyncEngine docs).
        resetLedger()
        switch change {
        case .signOut: status = .noAccount
        case .signIn, .switchAccounts: status = .notSyncedYet
        @unknown default: break
        }
    }

    private func zoneDeleted() {
        resetLedger()
        status = .iCloudDataDeleted
        model.apply(.settings { $0.syncEnabled = false })   // stops the engine through onChange
    }

    private func resetLedger() {
        ledger = CloudSyncLedger()
        firstSyncRecords = []
        firstSyncTags = [:]
        firstSyncUnknown = []
        unmergeable = []
        heldState = nil
        isAwaitingFirstSyncChoice = false
        saveLedger()
    }

    private func persist(_ state: CKSyncEngine.State.Serialization) async {
        guard !stateBlocked else { return }
        guard await model.flushForSync() else {
            stateBlocked = true
            return
        }
        ledger.engineState = try? JSONEncoder().encode(state)
        saveLedger()
    }

    private func finishOperation() {
        let now = model.now
        if let problem = operationProblem ?? (oversized ? .itemsTooLarge : nil) ?? (newerDataSeen ? .newerAppVersion : nil) {
            status = problem
        } else {
            ledger.lastSyncedAt = now
            saveLedger()
            status = .synced(now)
        }
    }

    private func saveLedger() {
        try? ledger.save(to: ledgerURL)   // shortcut: a failed write only costs a re-fetch / re-send next launch
    }

    // MARK: CKRecord <-> CloudRecord

    nonisolated private static func ckRecord(_ record: CloudRecord, systemFields: Data?) -> CKRecord {
        let ckRecord = systemFields.flatMap(decodeSystemFields)
            ?? CKRecord(recordType: record.type.rawValue, recordID: CKRecord.ID(recordName: record.name, zoneID: zoneID))
        ckRecord[CloudSyncSchema.payloadField] = record.payload
        ckRecord[CloudSyncSchema.schemaVersionField] = Int64(record.schemaVersion)
        return ckRecord
    }

    /// `nil` for record types this build does not know (a newer app version).
    nonisolated private static func cloudRecord(from ckRecord: CKRecord) -> CloudRecord? {
        guard let type = EntityType(rawValue: ckRecord.recordType) else { return nil }
        let payload = ckRecord[CloudSyncSchema.payloadField] as? Data ?? Data()
        let version = ckRecord[CloudSyncSchema.schemaVersionField] as? Int64 ?? 0
        return CloudRecord(type: type, name: ckRecord.recordID.recordName, payload: payload, schemaVersion: Int(version))
    }

    nonisolated private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    nonisolated private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
#endif
