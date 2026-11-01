import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let context = CalendarContext(timeZone: TimeZone(identifier: "Europe/Bratislava")!, firstWeekday: .monday)
private let now = Date(timeIntervalSince1970: 1_793_000_000)

private func activeID(_ db: TabulaDatabase) -> Timetable.ID {
    db.settings.activeTimetableID ?? ActiveTimetable.ordered(db)[0].id
}

private func envelope(_ db: TabulaDatabase) throws -> ShareEnvelope {
    try ShareExport.encode(from: db, timetableID: activeID(db), includeTasks: false).envelope
}

@Suite("Share links in (H1)")
struct ShareInboundTests {
    @Test func appLinkWithFragmentIsAnEnvelope() {
        #expect(ShareInbound.parse(url: URL(string: "tabula://import#1.abc-_9")!) == .envelope("1.abc-_9"))
        #expect(ShareInbound.parse(appLink: "TABULA://Import#1.x") == .envelope("1.x"))
    }

    @Test func appLinkWithCodeIsACode() {
        #expect(ShareInbound.parse(url: URL(string: "tabula://import?code=7KX2M9QH")!) == .code(ShortCode("7KX2M9QH")!))
    }

    @Test func malformedAppLinksAreRefused() {
        for text in ["tabula://import", "tabula://import#", "tabula://import#1.a b", "tabula://import#1.a%20",
                     "tabula://import?code=7kx2m9qh", "tabula://import?code=7KX2M9QH&x=1", "tabula://import?code=7KX2M9Q0",
                     "tabula://import/#1.a", "tabula://open/today", "https://import#1.a", "tabula://importer#1.a",
                     "tabula://import#" + String(repeating: "A", count: ShareLimits.maxLinkBytes)] {
            #expect(ShareInbound.parse(appLink: text) == nil, "\(text.prefix(60))")
        }
    }

    @Test func pastedTextAcceptsLinksAndCodes() throws {
        #expect(try ShareInbound.parse(pasted: " https://tabula.simondev.sk/t#1.abc\n") == .envelope("1.abc"))
        #expect(try ShareInbound.parse(pasted: "https://tabula.simondev.sk/c/7KX2M9QH?utm=x") == .code(ShortCode("7KX2M9QH")!))
        #expect(try ShareInbound.parse(pasted: "tabula://import?code=7KX2M9QH") == .code(ShortCode("7KX2M9QH")!))
        #expect(try ShareInbound.parse(pasted: "7kx2-m9qh") == .code(ShortCode("7KX2M9QH")!))
    }

    @Test func pastedGarbageSaysWhichKind() {
        #expect(throws: ShareError.invalidLink) { try ShareInbound.parse(pasted: "https://example.com/t#1.abc") }
        #expect(throws: ShareError.invalidLink) { try ShareInbound.parse(pasted: "tabula://import") }
        #expect(throws: ShareError.invalidLink) { try ShareInbound.parse(pasted: "www.example.com/x") }
        #expect(throws: ShareError.invalidShortCode) { try ShareInbound.parse(pasted: "HELLO") }
        #expect(throws: ShareError.invalidShortCode) { try ShareInbound.parse(pasted: "") }
    }
}

@Suite("Code entry (H1)")
struct ShareCodeInputTests {
    @Test func liveStates() {
        #expect(ShareCodeInput.evaluate("") == .empty)
        #expect(ShareCodeInput.evaluate("  - ") == .empty)
        #expect(ShareCodeInput.evaluate("7kx") == .incomplete(remaining: 5))
        #expect(ShareCodeInput.evaluate("7KX2-M9Q") == .incomplete(remaining: 1))
        #expect(ShareCodeInput.evaluate("7kx2 m9qh") == .complete(ShortCode("7KX2M9QH")!))
        #expect(ShareCodeInput.evaluate("7KX2‐M9QH") == .complete(ShortCode("7KX2M9QH")!))   // U+2010 hyphen
        #expect(ShareCodeInput.evaluate("7KX2M9QH2") == .tooLong)
    }

    @Test func excludedCharactersAreFlaggedAtOnce() {
        for text in ["0", "o", "1", "i", "l", "7KX!", "ž", "７"] {
            #expect(ShareCodeInput.evaluate(text) == .invalidCharacter, "\(text)")
        }
    }

    @Test func hints() {
        #expect(ShareCodeInput.empty.messageKey == nil)
        #expect(ShareCodeInput.incomplete(remaining: 3).messageKey == "share.code.remaining")
        #expect(ShareCodeInput.invalidCharacter.messageKey == "share.code.invalidCharacter")
        #expect(ShareCodeInput.tooLong.messageKey == "share.code.tooLong")
    }
}

@Suite("Inline link or short code (H1)")
struct SharePlanTests {
    @Test func secondaryFitsInline() throws {
        let env = try envelope(SampleScenarios.secondary().database)
        guard case .inline(let link) = SharePlan.make(for: env) else { Issue.record("expected inline"); return }
        #expect(link.urlString().hasPrefix("https://tabula.simondev.sk/t#1."))
        #expect(link.urlString().utf8.count <= SharePlan.qrByteCapacity)
    }

    @Test func universityNeedsACodeAndHasNoQRFallback() throws {
        // 60 lessons with incompressible notes: well over the 2 KB inline budget.
        let db = SampleScenarios.secondary().database
        var payload = try ShareExport.makePayload(from: db, timetableID: activeID(db), includeTasks: false).payload
        for _ in 0..<60 {
            var lesson = payload.lessons[0]
            lesson.notes = (0..<4).map { _ in UUID().uuidString }.joined(separator: " ")
            payload.lessons.append(lesson)
        }
        let env = try ShareCodec.encode(payload)
        #expect(env.route == .shortCode)
        #expect(SharePlan.make(for: env) == .upload(envelope: env.text))
        #expect(SharePlan.fallback(envelope: env.text) == nil)   // ≈ 10 KB: no QR code holds it
    }

    @Test func fallbackOnlyWhenTheLinkFitsAQRCode() {
        let fits = "1." + String(repeating: "A", count: 2900)     // link 2931 bytes
        let tooBig = "1." + String(repeating: "A", count: 2950)   // link 2981 bytes
        #expect(SharePlan.fallback(envelope: fits) == .inline(envelope: fits))
        #expect(SharePlan.fallback(envelope: tooBig) == nil)
    }
}

@Suite("Share service contract (H1/H2)")
struct ShareServiceTests {
    @Test func urlsAndBody() throws {
        #expect(ShareService.uploadURL.absoluteString == "https://tabula.simondev.sk/v1/share")
        #expect(ShareService.fetchURL(for: ShortCode("7KX2M9QH")!).absoluteString == "https://tabula.simondev.sk/v1/share/7KX2M9QH")
        #expect(String(decoding: ShareService.uploadBody(envelope: "1.ab"), as: UTF8.self) == #"{"payload":"1.ab","v":1}"#)
    }

    @Test func decodesResponses() {
        let created = Data(#"{"code":"7KX2M9QH","url":"https://x/c/7KX2M9QH","expiresAt":"2026-11-30T00:00:00Z"}"#.utf8)
        #expect(ShareService.decodeUpload(status: 201, data: created) == .success(ShortCode("7KX2M9QH")!))
        #expect(ShareService.decodeUpload(status: 201, data: Data(#"{"code":"bad"}"#.utf8)) == .failure(.invalidResponse))
        #expect(ShareService.decodeUpload(status: 429, data: Data()) == .failure(.rateLimited))
        #expect(ShareService.decodeUpload(status: 413, data: Data()) == .failure(.tooLarge))
        #expect(ShareService.decodeUpload(status: 503, data: Data()) == .failure(.unavailable))
        #expect(ShareService.decodeFetch(status: 200, data: Data(#"{"v":1,"payload":"1.ab"}"#.utf8)) == .success("1.ab"))
        #expect(ShareService.decodeFetch(status: 200, data: Data(#"{"v":2,"payload":"1.ab"}"#.utf8)) == .failure(.invalidResponse))
        #expect(ShareService.decodeFetch(status: 404, data: Data()) == .failure(.notFound))
    }
}

@Suite("Import preview and mutation (H1)")
struct ShareImportFlowTests {
    private func payload(_ db: TabulaDatabase) throws -> SharePayloadV1 {
        try ShareExport.makePayload(from: db, timetableID: activeID(db), includeTasks: false).payload
    }

    private func apply(_ mutation: DatabaseMutation, to db: TabulaDatabase) throws -> TabulaDatabase {
        var clock = HybridLogicalClock(node: 7)
        return try mutation.apply(to: db, clock: &clock, now: now)
    }

    @Test func summaryShowsTheTimetable() throws {
        let db = SampleScenarios.secondary().database
        let source = try payload(db)
        let summary = try ShareImportSummary(payload: source, context: context)
        #expect(summary.name == source.timetable.name)
        #expect(summary.subjectNames.count == source.subjects.count)
        #expect(summary.lessonCount == source.lessons.count)
        #expect(summary.bellSchedules.count == source.bellSchedules.count)
        #expect(summary.bellSchedules.allSatisfy { !$0.periods.isEmpty })
        #expect(summary.conflictCount == 0)
    }

    @Test func overlappingLessonsAreCounted() throws {
        var source = try payload(SampleScenarios.secondary().database)
        var twin = source.lessons[0]
        twin.subject = (twin.subject + 1) % source.subjects.count
        source.lessons.append(twin)
        #expect(try ShareImportSummary(payload: source, context: context).conflictCount >= 2)
    }

    @Test func addKeepsEverythingAndActivatesTheNewTimetable() throws {
        let db = SampleScenarios.secondary().database
        let before = ActiveTimetable.ordered(db)
        let after = try apply(.importShared(try payload(db)), to: db)
        let live = ActiveTimetable.ordered(after)
        #expect(live.count == before.count + 1)
        #expect(Set(before.map(\.id)).isSubset(of: Set(live.map(\.id))))
        #expect(after.settings.activeTimetableID == live.last?.id)
        #expect(after.validate().allSatisfy { $0.severity != .error })
    }

    @Test func replaceDeletesOnlyTheReplacedTimetableAndKeepsItsPlace() throws {
        let db = SampleScenarios.secondary().database
        let old = activeID(db)
        let oldIndex = ActiveTimetable.ordered(db).first { $0.id == old }!.sortIndex
        let after = try apply(.importShared(try payload(db), replacing: old), to: db)
        let live = ActiveTimetable.ordered(after)
        #expect(live.count == ActiveTimetable.ordered(db).count)
        #expect(!live.contains { $0.id == old })
        #expect(after.timetables.first { $0.id == old }?.isDeleted == true)
        let new = try #require(live.first { $0.id == after.settings.activeTimetableID })
        #expect(new.sortIndex == oldIndex)
        #expect(after.tasks.filter { !$0.isDeleted }.count == db.tasks.filter { !$0.isDeleted }.count)
    }

    @Test func firstLaunchImportFinishesOnboarding() throws {
        let source = try payload(SampleScenarios.secondary().database)
        let mutation = DatabaseMutation.importShared(source, profile: .university, startsFromScratch: true)
        #expect(mutation.replacesDatabase)
        let after = try apply(mutation, to: DatabaseMutation.emptyBase)
        #expect(ActiveTimetable.ordered(after).count == 1)
        #expect(after.settings.onboardingCompletedAt == now)
        #expect(after.settings.profile == .university)
        #expect(after.settings.activeTimetableID == after.timetables.first?.id)
        let presets = ProfilePreset.for(.university).reminderRules
        #expect(!presets.isEmpty)
        #expect(after.reminderRules.map(\.target) == presets.map(\.target))
        #expect(after.validate().allSatisfy { $0.severity != .error })
    }

    @Test func importKeepsExistingReminderRules() throws {
        let db = SampleScenarios.secondary().database
        let after = try apply(.importShared(try payload(db)), to: db)
        #expect(after.reminderRules == db.reminderRules)
    }

    @Test func replacingAVanishedTimetableFailsInsteadOfAdding() throws {
        let db = SampleScenarios.secondary().database
        let gone = Timetable.ID(UUID())
        #expect(throws: MutationError.notFound(.timetable, gone.uuid)) {
            try apply(.importShared(try payload(db), replacing: gone), to: db)
        }
    }
}
