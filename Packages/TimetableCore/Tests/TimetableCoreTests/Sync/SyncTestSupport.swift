import Foundation
import Testing
@testable import TimetableCore

// Helpers for the Stage 2E sync/repository tests. All names are prefixed `Sync` (one shared test module).

/// A unique scratch directory under the system temp directory (`/tmp` on Linux), removed by `remove()`.
struct SyncTempDirectory {
    let url: URL

    init(_ label: String = #function) {
        let name = "tabula-sync-\(label.filter { $0.isLetter || $0.isNumber })-\(UUID().uuidString)"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func write(_ data: Data, to name: String) throws { try data.write(to: file(name)) }

    func read(_ name: String) -> Data? { try? Data(contentsOf: file(name)) }

    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// Simulated power loss / process kill inside a file operation.
struct SyncSimulatedCrash: Error {}

/// A `FoundationFileSystem` that "crashes" (throws, doing nothing) on the n-th `replaceItem` or `write` call.
final class SyncCrashingFileSystem: RepositoryFileSystem, @unchecked Sendable {
    private let base = FoundationFileSystem()
    private let lock = NSLock()
    private var replaceCalls = 0
    private var writeCalls = 0
    private let crashOnReplace: Int?
    private let crashOnWrite: Int?

    init(crashOnReplace: Int? = nil, crashOnWrite: Int? = nil) {
        self.crashOnReplace = crashOnReplace
        self.crashOnWrite = crashOnWrite
    }

    private func count(_ keyPath: ReferenceWritableKeyPath<SyncCrashingFileSystem, Int>, limit: Int?) throws {
        lock.lock()
        defer { lock.unlock() }
        self[keyPath: keyPath] += 1
        if let limit, self[keyPath: keyPath] == limit { throw SyncSimulatedCrash() }
    }

    func contents(of url: URL) throws -> Data? { try base.contents(of: url) }

    func write(_ data: Data, to url: URL) throws {
        try count(\.writeCalls, limit: crashOnWrite)
        try base.write(data, to: url)
    }

    func replaceItem(at destination: URL, withItemAt source: URL) throws {
        try count(\.replaceCalls, limit: crashOnReplace)
        try base.replaceItem(at: destination, withItemAt: source)
    }

    /// Counted as a write (it creates the backup's temporary file).
    func linkItem(at source: URL, to destination: URL) throws {
        try count(\.writeCalls, limit: crashOnWrite)
        try base.linkItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
}

enum SyncFixture {
    static let t0 = Fixture.now

    /// `t0` + `millis`.
    static func at(_ millis: Int64) -> Date { Date(timeIntervalSince1970: t0.timeIntervalSince1970 + Double(millis) / 1000) }

    static func hlc(_ millis: Int64, _ logical: UInt32 = 0, node: UInt64 = 1) -> HLCTimestamp {
        HLCTimestamp(physicalMillis: TabulaJSON.milliseconds(from: t0) + millis, logical: logical, node: node)
    }

    /// A task created through the stamper on `clock` at `t0 + millis`.
    static func task(_ id: TaskItem.ID, title: String = "Task", clock: inout HybridLogicalClock, at millis: Int64 = 0,
                     subtasks: [Subtask] = [], attachments: [AttachmentRef] = []) throws -> TaskItem {
        let draft = TaskItem(id: id, meta: Fixture.meta(), title: title, subtasks: subtasks, attachments: attachments)
        return try MutationStamper.stamp(old: nil, new: draft, clock: &clock, now: at(millis))
    }

    static func taskID(_ n: UInt64) -> TaskItem.ID { id(n) }

    static func id<T>(_ n: UInt64, namespace: UInt32 = 0x5E) -> EntityID<T> {
        var generator = SequentialIDGenerator(namespace: namespace, start: n)
        return generator.next()
    }

    static func subtask(_ n: UInt64, _ title: String, sortIndex: Int = 0) -> Subtask {
        Subtask(id: id(n, namespace: 0x5B), meta: Fixture.meta(), title: title, sortIndex: sortIndex)
    }

    /// Canonical JSON text (for byte-level comparisons).
    static func json<T: Encodable>(_ value: T) -> String { (try? Fixture.json(value)) ?? "<encode failed>" }

    /// The JSON tree of `value`.
    static func tree<T: Encodable>(_ value: T) throws -> JSONValue { try JSONValue(encoding: value) }
}

/// Edits a JSON object tree at a path of object keys / array indices.
enum SyncJSONPatch {
    enum Step { case key(String), index(Int) }

    static func set(_ tree: JSONValue, _ path: [Step], _ value: JSONValue) -> JSONValue {
        guard let first = path.first else { return value }
        let rest = Array(path.dropFirst())
        switch (first, tree) {
        case let (.key(key), .object(members)):
            var copy = members
            copy[key] = set(members[key] ?? .null, rest, value)
            return .object(copy)
        case let (.index(index), .array(items)) where items.indices.contains(index):
            var copy = items
            copy[index] = set(items[index], rest, value)
            return .array(copy)
        default:
            return tree
        }
    }

    static func get(_ tree: JSONValue, _ path: [Step]) -> JSONValue? {
        var current: JSONValue? = tree
        for step in path {
            switch (step, current) {
            case let (.key(key), .object(members)?): current = members[key]
            case let (.index(index), .array(items)?) where items.indices.contains(index): current = items[index]
            default: return nil
            }
        }
        return current
    }
}
