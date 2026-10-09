// Serial, generation-ordered saving in front of a `TabulaRepository` (PHASE2_PLAN §0.4 "debounced, serial").
// `AppModel` numbers every accepted mutation (generation) and asks this actor to save the latest snapshot after a
// short debounce. The actor never writes an older generation after a newer one, whatever order the save tasks
// arrive in. Linux-tested with `InMemoryRepository`.
import Foundation
import TimetableCore

/// Outcome of one save request.
public enum SaveOutcome: Equatable, Sendable {
    /// Written.
    case saved(generation: Int)
    /// Skipped: a newer (or the same) generation was already written.
    case skippedStale(generation: Int, lastSaved: Int)
    /// The store is read-only (written by a newer app version); nothing was written.
    case readOnly
    /// Writing failed; the previous state on disk is intact.
    case failed(String)
}

/// Loads once and saves serially.
public actor PersistenceController {
    private let repository: any TabulaRepository
    /// Highest generation written so far (`-1` before the first save).
    public private(set) var lastSavedGeneration = -1
    /// Number of successful writes (tests, debug screen).
    public private(set) var writeCount = 0

    /// Creates a controller for `repository`.
    public init(repository: any TabulaRepository) {
        self.repository = repository
    }

    /// Loads the stored database and maps the result (banners, read-only, first launch, failures).
    public func load() async -> StoreLoadOutcome {
        do {
            let database = try await repository.load()
            var report: LoadReport?
            if let file = repository as? FileRepository { report = await file.lastLoadReport }
            return .loaded(database, report: report)
        } catch {
            return .failed(error)
        }
    }

    /// Saves `database` as `generation`. Writes happen strictly one after another in request order; a request
    /// that is older than (or equal to) one already requested is skipped, and a request superseded by a newer
    /// one while it waited for the previous write is skipped too (the newer one writes the newer data).
    public func save(_ database: TabulaDatabase, generation: Int) async -> SaveOutcome {
        guard generation > lastRequestedGeneration else {
            return .skippedStale(generation: generation, lastSaved: lastSavedGeneration)
        }
        lastRequestedGeneration = generation
        let previous = tail
        let task = Task { await self.write(database, generation: generation, after: previous) }
        tail = task
        return await task.value
    }

    private var lastRequestedGeneration = -1
    private var tail: Task<SaveOutcome, Never>?

    private func write(_ database: TabulaDatabase, generation: Int, after previous: Task<SaveOutcome, Never>?) async -> SaveOutcome {
        _ = await previous?.value
        guard generation == lastRequestedGeneration else {
            return .skippedStale(generation: generation, lastSaved: lastSavedGeneration)
        }
        do {
            try await repository.save(database)
            lastSavedGeneration = generation
            writeCount += 1
            return .saved(generation: generation)
        } catch RepositoryError.readOnly(_) {
            return .readOnly
        } catch {
            return .failed(String(describing: error))
        }
    }
}
