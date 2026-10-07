import Foundation
import Testing
@testable import TimetableCore

@Suite("Share codec: round trip, determinism, size budget, envelope")
struct ShareCodecTests {
    // MARK: Round trip

    @Test(arguments: [false, true])
    func secondaryRoundTripsThroughEnvelopeAndDatabase(includeTasks: Bool) throws {
        try assertRoundTrip(ShareFixture.secondary(), ShareFixture.secondaryTimetableID, includeTasks: includeTasks)
    }

    @Test(arguments: [false, true])
    func universityRoundTripsThroughEnvelopeAndDatabase(includeTasks: Bool) throws {
        try assertRoundTrip(ShareFixture.university(), ShareFixture.universityTimetableID, includeTasks: includeTasks)
    }

    /// export → encode → decode == payload; materialize → export again == payload (same canonical JSON).
    private func assertRoundTrip(_ db: TabulaDatabase, _ id: Timetable.ID, includeTasks: Bool) throws {
        let exported = try ShareExport.makePayload(from: db, timetableID: id, includeTasks: includeTasks)
        #expect(exported.warnings.isEmpty, "\(exported.warnings)")
        let envelope = try ShareCodec.encode(exported.payload)
        let decoded = try ShareCodec.decode(envelope.text)
        #expect(decoded == exported.payload)

        let (imported, newID) = try ShareFixture.importIntoEmptyDatabase(decoded)
        let errors = imported.validate().filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let reexported = try ShareFixture.payload(imported, newID, includeTasks: includeTasks)
        #expect(reexported == exported.payload)
        #expect(try ShareCodec.canonicalJSON(reexported) == ShareCodec.canonicalJSON(exported.payload))
    }

    @Test func exportSelectsTheRightEntities() throws {
        let db = ShareFixture.secondary()
        let without = try ShareFixture.payload(db, ShareFixture.secondaryTimetableID)
        #expect(without.subjects.count == 14)
        #expect(without.bellSchedules.count == 2)
        #expect(without.bellSchedules.allSatisfy { $0.periods.map(\.key) == Array(0..<10) })
        #expect(without.lessons.count == 32)
        #expect(without.terms.count == 2)
        #expect(without.breaks.count == 6)
        #expect(!without.includesTasks && without.tasks.isEmpty && without.exams.isEmpty)

        let with = try ShareFixture.payload(db, ShareFixture.secondaryTimetableID, includeTasks: true)
        #expect(with.includesTasks)
        // The completed task and the completed exam are personal history and are not shared; the task without a
        // timetable is included because its subject belongs to the timetable.
        #expect(with.tasks.map(\.title) == ["Slohová práca – úvaha", "Pracovný zošit s. 42", "Slovíčka Unit 3"])
        #expect(with.tasks[0].subtasks == ["Osnova", "Koncept"])
        #expect(with.tasks[1].linkedLesson == ShareLessonLink(lesson: 1, date: Fixture.date("2026-10-12")))
        #expect(with.exams.map(\.title) == ["Písomka – funkcie"])
    }

    @Test func exportSkipsDeletedEntitiesAndOtherTimetables() throws {
        var db = ShareFixture.secondary()
        db.subjects[0].meta.isDeleted = true                       // SJL deleted → its lessons are skipped
        let sjlLessons = db.lessons.filter { $0.subjectID == db.subjects[0].id }.count
        db.lessons[5].meta.isDeleted = true
        var other = db.timetables[0]
        other.id = Timetable.ID(UUID(uuidString: "07E40000-0000-4000-8000-000000000001")!)
        db.timetables.append(other)
        db.subjects.append(Subject(id: Subject.ID(UUID(uuidString: "07E40000-0000-4000-8000-000000000002")!), meta: Fixture.meta(),
                                   timetableID: other.id, name: "Elsewhere", color: .black))
        let result = try ShareExport.makePayload(from: db, timetableID: ShareFixture.secondaryTimetableID, includeTasks: false)
        #expect(result.payload.subjects.count == 13)
        #expect(!result.payload.subjects.contains { $0.name == "Elsewhere" })
        let deletedIsSJL = db.lessons[5].subjectID == db.subjects[0].id
        #expect(result.payload.lessons.count == 32 - sjlLessons - (deletedIsSJL ? 0 : 1))
        #expect(result.warnings == [.skippedLessons(count: sjlLessons - (deletedIsSJL ? 1 : 0))])

        db.timetables[0].meta.isDeleted = true
        #expect(throws: ShareError.timetableNotFound) {
            try ShareExport.makePayload(from: db, timetableID: ShareFixture.secondaryTimetableID, includeTasks: false)
        }
    }

    // MARK: Determinism

    @Test func permutedDatabasesProduceByteIdenticalEnvelopes() throws {
        for (db, id) in [(ShareFixture.secondary(), ShareFixture.secondaryTimetableID),
                         (ShareFixture.university(), ShareFixture.universityTimetableID)] {
            let reference = try ShareExport.encode(from: db, timetableID: id, includeTasks: true).envelope
            var rng = TestRNG(seed: 42)
            for _ in 0..<10 {
                var shuffled = db
                shuffled.subjects.shuffle(using: &rng)
                shuffled.lessons.shuffle(using: &rng)
                shuffled.bellSchedules.shuffle(using: &rng)
                for index in shuffled.bellSchedules.indices { shuffled.bellSchedules[index].periods.shuffle(using: &rng) }
                shuffled.terms.shuffle(using: &rng)
                shuffled.breaks.shuffle(using: &rng)
                shuffled.tasks.shuffle(using: &rng)
                for index in shuffled.tasks.indices { shuffled.tasks[index].subtasks.shuffle(using: &rng) }
                shuffled.exams.shuffle(using: &rng)
                let envelope = try ShareExport.encode(from: shuffled, timetableID: id, includeTasks: true).envelope
                #expect(envelope == reference)
            }
        }
    }

    @Test func encodingIsStableAcrossRepeatedCalls() throws {
        let payload = try ShareFixture.payload(ShareFixture.university(), ShareFixture.universityTimetableID, includeTasks: true)
        let first = try ShareCodec.encode(payload)
        for _ in 0..<5 { #expect(try ShareCodec.encode(payload) == first) }
        // decode → encode reproduces the same envelope (canonical input).
        #expect(try ShareCodec.encode(ShareCodec.decode(first.text)) == first)
    }

    /// Golden wire format of a small payload. A change here is a wire-format change (see SHARE_FORMAT.md §10).
    @Test func goldenCanonicalJSON() throws {
        var payload = ShareFixture.minimalPayload()
        payload.timetable.rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 1),
                                                          labels: ["A", "B"]))
        payload.timetable.fieldVisibility = [.teacher, .room]
        payload.subjects[0].colorName = .key("palette.classic.color.red")
        payload.subjects[0].symbol = .emoji("➗")
        payload.terms = [ShareTerm(name: "Winter", range: LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2027-01-31")))]
        payload.breaks = [ShareBreak(name: "Xmas", range: LocalDateRange(start: Fixture.date("2026-12-23"), end: Fixture.date("2027-01-07")),
                                     kind: .vacation)]
        payload.lessons.append(ShareLesson(subject: 0, day: .weekday(.tuesday), cycleWeeks: [2], slot: .period(key: 1, span: 2),
                                           validity: .terms([0]), room: "101", bringList: ["Ruler"]))
        payload.lessons.append(ShareLesson(subject: 0, day: .weekday(.tuesday), slot: .time(start: Fixture.time("12:00"), end: Fixture.time("12:45")),
                                           validity: .range(LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2026-12-31")))))
        payload.includesTasks = true
        payload.tasks = [ShareTask(title: "HW", subject: 0, due: .dateTime(Fixture.date("2026-10-08"), Fixture.time("08:00")),
                                   linkedLesson: ShareLessonLink(lesson: 0, date: Fixture.date("2026-10-05")), priority: .high,
                                   repeatRule: RepeatRule(frequency: .weekly, weekdays: [.wednesday, .monday]), subtasks: ["Read"])]
        payload.exams = [ShareExam(title: "Test", kind: .quiz, subject: 0, date: Fixture.date("2026-10-20"),
                                   start: Fixture.time("08:00"), end: Fixture.time("08:45"), topics: ["Fractions"])]
        let json = String(decoding: try ShareCodec.canonicalJSON(payload), as: UTF8.self)
        let expected = #"{"b":[{"n":"Normal","p":[{"a":"08:00","k":0,"z":"08:45"},{"a":"08:55","k":1,"z":"09:40"}]}],"#
            + #""h":[{"a":"2026-12-23","n":"Xmas","t":"vacation","z":"2027-01-07"}],"#
            + #""k":[{"dd":"2026-10-08","dt":"08:00","ll":{"d":"2026-10-05","l":0},"n":"HW","pr":"high","rp":{"f":"weekly","w":[1,3]},"s":0,"st":["Read"]}],"#
            + #""l":[{"p":0,"s":0,"w":1},{"br":["Ruler"],"cw":[2],"n":2,"p":1,"r":"101","s":0,"vt":[0],"w":2},"#
            + #"{"a":"12:00","s":0,"vr":{"a":"2026-09-01","z":"2026-12-31"},"w":2,"z":"12:45"}],"#
            + #""r":[{"a":"2026-09-01","n":"Winter","z":"2027-01-31"}],"#
            + ##""s":[{"c":"#E53935","ck":"palette.classic.color.red","n":"Math","se":"➗"}],"##
            + #""t":{"d":[1,2],"de":"comfortable","dv":"grid","fv":["room","teacher"],"n":"Mini","#
            + #""ro":{"a":{"k":"iso","o":1,"p":"strict"},"k":"w","lb":["A","B"],"n":2},"ts":{"d":0,"k":"b"}},"#
            + #""v":1,"#
            + #""x":[{"a":"08:00","d":"2026-10-20","n":"Test","s":0,"t":"quiz","tp":["Fractions"],"z":"08:45"}]}"#
        #expect(json == expected)
        #expect(try ShareCodec.decode(ShareCodec.encode(payload).text) == payload)
    }

    // MARK: Size budget

    @Test func sizeBudgetRoutesSecondaryInlineAndUniversityToShortCode() throws {
        let cases: [(String, TabulaDatabase, Timetable.ID, Bool, ShareRoute)] = [
            ("secondary", ShareFixture.secondary(), ShareFixture.secondaryTimetableID, false, .inline),
            ("secondary+tasks", ShareFixture.secondary(), ShareFixture.secondaryTimetableID, true, .inline),
            ("university", ShareFixture.university(), ShareFixture.universityTimetableID, false, .shortCode),
            ("university+tasks", ShareFixture.university(), ShareFixture.universityTimetableID, true, .shortCode),
        ]
        for (name, db, id, tasks, route) in cases {
            let envelope = try ShareExport.encode(from: db, timetableID: id, includeTasks: tasks).envelope
            let link = ShareLink.inline(envelope: envelope.text).urlString()
            print("SHARE-SIZE \(name): json=\(envelope.jsonByteCount) B, deflate=\(envelope.compressedByteCount) B, "
                  + "envelope=\(envelope.text.utf8.count) chars, inline link=\(link.utf8.count) chars, route=\(envelope.route)")
            #expect(envelope.route == route, "\(name)")
            #expect(envelope.text.utf8.count <= ShareLimits.maxEnvelopeBytes)
            if route == .inline {
                // An inline link must fit a QR code at error-correction level L (2953 bytes in byte mode).
                #expect(link.utf8.count <= 2953, "\(name)")
            }
        }
    }

    @Test func inlineRouteBoundaryIsInclusive() throws {
        // Find payloads just below/above the 2048-byte boundary by growing incompressible notes.
        var rng = TestRNG(seed: 7)
        var payload = ShareFixture.minimalPayload()
        var sawInline = false, sawShortCode = false
        for length in stride(from: 2000, through: 3600, by: 16) {
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
            let notes = String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            payload.subjects[0].notes = String(notes.prefix(ShareLimits.maxNotesLength))
            let envelope = try ShareCodec.encode(payload)
            #expect(envelope.route == (envelope.compressedByteCount <= ShareLimits.inlineCompressedBytes ? .inline : .shortCode))
            if envelope.route == .inline { sawInline = true } else { sawShortCode = true }
        }
        #expect(sawInline && sawShortCode)
    }

    @Test func oversizedPayloadIsRefusedOnExport() throws {
        // Maximal counts with incompressible notes exceed the 64 KB envelope.
        var rng = TestRNG(seed: 99)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var payload = ShareFixture.minimalPayload()
        payload.subjects = (0..<ShareLimits.maxSubjects).map { index in
            ShareSubject(name: "S\(index)", color: .black,
                         notes: String((0..<1000).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }))
        }
        #expect(throws: ShareError.self) { try ShareCodec.encode(payload) }
        do {
            _ = try ShareCodec.encode(payload)
        } catch {
            guard case .envelopeTooLarge(let count) = error else { Issue.record("unexpected \(error)"); return }
            #expect(count > ShareLimits.maxEnvelopeBytes)
            #expect(error.message.key == "share.error.tooLarge")
        }
    }

    // MARK: Envelope versions and transport errors

    @Test func envelopePrefixes() throws {
        let valid = try ShareCodec.encode(ShareFixture.minimalPayload()).text
        let body = String(valid.dropFirst(2))
        #expect(try ShareCodec.decode("1." + body) == ShareFixture.minimalPayload())
        #expect(ShareFixture.error(decoding: "2." + body) == .newerVersion(2))
        #expect(ShareFixture.error(decoding: "17." + body) == .newerVersion(17))
        #expect(ShareFixture.error(decoding: "999." + body) == .newerVersion(999))
        #expect(ShareFixture.error(decoding: "0." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "01." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "1000." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "v1." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "-1." + body) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: "１." + body) == .unsupportedVersion) // fullwidth digit
        #expect(ShareFixture.error(decoding: "") == .malformedEnvelope)
        #expect(ShareFixture.error(decoding: "1.") == .malformedEnvelope)
        #expect(ShareFixture.error(decoding: body) == .malformedEnvelope) // no prefix at all
        #expect(ShareFixture.error(decoding: "1." + body + "=") == .invalidBase64)
        #expect(ShareFixture.error(decoding: "1." + body + " ") == .invalidBase64)
        #expect(ShareFixture.error(decoding: "1.A") == .invalidBase64)
        #expect(ShareFixture.error(decoding: "1.Zh") == .invalidBase64) // non-canonical trailing bits
        #expect(ShareFixture.error(decoding: "1." + body + ".x") == .invalidBase64)
        let huge = "1." + String(repeating: "A", count: ShareLimits.maxEnvelopeBytes)
        #expect(ShareFixture.error(decoding: huge) == .envelopeTooLarge(byteCount: ShareLimits.maxEnvelopeBytes + 2))
    }

    @Test func payloadVersions() throws {
        var json = try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload())
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: json)) == nil)
        json = json.replacingOccurrences(of: #""v":1"#, with: #""v":2"#)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: json)) == .newerVersion(2))
        // A newer payload is reported as newer even if the rest of its shape is unknown.
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: #"{"v":3,"data":[1,2,3]}"#)) == .newerVersion(3))
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: #"{"v":0,"t":{}}"#)) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: #"{"v":-1}"#)) == .unsupportedVersion)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: #"{"v":"1"}"#)) == .malformedPayload(path: "v"))
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: #"{"t":{}}"#)) == .malformedPayload(path: "v"))
        for text in ["[]", "1", "null", "\"v\"", "{", "", "{\"v\":1", "{\"v\":1}}", #"{"v":1.5}"#, #"{"v":1e30}"#] {
            guard case .malformedPayload? = ShareFixture.error(decoding: try ShareFixture.envelope(json: text)) else {
                Issue.record("expected malformedPayload for \(text)")
                continue
            }
        }
        let error = ShareError.newerVersion(2)
        #expect(error.message == LocalizedText(key: "share.error.newerVersion"))
    }

    @Test func unknownKeysAreIgnoredWithinVersionOne() throws {
        var json = try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload())
        json = json.replacingOccurrences(of: #""v":1"#, with: #""v":1,"zz":{"future":true}"#)
        #expect(try ShareCodec.decode(ShareFixture.envelope(json: json)) == ShareFixture.minimalPayload())
    }

    @Test func zipBombIsStoppedAtTheLimit() throws {
        // 4 MB of spaces compress to a few KB; inflating stops after 1 MB.
        let bomb = [UInt8](repeating: UInt8(ascii: " "), count: 4 * 1_048_576)
        let envelope = try ShareFixture.envelope(bytes: bomb)
        #expect(envelope.utf8.count < 10_000)
        #expect(ShareFixture.error(decoding: envelope) == .decompressedTooLarge)

        // Exactly at the limit is accepted (valid JSON padded with whitespace); one byte more is not.
        let json = Array(try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload()).utf8)
        let padded = json + [UInt8](repeating: UInt8(ascii: " "), count: ShareLimits.maxJSONBytes - json.count)
        #expect(try ShareCodec.decode(ShareFixture.envelope(bytes: padded)) == ShareFixture.minimalPayload())
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(bytes: padded + [UInt8(ascii: " ")])) == .decompressedTooLarge)
    }

    @Test func corruptOrTruncatedStreamsFail() throws {
        let compressed = try ShareDeflate.compress(Array(try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload()).utf8))
        for cut in [1, 2, compressed.count / 2, compressed.count - 1] {
            let envelope = "1." + Base64URL.encode(Array(compressed.prefix(cut)))
            #expect(ShareFixture.error(decoding: envelope) == .decompressionFailed, "cut \(cut)")
        }
        #expect(ShareFixture.error(decoding: "1." + Base64URL.encode(compressed + [0])) == .decompressionFailed)
        #expect(ShareFixture.error(decoding: "1." + Base64URL.encode(compressed + compressed)) == .decompressionFailed)
        // A stored block header with a wrong length complement.
        #expect(ShareFixture.error(decoding: "1." + Base64URL.encode([0x01, 0x05, 0x00, 0x00, 0x00])) == .decompressionFailed)
        // Reserved block type 3.
        #expect(ShareFixture.error(decoding: "1." + Base64URL.encode([0x07, 0x00])) == .decompressionFailed)
    }

    @Test func invalidUTF8IsRejected() throws {
        let prefix = Array(#"{"v":1,"t":{"n":""#.utf8)
        let suffix = Array(#"","d":[1],"ts":{"k":"f","m":45},"dv":"grid","de":"compact"}}"#.utf8)
        #expect(try ShareCodec.decode(ShareFixture.envelope(bytes: prefix + Array("Škola".utf8) + suffix)).timetable.name == "Škola")
        let bad: [[UInt8]] = [[0x80], [0xC3], [0xC0, 0xAF], [0xE0, 0x80, 0xAF], [0xED, 0xA0, 0x80], [0xF5, 0x80, 0x80, 0x80],
                              [0xF4, 0x90, 0x80, 0x80], [0xFF], [0xC3, 0x28]]
        for bytes in bad {
            #expect(ShareFixture.error(decoding: try ShareFixture.envelope(bytes: prefix + bytes + suffix)) == .invalidUTF8, "\(bytes)")
        }
    }

    @Test func deepNestingIsRejectedBeforeDecoding() throws {
        let depth = 100_000
        let json = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: json)) == .malformedPayload(path: ""))
        let object = #"{"v":1,"zz":"# + String(repeating: #"{"a":"#, count: 20) + "1" + String(repeating: "}", count: 21)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: object)) == .malformedPayload(path: ""))
        // Brackets inside strings do not count.
        #expect(ShareCodec.nestingDepth(Array(#"{"a":"[[[[[[[[[[[[[[[[[[[[[[\"]]"}"#.utf8), limit: 16) == 1)
    }

    @Test func errorsMapToLocalizationKeys() {
        #expect(ShareError.invalidBase64.message.key == "share.error.damaged")
        #expect(ShareError.malformedPayload(path: "x").message.key == "share.error.damaged")
        #expect(ShareError.unsupportedVersion.message.key == "share.error.unsupportedVersion")
        #expect(ShareError.decompressedTooLarge.message.key == "share.error.tooLarge")
        #expect(ShareError.danglingReference(path: "l[0].s").message.key == "share.error.invalidContent")
        #expect(ShareError.tooMany(.lessons, count: 2001).message
                == LocalizedText(key: "share.error.tooMany.lessons", args: [.integer(2000)]))
        #expect(ShareError.tooMany(.bringList, count: 51).message.key == "share.error.invalidContent")
        #expect(ShareError.idCollision.message.key == "share.error.failed")
        #expect(ShareWarning.lessonsOnDisabledDays(count: 3).message
                == LocalizedText(key: "share.warning.lessonsOnDisabledDays", args: [.integer(3)]))
        #expect(Set(ShareError.allL10nKeys).count == ShareError.allL10nKeys.count)
        #expect(Set(ShareWarning.allL10nKeys).count == ShareWarning.allL10nKeys.count)
    }
}
