// Orphan cleanup scheduling for attachment files (stage B3, PHASE3_PLAN §0.7 "cleaned up after deletion and at
// launch"). Installed once in `AppServices.init` (after the reminder coordinator attached) by chaining onto
// `AppModel.onChange`: the previous handler always runs first and unchanged.
//
//   .loaded → cleanup shortly after launch        .data → debounced cleanup after every accepted change
//                                                          (a deleted task / removed attachment was saved)
//
// The rules live in TimetableUI (`AttachmentStore.swift`): live refs are never touched, orphans are deleted only after
// the grace period and when no open editor protects them. Cleanup is skipped entirely unless the database loaded
// and is writable, while the last save failed (the in-memory state is not on disk), and for the rest of a session
// whose load recovered from a backup or discarded a write.
import Foundation
import TimetableCore
import TimetableUI

@MainActor
enum AttachmentMaintenance {
    /// Chains the cleanup onto `model.onChange`. Call once, after every other `onChange` owner attached.
    static func install(on model: AppModel) {
        let runner = AttachmentCleanupRunner(model: model)
        let previous = model.onChange
        model.onChange = { change in
            previous?(change)
            runner.handle(change)
        }
    }
}

/// Debounced, single-flight cleanup runs.
@MainActor
final class AttachmentCleanupRunner {
    private weak var model: AppModel?
    private var pending: Task<Void, Never>?
    private var recoveredThisSession = false
    /// Last report (developer diagnostics).
    private(set) var lastReport: AttachmentCleanupReport?

    init(model: AppModel) {
        self.model = model
    }

    func handle(_ change: AppModelChange) {
        switch change {
        case .loaded:
            if let banners = model?.banners,
               banners.contains(.restoredFromBackup) || banners.contains(.discardedIncompleteWrite) {
                recoveredThisSession = true
            }
            schedule(after: .seconds(2))
        case .data:
            schedule(after: .seconds(3))
        case .environment:
            break
        }
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private func run() async {
        guard let model else { return }
        var lastSaveFailed = model.banners.contains(.saveFailed)
        if case .failed? = model.lastSaveOutcome { lastSaveFailed = true }
        guard AttachmentCleanupGate.mayRun(databaseLoaded: model.database != nil && !model.isLoading,
                                           isReadOnly: model.isReadOnly, hasProblem: model.problem != nil,
                                           recoveredThisSession: recoveredThisSession, lastSaveFailed: lastSaveFailed),
              let database = model.database else { return }
        // The live set is taken from the snapshot at this moment; anything added later is younger than the grace
        // period or protected by its open editor, so it cannot be deleted by this run.
        let live = AttachmentReferences.liveIDs(in: database)
        lastReport = await model.environment.attachments.cleanUpOrphans(liveIDs: live)
    }
}
