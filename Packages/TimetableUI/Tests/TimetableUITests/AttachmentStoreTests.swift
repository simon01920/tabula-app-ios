import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Stage B3: attachment file names, links, quota, atomic copy-in and orphan cleanup, on real temporary directories.

private let t0 = Date(timeIntervalSince1970: 1_791_879_600)
private let hour: TimeInterval = 3_600

/// A mutable clock shared with the store under test.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("p3b3-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeStore(_ clock: TestClock, policy: AttachmentCleanupPolicy = .standard) throws -> (FileAttachmentStore, URL) {
    let base = try tempDirectory()
    let store = FileAttachmentStore(root: FileAttachmentStore.root(forStoreDirectory: base), policy: policy,
                                    clock: { clock.now })
    return (store, base)
}

private func newID() -> AttachmentRef.ID { AttachmentRef.ID(UUID()) }

private func ref(_ id: AttachmentRef.ID, deleted: Bool = false, sortIndex: Int = 0) -> AttachmentRef {
    AttachmentRef(id: id, meta: EntityMeta(createdAt: .zero, updatedAt: .zero, isDeleted: deleted), kind: .file,
                  fileName: "a.txt", sortIndex: sortIndex)
}

@Suite("AttachmentFileName")
struct AttachmentFileNameTests {
    @Test func traversalIsReducedToTheLastComponent() {
        #expect(AttachmentFileName.sanitize("../../etc/passwd") == "passwd")
        #expect(AttachmentFileName.sanitize("..\\..\\Windows\\win.ini") == "win.ini")
        #expect(AttachmentFileName.sanitize("..") == "attachment")
        #expect(AttachmentFileName.sanitize(".") == "attachment")
        #expect(AttachmentFileName.sanitize("../") == "attachment")
        #expect(AttachmentFileName.sanitize("/") == "attachment")
        #expect(!AttachmentFileName.sanitize("a/../../b.pdf").contains("/"))
    }

    @Test func emptyAndWhitespaceUseTheFallback() {
        #expect(AttachmentFileName.sanitize("") == "attachment")
        #expect(AttachmentFileName.sanitize("   ") == "attachment")
        #expect(AttachmentFileName.sanitize("", fallbackExtension: "m4a") == "attachment.m4a")
        // A leading dot is stripped first (no hidden files), so ".pdf" is the plain name "pdf", not an extension.
        #expect(AttachmentFileName.sanitize(".pdf") == "pdf")
        #expect(AttachmentFileName.sanitize("..pdf.pdf") == "pdf.pdf")
        #expect(AttachmentFileName.sanitize("notes", fallbackExtension: "txt") == "notes.txt")
        #expect(AttachmentFileName.sanitize("notes.md", fallbackExtension: "txt") == "notes.md")
        #expect(AttachmentFileName.sanitize("x", fallbackExtension: "../evil") == "x")
    }

    @Test func hiddenAndReservedCharactersAreNeutralised() {
        #expect(AttachmentFileName.sanitize(".hidden.txt") == "hidden.txt")
        #expect(AttachmentFileName.sanitize("a:b*c?d\"e<f>g|h.txt") == "a_b_c_d_e_f_g_h.txt")
        #expect(AttachmentFileName.sanitize("line\nbreak\u{0}.txt") == "line_break_.txt")
        // Right-to-left override used to disguise extensions ("…gpj.exe" shown as "…exe.jpg").
        #expect(!AttachmentFileName.sanitize("photo\u{202E}gpj.exe").unicodeScalars.contains("\u{202E}"))
        #expect(AttachmentFileName.sanitize("  report  .pdf  ") == "report.pdf")
    }

    @Test func unicodeIsKeptAndNormalisedToNFC() {
        let decomposed = "Pri\u{0301}klad u\u{0301}lohy.pdf"   // í, ú as base + combining acute
        let result = AttachmentFileName.sanitize(decomposed)
        #expect(result == "Príklad úlohy.pdf")
        #expect(result.unicodeScalars.count == "Príklad úlohy.pdf".unicodeScalars.count)
        #expect(AttachmentFileName.sanitize("数学の宿題.jpg") == "数学の宿題.jpg")
        #expect(AttachmentFileName.sanitize("👩‍🎓 notes.txt") == "👩‍🎓 notes.txt")
    }

    @Test func lengthIsCappedKeepingTheExtension() {
        let long = String(repeating: "é", count: 300) + ".docx"
        let result = AttachmentFileName.sanitize(long)
        #expect(result.utf8.count <= AttachmentFileName.maxUTF8Length)
        #expect(result.hasSuffix(".docx"))
        let emoji = String(repeating: "👩‍🎓", count: 100) + ".png"
        let cut = AttachmentFileName.sanitize(emoji)
        #expect(cut.utf8.count <= AttachmentFileName.maxUTF8Length)
        #expect(cut.hasSuffix(".png"))
        #expect(cut.dropLast(4).allSatisfy { $0 == "👩‍🎓" })   // cut on character boundaries
        // An over-long "extension" is not an extension.
        #expect(AttachmentFileName.pathExtension(of: AttachmentFileName.sanitize("a.verylongextension")) == nil)
    }

    @Test func sanitizeIsIdempotentAndDefinesSafeStoredNames() {
        for raw in ["../../x.pdf", "a:b.txt", "", "Pri\u{0301}klad.pdf", String(repeating: "x", count: 400) + ".jpg",
                    ".hidden", "photo\u{202E}gpj.exe", "ok.JPG"] {
            let once = AttachmentFileName.sanitize(raw)
            #expect(AttachmentFileName.sanitize(once) == once)
            #expect(AttachmentFileName.isSafeStoredName(once))
        }
        #expect(!AttachmentFileName.isSafeStoredName("../x"))
        #expect(!AttachmentFileName.isSafeStoredName("a/b"))
        #expect(!AttachmentFileName.isSafeStoredName(".."))
        #expect(!AttachmentFileName.isSafeStoredName(""))
        #expect(AttachmentFileName.pathExtension(of: "Board.JPG") == "jpg")
    }

    @Test func generatedNamesUseTheGivenZone() throws {
        let bratislava = try #require(TimeZone(identifier: "Europe/Bratislava"))
        // 2026-10-10 07:00:00 UTC = 09:00:00 CEST.
        let date = Date(timeIntervalSince1970: 1_791_615_600)
        #expect(AttachmentFileName.generated(prefix: "VoiceNote", fileExtension: "m4a", date: date,
                                             timeZone: bratislava) == "VoiceNote-20261010-090000.m4a")
        #expect(AttachmentFileName.generated(prefix: "Photo", fileExtension: "heic", date: date,
                                             timeZone: try #require(TimeZone(identifier: "UTC"))) == "Photo-20261010-070000.heic")
    }

    @Test func contentTypeFallsBackToTheExtensionTable() {
        #expect(AttachmentContentType.resolve(provided: "public.heic", fileName: "x.jpg") == "public.heic")
        #expect(AttachmentContentType.resolve(provided: nil, fileName: "x.JPG") == "public.jpeg")
        #expect(AttachmentContentType.resolve(provided: "  ", fileName: "a.pdf") == "com.adobe.pdf")
        #expect(AttachmentContentType.resolve(provided: "bad type", fileName: "v.m4a") == "com.apple.m4a-audio")
        #expect(AttachmentContentType.resolve(provided: nil, fileName: "blob") == "public.data")
    }
}

@Suite("AttachmentLink")
struct AttachmentLinkTests {
    @Test func acceptsWebLinks() throws {
        #expect(AttachmentLink.validated("https://example.com/a?b=1")?.absoluteString == "https://example.com/a?b=1")
        #expect(AttachmentLink.validated("  http://example.com  ")?.absoluteString == "http://example.com")
        #expect(AttachmentLink.validated("example.com/x")?.absoluteString == "https://example.com/x")
        #expect(AttachmentLink.validated("example.com:8080/x")?.absoluteString == "https://example.com:8080/x")
        #expect(AttachmentLink.validated("HTTPS://Example.com") != nil)
        #expect(AttachmentLink.host(of: "https://www.example.com/a") == "www.example.com")
        #expect(AttachmentLink.host(of: nil) == nil)
    }

    @Test func rejectsOtherSchemesAndDisguises() {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "tel:123", "mailto:a@b.c", "ftp://example.com",
                    "data:text/html,hi", "https://", "https://bank.com@evil.example", "https://exa mple.com", "",
                    "   ", "https://exa\nmple.com", "https://exa\u{7}mple.com","sms:+421", "x-apple-health://", "https://user:pw@host.com"] {
            #expect(AttachmentLink.validated(bad) == nil, "accepted \(bad)")
        }
        #expect(AttachmentLink.validated("https://example.com/" + String(repeating: "a", count: 3_000)) == nil)
    }
}

@Suite("Attachment quota and references")
struct AttachmentPolicyTests {
    @Test func quotaComesFromTheEntitlementsInMegabytes() {
        let free = AttachmentQuota(entitlements: PolicyEntitlements(tier: .free))
        #expect(free.limitBytes == Int64(100_000_000))
        #expect(AttachmentQuota(entitlements: PolicyEntitlements(tier: .pro)).limitBytes == Int64(2_000_000_000))
        #expect(AttachmentQuota(entitlements: AllAccessEntitlements()) == .unlimited)
        #expect(free.allows(adding: 1_000_000, currentUsage: 99_000_000))
        #expect(!free.allows(adding: 1_000_001, currentUsage: 99_000_000))
        #expect(free.available(currentUsage: 150_000_000) == 0)
        #expect(AttachmentQuota.unlimited.allows(adding: .max, currentUsage: .max))
    }

    @Test func liveIDsSkipTombstonedRefsAndTasks() {
        var database = SampleScenarios.blank()
        let live = newID(), tombstoned = newID(), ofDeletedTask = newID()
        let meta = EntityMeta(createdAt: .zero, updatedAt: .zero)
        database.tasks = [
            TaskItem(id: TaskItem.ID(UUID()), meta: meta, title: "A", kind: .homework, due: nil,
                     attachments: [ref(live), ref(tombstoned, deleted: true)]),
            TaskItem(id: TaskItem.ID(UUID()), meta: EntityMeta(createdAt: .zero, updatedAt: .zero, isDeleted: true),
                     title: "B", kind: .homework, due: nil, attachments: [ref(ofDeletedTask)]),
        ]
        #expect(AttachmentReferences.liveIDs(in: database) == [live.uuid])
    }

    @Test func visibleOrderReorderAndNextIndex() {
        let a = newID(), b = newID(), c = newID(), gone = newID()
        let refs = [ref(a, sortIndex: 2), ref(b, sortIndex: 0), ref(gone, deleted: true, sortIndex: 9), ref(c, sortIndex: 1)]
        #expect(AttachmentReferences.visible(refs).map(\.id) == [b, c, a])
        #expect(AttachmentReferences.nextSortIndex(refs) == 3)
        #expect(AttachmentReferences.nextSortIndex([]) == 0)
        let moved = AttachmentReferences.reordered(refs, to: [a, b, c])
        #expect(AttachmentReferences.visible(moved).map(\.id) == [a, b, c])
        #expect(moved.first { $0.id == gone }?.sortIndex == 9)   // tombstones untouched
    }

    @Test func cleanupGateRequiresALoadedWritableSavedDatabase() {
        func gate(loaded: Bool = true, readOnly: Bool = false, problem: Bool = false, recovered: Bool = false,
                  saveFailed: Bool = false) -> Bool {
            AttachmentCleanupGate.mayRun(databaseLoaded: loaded, isReadOnly: readOnly, hasProblem: problem,
                                         recoveredThisSession: recovered, lastSaveFailed: saveFailed)
        }
        #expect(gate())
        #expect(!gate(loaded: false))
        #expect(!gate(readOnly: true))
        #expect(!gate(problem: true))
        #expect(!gate(recovered: true))
        #expect(!gate(saveFailed: true))   // the in-memory state is not on disk: never clean against it
    }

    @Test func unknownKindRefsAreLive() {
        var database = SampleScenarios.blank()
        let future = newID()
        var futureRef = ref(future)
        futureRef.kind = AttachmentKind(rawValue: "sketch")   // written by a newer app version
        database.tasks = [TaskItem(id: TaskItem.ID(UUID()), meta: EntityMeta(createdAt: .zero, updatedAt: .zero),
                                   title: "T", kind: .homework, due: nil, attachments: [futureRef])]
        #expect(AttachmentReferences.liveIDs(in: database) == [future.uuid])
        #expect(DynamicL10nKeys.attachmentKind(futureRef.kind) == "attachments.kind.unknown")
    }

    @Test func editorProtectionOnlyGrows() {
        var protection = AttachmentEditorProtection()
        let a = newID(), b = newID(), c = newID()
        let first = protection.record([ref(a), ref(b, deleted: true)])
        let afterRemovingB = protection.record([ref(a)])   // removing b from the draft does not unprotect it
        let copying = protection.record(c)                  // an import still copying
        let again = protection.record(c)
        #expect(first && !afterRemovingB && copying && !again)
        #expect(protection.ids == [a.uuid, b.uuid, c.uuid])
    }

    @Test func policyKeepsLiveProtectedAndRecentFolders() {
        let policy = AttachmentCleanupPolicy(gracePeriod: 24 * hour)
        let live = UUID(), protected = UUID(), recent = UUID(), old = UUID(), future = UUID()
        let entries = [
            AttachmentDirectoryEntry(id: live, byteCount: 1, lastModified: t0 - 100 * hour),
            AttachmentDirectoryEntry(id: protected, byteCount: 1, lastModified: t0 - 100 * hour),
            AttachmentDirectoryEntry(id: recent, byteCount: 1, lastModified: t0 - 23 * hour),
            AttachmentDirectoryEntry(id: old, byteCount: 1, lastModified: t0 - 24 * hour),
            AttachmentDirectoryEntry(id: future, byteCount: 1, lastModified: t0 + 5 * hour),
        ]
        #expect(policy.deletable(entries: entries, liveIDs: [live], protectedIDs: [protected], now: t0) == [old])
    }
}

@Suite("FileAttachmentStore")
struct FileAttachmentStoreTests {
    @Test func importDataIsStoredUnderTheIDWithSanitisedName() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let id = newID()
        let stored = try await store.importData(Data("hello".utf8), id: id, suggestedName: "../Úloha:1.txt",
                                                contentType: nil, quota: .unlimited)
        #expect(stored == StoredAttachmentFile(fileName: "Úloha_1.txt", byteCount: 5, contentType: "public.plain-text"))
        let url = try #require(await store.fileURL(id: id, fileName: stored.fileName))
        #expect(url.deletingLastPathComponent().lastPathComponent == id.uuidString)
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Attachments")
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello")
        #expect(await store.totalUsage() == 5)
        // Unsafe or missing names never resolve.
        #expect(await store.fileURL(id: id, fileName: "../\(id.uuidString)/\(stored.fileName)") == nil)
        #expect(await store.fileURL(id: id, fileName: nil) == nil)
        #expect(await store.fileURL(id: newID(), fileName: stored.fileName) == nil)
    }

    @Test func importFileCopiesAtomicallyAndLeavesNoStaging() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source.pdf")
        let bytes = Data((0..<10_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        // The source is old: the stored copy is stamped with the import time (grace period starts now).
        try FileManager.default.setAttributes([.modificationDate: t0 - 1_000 * hour], ofItemAtPath: source.path)
        let id = newID()
        let stored = try await store.importFile(at: source, id: id, suggestedName: "Worksheet.pdf",
                                                contentType: "com.adobe.pdf", quota: .unlimited)
        #expect(stored.byteCount == 10_000)
        let url = try #require(await store.fileURL(id: id, fileName: stored.fileName))
        #expect(try Data(contentsOf: url) == bytes)
        #expect(FileManager.default.fileExists(atPath: source.path))   // a copy, the source stays
        let staging = store.root.appendingPathComponent(".staging")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty)
        let entry = try #require(await store.entries().first)
        #expect(entry.lastModified >= t0 - 1)
        // IDs are never reused: a second import for the same ID fails and keeps the first file.
        await #expect(throws: AttachmentStoreError.alreadyExists) {
            try await store.importData(Data("x".utf8), id: id, suggestedName: "b.txt", contentType: nil, quota: .unlimited)
        }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func unreadableSourceStoresNothing() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let id = newID()
        await #expect(throws: AttachmentStoreError.sourceUnreadable) {
            try await store.importFile(at: base.appendingPathComponent("missing.pdf"), id: id, suggestedName: "m.pdf",
                                       contentType: nil, quota: .unlimited)
        }
        #expect(await store.entries().isEmpty)
        let staging = store.root.appendingPathComponent(".staging")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty)
    }

    @Test func quotaRefusesFilesThatDoNotFitAndCountsTotalUsage() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let quota = AttachmentQuota(limitBytes: 100)
        _ = try await store.importData(Data(count: 60), id: newID(), suggestedName: "a.bin", contentType: nil, quota: quota)
        _ = try await store.importData(Data(count: 30), id: newID(), suggestedName: "b.bin", contentType: nil, quota: quota)
        #expect(await store.totalUsage() == 90)
        await #expect(throws: AttachmentStoreError.quotaExceeded(needed: 11, available: 10)) {
            try await store.importData(Data(count: 11), id: newID(), suggestedName: "c.bin", contentType: nil, quota: quota)
        }
        // File path: the definitive check runs on the copied bytes; nothing is left behind.
        let source = base.appendingPathComponent("big.bin")
        try Data(count: 50).write(to: source)
        await #expect(throws: AttachmentStoreError.quotaExceeded(needed: 50, available: 10)) {
            try await store.importFile(at: source, id: newID(), suggestedName: "big.bin", contentType: nil, quota: quota)
        }
        #expect(await store.entries().count == 2)
        _ = try await store.importData(Data(count: 10), id: newID(), suggestedName: "d.bin", contentType: nil, quota: quota)
        #expect(await store.totalUsage() == 100)
    }

    @Test func deleteRemovesOnlyThatFolder() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let a = newID(), b = newID()
        _ = try await store.importData(Data(count: 3), id: a, suggestedName: "a.bin", contentType: nil, quota: .unlimited)
        let storedB = try await store.importData(Data(count: 4), id: b, suggestedName: "b.bin", contentType: nil, quota: .unlimited)
        try await store.deleteFiles(id: a)
        try await store.deleteFiles(id: a)   // idempotent
        #expect(await store.entries().map(\.id) == [b.uuid])
        #expect(await store.fileURL(id: b, fileName: storedB.fileName) != nil)
        #expect(await store.totalUsage() == 4)
    }

    @Test func orphanCleanupHonoursLiveTombstonedAndGrace() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock, policy: AttachmentCleanupPolicy(gracePeriod: 24 * hour))
        defer { try? FileManager.default.removeItem(at: base) }
        let live = newID(), tombstoned = newID(), neverSaved = newID(), fresh = newID()
        for id in [live, tombstoned, neverSaved] {
            _ = try await store.importData(Data(count: 10), id: id, suggestedName: "f.bin", contentType: nil, quota: .unlimited)
        }
        clock.now = t0 + 30 * hour
        _ = try await store.importData(Data(count: 10), id: fresh, suggestedName: "f.bin", contentType: nil, quota: .unlimited)

        // The database: `live` referenced; `tombstoned` has a tombstoned ref; the others are unknown.
        var database = SampleScenarios.blank()
        database.tasks = [TaskItem(id: TaskItem.ID(UUID()), meta: EntityMeta(createdAt: .zero, updatedAt: .zero),
                                   title: "T", kind: .homework, due: nil,
                                   attachments: [ref(live), ref(tombstoned, deleted: true)])]
        let report = await store.cleanUpOrphans(liveIDs: AttachmentReferences.liveIDs(in: database))
        #expect(Set(report.deleted) == [tombstoned.uuid, neverSaved.uuid])
        #expect(report.freedBytes == 20)
        #expect(report.kept == 2)
        #expect(report.failures.isEmpty)
        #expect(Set(await store.entries().map(\.id)) == [live.uuid, fresh.uuid])

        // A live file is never deleted, however old it is.
        clock.now = t0 + 10_000 * hour
        let later = await store.cleanUpOrphans(liveIDs: [live.uuid])
        #expect(later.deleted == [fresh.uuid])
        #expect(await store.entries().map(\.id) == [live.uuid])
    }

    @Test func openEditorProtectionPreventsDeletionUntilCleared() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock, policy: AttachmentCleanupPolicy(gracePeriod: hour))
        defer { try? FileManager.default.removeItem(at: base) }
        let pending = newID(), editor = UUID(), otherEditor = UUID()
        _ = try await store.importData(Data(count: 1), id: pending, suggestedName: "p.bin", contentType: nil, quota: .unlimited)
        await store.setProtectedIDs([pending.uuid], owner: editor)
        await store.setProtectedIDs([], owner: otherEditor)
        clock.now = t0 + 48 * hour
        #expect(await store.cleanUpOrphans(liveIDs: []).deleted.isEmpty)
        await store.clearProtection(owner: otherEditor)
        #expect(await store.cleanUpOrphans(liveIDs: []).deleted.isEmpty)
        await store.clearProtection(owner: editor)
        #expect(await store.cleanUpOrphans(liveIDs: []).deleted == [pending.uuid])
    }

    @Test func cleanupIgnoresForeignEntriesAndRemovesAbandonedStaging() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock, policy: AttachmentCleanupPolicy(gracePeriod: hour, stagingMaxAge: hour))
        defer { try? FileManager.default.removeItem(at: base) }
        let fileManager = FileManager.default
        let root = store.root
        try fileManager.createDirectory(at: root.appendingPathComponent("not-a-uuid"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("loose.txt"))
        let stale = root.appendingPathComponent(".staging/\(UUID().uuidString)")
        let current = root.appendingPathComponent(".staging/\(UUID().uuidString)")
        for folder in [stale, current] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(count: 5).write(to: folder.appendingPathComponent("partial.bin"))
        }
        for path in [stale.path, stale.appendingPathComponent("partial.bin").path] {
            try fileManager.setAttributes([.modificationDate: t0 - 2 * hour], ofItemAtPath: path)
        }
        for path in [current.path, current.appendingPathComponent("partial.bin").path] {
            try fileManager.setAttributes([.modificationDate: t0], ofItemAtPath: path)
        }
        let report = await store.cleanUpOrphans(liveIDs: [])
        #expect(report.deleted.isEmpty)
        #expect(report.removedStaging == 1)
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("not-a-uuid").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("loose.txt").path))
        #expect(!fileManager.fileExists(atPath: stale.path))
        #expect(fileManager.fileExists(atPath: current.path))
        #expect(await store.totalUsage() == 0)   // staging and foreign entries are not usage
    }

    @Test func foldersPackagesAndLinksAreNotImported() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        let fileManager = FileManager.default
        let folder = base.appendingPathComponent("Essay.pages", isDirectory: true)   // a package is a folder
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 10).write(to: folder.appendingPathComponent("index.xml"))
        let real = base.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: real)
        let link = base.appendingPathComponent("link.txt")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        for source in [folder, link] {
            await #expect(throws: AttachmentStoreError.notARegularFile) {
                try await store.importFile(at: source, id: newID(), suggestedName: source.lastPathComponent,
                                           contentType: nil, quota: .unlimited)
            }
        }
        #expect(await store.entries().isEmpty)
    }

    @Test func symlinkedUUIDFolderIsIgnoredAndItsTargetSurvives() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock, policy: AttachmentCleanupPolicy(gracePeriod: hour))
        defer { try? FileManager.default.removeItem(at: base) }
        let fileManager = FileManager.default
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(count: 7).write(to: outside.appendingPathComponent("precious.bin"))
        try fileManager.createDirectory(at: store.root, withIntermediateDirectories: true)
        let linked = store.root.appendingPathComponent(UUID().uuidString)
        try fileManager.createSymbolicLink(at: linked, withDestinationURL: outside)
        clock.now = t0 + 100 * hour
        let report = await store.cleanUpOrphans(liveIDs: [])
        #expect(report.deleted.isEmpty)
        #expect(await store.entries().isEmpty)
        #expect(await store.totalUsage() == 0)
        #expect(fileManager.fileExists(atPath: outside.appendingPathComponent("precious.bin").path))
        #expect((try? fileManager.destinationOfSymbolicLink(atPath: linked.path)) != nil)
    }

    @Test func replacingAnEditorsProtectionUnprotectsStaleIDs() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock, policy: AttachmentCleanupPolicy(gracePeriod: hour))
        defer { try? FileManager.default.removeItem(at: base) }
        let kept = newID(), stale = newID(), editor = UUID()
        for id in [kept, stale] {
            _ = try await store.importData(Data(count: 1), id: id, suggestedName: "f.bin", contentType: nil, quota: .unlimited)
        }
        await store.setProtectedIDs([kept.uuid, stale.uuid], owner: editor)
        await store.setProtectedIDs([kept.uuid], owner: editor)   // the owner's set is replaced, not merged
        clock.now = t0 + 2 * hour
        #expect(await store.cleanUpOrphans(liveIDs: []).deleted == [stale.uuid])
        #expect(await store.entries().map(\.id) == [kept.uuid])
    }

    @Test func cleanupOnAMissingRootIsANoOp() async throws {
        let clock = TestClock(t0)
        let (store, base) = try makeStore(clock)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(await store.cleanUpOrphans(liveIDs: []) == AttachmentCleanupReport())
        #expect(await store.totalUsage() == 0)
    }
}
