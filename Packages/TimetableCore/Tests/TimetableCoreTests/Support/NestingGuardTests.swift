import Foundation
import Testing
@testable import TimetableCore

/// Runs `body` on a thread with a small stack and returns its result. Darwin gives Swift-concurrency threads a
/// 512 KiB stack (Linux 8 MiB), so recursion that passes on Linux can overflow on an iPhone. These tests use
/// half of that (256 KiB) as a safety margin for larger Darwin frames.
enum SmallStack {
    static let darwinThreadStack = 512 * 1024

    static func run<T: Sendable>(stackBytes: Int = darwinThreadStack / 2,
                                 _ body: @escaping @Sendable () throws -> T) throws -> T {
        let box = SmallStackBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.result = Result { try body() }
            done.signal()
        }
        thread.stackSize = stackBytes
        thread.start()
        done.wait()
        return try box.result!.get()
    }
}

/// Result slot for `SmallStack.run` (written once by the worker thread, read after the semaphore).
final class SmallStackBox<T>: @unchecked Sendable {
    var result: Result<T, any Error>?
}

/// Regression for the macOS CI crash of 2026-10-08 (`swiftpm-testing-helper` SIGBUS): `SyncJSONParser` accepted
/// 512 nesting levels and recursed twice per level, which overflows a 512 KiB thread stack. Every untrusted JSON
/// entry point now rejects input nested deeper than `TabulaJSON.maxNestingDepth` (64) iteratively, before any
/// recursive decoder runs, and everything at the limit works on a small stack.
@Suite("Nesting-depth guard (small stacks)")
struct NestingGuardTests {
    /// `Fixture.fullDatabase()` JSON with an unknown root field nested so that the whole document has `depth`
    /// levels (the root object is level 1).
    static func database(depth: Int) throws -> Data {
        var bytes = Array(try Fixture.fullDatabase().encoded())
        #expect(bytes.last == UInt8(ascii: "}"))
        bytes.removeLast()
        let field = #","zzDeep":"# + String(repeating: "[", count: depth - 1) + "1" + String(repeating: "]", count: depth - 1) + "}"
        bytes += Array(field.utf8)
        return Data(bytes)
    }

    @Test func nestingDepthIsIterativeAndIgnoresStrings() {
        let huge = Array(repeating: UInt8(ascii: "["), count: 1_000_000)
        #expect(TabulaJSON.nestingDepth(huge, limit: 64) == 65)
        #expect(TabulaJSON.nestingDepth(Array(#"{"a":"[[[[\"]]","b":[[1]]}"#.utf8), limit: 64) == 3)
        #expect(TabulaJSON.maxNestingDepth == 64)
    }

    @Test func databaseAtTheLimitDecodesMergesAndParsesOnASmallStack() throws {
        let data = try Self.database(depth: TabulaJSON.maxNestingDepth)
        #expect(TabulaJSON.nestingDepth(data, limit: 100) == 64)
        let reencoded = try SmallStack.run { () throws -> Data in
            let db = try TabulaDatabase.decode(from: data)
            guard case .current(let viaFile) = DatabaseFileDecoder.decode(data, migrations: .standard) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let merged = try SyncMerge.merge(local: db, remote: viaFile)
            _ = try SyncJSONParser.parse(data)
            _ = SyncJSON.canonicalBytes(try JSONValue(encoding: merged))
            return try merged.encoded()
        }
        #expect(try TabulaDatabase.decode(from: reencoded).unknownFields.root["zzDeep"] != nil)
    }

    @Test(arguments: [TabulaJSON.maxNestingDepth + 1, 600, 100_000])
    func deeperInputIsATypedErrorNotACrash(depth: Int) throws {
        let data = try Self.database(depth: depth)
        let outcome = try SmallStack.run { () -> [String] in
            var failures: [String] = []
            do { _ = try TabulaDatabase.decode(from: data); failures.append("TabulaDatabase.decode accepted it") } catch {}
            if case .corrupt(.invalidJSON) = DatabaseFileDecoder.decode(data, migrations: .standard) {} else {
                failures.append("DatabaseFileDecoder did not report invalidJSON")
            }
            do { _ = try SyncJSONParser.parse(data); failures.append("SyncJSONParser accepted it") } catch {}
            let bare = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
            do { _ = try SyncJSONParser.parse(bare); failures.append("SyncJSONParser accepted bare arrays") } catch {}
            do {
                let manifest = BackupArchive.Manifest(
                    format: BackupArchive.formatName, formatVersion: BackupArchive.formatVersion, schemaVersion: 1,
                    createdAt: Fixture.now, entityCounts: [:], databaseByteCount: data.count,
                    sha256: TabulaSHA256.hexDigest(data))
                var file = Data((BackupArchive.magicLine + "\n").utf8)
                file.append(try TabulaJSON.makeEncoder().encode(manifest))
                file.append(0x0A)
                file.append(data)
                let archive = try BackupArchive.decode(from: file)
                _ = try archive.database()
                failures.append("backup accepted it")
            } catch {}
            if (try? ShareCodec.decode(ShareFixture.envelope(json: String(decoding: bare, as: UTF8.self)))) != nil {
                failures.append("share accepted it")
            }
            return failures
        }
        #expect(outcome.isEmpty, "\(outcome)")
    }
}
