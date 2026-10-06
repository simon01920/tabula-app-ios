import Foundation
import Testing
@testable import TimetableCore

@Suite("Share validation: references, vocabularies, ranges, duplicates, limits, hostile text")
struct ShareValidationTests {
    /// The error `mutate(minimalPayload)` causes, checked both by `validate()` and through a full envelope.
    private func error(_ mutate: (inout SharePayloadV1) -> Void) throws -> ShareError? {
        var payload = ShareFixture.minimalPayload()
        mutate(&payload)
        let direct = ShareFixture.error(validating: payload)
        let viaEnvelope = ShareFixture.error(decoding: try ShareFixture.envelope(json: ShareFixture.unvalidatedJSON(payload)))
        #expect(direct == viaEnvelope, "validate() and decode disagree")
        return viaEnvelope
    }

    /// The error of the minimal payload's JSON after a textual replacement.
    private func error(replacing target: String, with replacement: String) throws -> ShareError? {
        let json = try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload())
        #expect(json.contains(target), "fixture JSON lacks \(target)")
        return ShareFixture.error(decoding: try ShareFixture.envelope(json: json.replacingOccurrences(of: target, with: replacement)))
    }

    @Test func minimalPayloadIsValid() throws {
        #expect(try error { _ in } == nil)
        #expect(try ShareFixture.minimalPayload().validate().isEmpty)
    }

    // MARK: References

    @Test func danglingReferences() throws {
        #expect(try error { $0.lessons[0].subject = 1 } == .danglingReference(path: "l[0].s"))
        #expect(try error { $0.lessons[0].subject = -1 } == .danglingReference(path: "l[0].s"))
        #expect(try error { $0.lessons[0].slot = .period(key: 7, span: 1) } == .danglingReference(path: "l[0].p"))
        #expect(try error { $0.lessons[0].validity = .terms([0]) } == .danglingReference(path: "l[0].vt"))
        #expect(try error { $0.timetable.timeStructure = .bellSchedule(defaultIndex: 1, perWeekday: [:]) }
                == .danglingReference(path: "t.ts.d"))
        #expect(try error { $0.timetable.timeStructure = .bellSchedule(defaultIndex: 0, perWeekday: [.friday: 3]) }
                == .danglingReference(path: "t.ts.w.5"))
        #expect(try error { $0.bellSchedules = [] } == .danglingReference(path: "t.ts.d"))
        #expect(try error {
            $0.includesTasks = true
            $0.tasks = [ShareTask(title: "T", subject: 4)]
        } == .danglingReference(path: "k[0].s"))
        #expect(try error {
            $0.includesTasks = true
            $0.tasks = [ShareTask(title: "T", linkedLesson: ShareLessonLink(lesson: 1, date: Fixture.date("2026-10-05")))]
        } == .danglingReference(path: "k[0].ll"))
        #expect(try error {
            $0.includesTasks = true
            $0.exams = [ShareExam(title: "E", subject: 9, date: Fixture.date("2026-10-05"))]
        } == .danglingReference(path: "x[0].s"))
    }

    // MARK: Duplicates

    @Test func duplicates() throws {
        #expect(try error { $0.bellSchedules[0].periods[1].key = 0 } == .duplicate(path: "b[0].p[1].k"))
        #expect(try error(replacing: #""d":[1,2]"#, with: #""d":[1,2,1]"#) == .duplicate(path: "t.d"))
        #expect(try error(replacing: #""w":1}"#, with: #""w":1,"cw":[1,1]}"#) == .duplicate(path: "l[0].cw"))
        #expect(try error(replacing: #""w":1}"#, with: #""w":1,"vt":[0,0]}"#) == .duplicate(path: "l[0].vt"))
        #expect(try error(replacing: #""dv":"grid""#, with: #""dv":"grid","fv":["room","room"]"#) == .duplicate(path: "t.fv"))
    }

    // MARK: Time and date ranges

    @Test func timeAndDateRanges() throws {
        #expect(try error { $0.bellSchedules[0].periods[0].end = Fixture.time("08:00") } == .invalidTimeRange(path: "b[0].p[0]"))
        #expect(try error { $0.bellSchedules[0].periods[0].end = Fixture.time("07:00") } == .invalidTimeRange(path: "b[0].p[0]"))
        #expect(try error { $0.lessons[0].slot = .time(start: Fixture.time("10:00"), end: Fixture.time("10:00")) }
                == .invalidTimeRange(path: "l[0]"))
        #expect(try error {
            $0.includesTasks = true
            $0.exams = [ShareExam(title: "E", date: Fixture.date("2026-10-05"), start: Fixture.time("09:00"), end: Fixture.time("08:00"))]
        } == .invalidTimeRange(path: "x[0]"))
        let backwards = LocalDateRange(start: Fixture.date("2027-01-31"), end: Fixture.date("2026-09-01"))
        #expect(try error { $0.terms = [ShareTerm(name: "T", range: backwards)] } == .invalidDateRange(path: "r[0]"))
        #expect(try error { $0.breaks = [ShareBreak(name: "B", range: backwards)] } == .invalidDateRange(path: "h[0]"))
        #expect(try error { $0.lessons[0].validity = .range(backwards) } == .invalidDateRange(path: "l[0].vr"))
        // Dates are limited to 1970…2199.
        let ancient = LocalDateRange(start: Fixture.date("1969-12-31"), end: Fixture.date("2026-01-01"))
        #expect(try error { $0.terms = [ShareTerm(name: "T", range: ancient)] } == .invalidValue(path: "r[0].a"))
        #expect(try error {
            $0.includesTasks = true
            $0.exams = [ShareExam(title: "E", date: Fixture.date("9999-12-31"))]
        } == .invalidValue(path: "x[0].d"))
        #expect(try error(replacing: #""a":"08:00""#, with: #""a":"24:00""#) == .malformedPayload(path: "b[0].p[0].a"))
        #expect(try error(replacing: #""a":"08:00""#, with: #""a":"8:00""#) == .malformedPayload(path: "b[0].p[0].a"))
    }

    // MARK: Values

    @Test func outOfRangeValues() throws {
        func weekCycle(_ length: Int, _ anchor: WeekCycleAnchor = .isoWeekParity(policy: .strict, offset: 0)) -> RotationScheme {
            .weekCycle(WeekCycle(length: length, anchor: anchor))
        }
        #expect(try error { $0.timetable.rotation = weekCycle(7) } == .invalidValue(path: "t.ro.n"))
        #expect(try error { $0.timetable.rotation = weekCycle(1) } == .invalidValue(path: "t.ro.n"))
        #expect(try error { $0.timetable.rotation = weekCycle(2, .isoWeekParity(policy: .continuous, offset: 2)) }
                == .invalidValue(path: "t.ro.a.o"))
        #expect(try error { $0.timetable.rotation = weekCycle(2, .isoWeekParity(policy: .continuous, offset: Int.max)) }
                == .invalidValue(path: "t.ro.a.o"))
        #expect(try error { $0.timetable.rotation = weekCycle(3, .referenceWeek(date: Fixture.date("2026-09-01"), cycleWeek: 0)) }
                == .invalidValue(path: "t.ro.a.w"))
        #expect(try error {
            $0.timetable.rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0),
                                                         labels: Array(repeating: "x", count: 11)))
        } == .invalidValue(path: "t.ro.lb"))
        let dayCycle = DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01"), anchorIndex: 0)
        #expect(try error { $0.timetable.rotation = .dayCycle(dayCycle) } == .invalidValue(path: "t.ro.i"))
        var noDays = DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01"))
        noDays.schoolDays = []
        #expect(try error { $0.timetable.rotation = .dayCycle(noDays) } == .invalidValue(path: "t.ro.sd"))
        // Day keys must match the rotation.
        #expect(try error { $0.timetable.rotation = .dayCycle(DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01"))) }
                == .invalidValue(path: "l[0].w"))
        #expect(try error { $0.lessons[0].day = .cycleDay(1) } == .invalidValue(path: "l[0].c"))
        #expect(try error {
            $0.timetable.rotation = .dayCycle(DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01")))
            $0.lessons[0].day = .cycleDay(7)
        } == .invalidValue(path: "l[0].c"))
        #expect(try error {
            $0.timetable.rotation = weekCycle(2)
            $0.lessons[0].cycleWeeks = [3]
        } == .invalidValue(path: "l[0].cw"))
        #expect(try error { $0.lessons[0].cycleWeeks = [7] } == .invalidValue(path: "l[0].cw"))
        #expect(try error { $0.lessons[0].slot = .period(key: 0, span: 0) } == .invalidValue(path: "l[0].n"))
        #expect(try error { $0.lessons[0].slot = .period(key: 0, span: 41) } == .invalidValue(path: "l[0].n"))
        #expect(try error { $0.bellSchedules[0].periods[1].key = -1 } == .invalidValue(path: "b[0].p[1].k"))
        #expect(try error { $0.timetable.timeStructure = .freeForm(defaultDurationMinutes: 0) } == .invalidValue(path: "t.ts.m"))
        #expect(try error { $0.timetable.timeStructure = .freeForm(defaultDurationMinutes: 1440) } == .invalidValue(path: "t.ts.m"))
        #expect(try error {
            $0.includesTasks = true
            $0.tasks = [ShareTask(title: "T", repeatRule: RepeatRule(frequency: .daily, interval: 0))]
        } == .invalidValue(path: "k[0].rp.i"))
        #expect(try error { $0.subjects[0].symbol = .systemImage("Function Key") } == .invalidValue(path: "s[0].si"))
        #expect(try error { $0.subjects[0].symbol = .emoji("") } == .invalidValue(path: "s[0].se"))
        #expect(try error { $0.subjects[0].colorName = .key("palette classic") } == .invalidValue(path: "s[0].ck"))
        #expect(try error { $0.timetable.emoji = "" } == .invalidValue(path: "t.e"))
        #expect(try error { $0.lessons[0].lessonType = LessonType(rawValue: "lab work") } == .invalidValue(path: "l[0].ty"))
        #expect(try error { $0.lessons[0].lessonType = LessonType(rawValue: String(repeating: "a", count: 41)) }
                == .invalidValue(path: "l[0].ty"))
        // Tasks without "Include tasks" cannot be encoded (the encoder would drop them), so check `validate()` only.
        var notIncluded = ShareFixture.minimalPayload()
        notIncluded.tasks = [ShareTask(title: "not included")]
        #expect(ShareFixture.error(validating: notIncluded) == .invalidValue(path: "k"))
        #expect(throws: ShareError.invalidValue(path: "k")) { try ShareCodec.encode(notIncluded) }
        #expect(try error(replacing: #""ts":{"d":0,"k":"b"}"#, with: #""ts":{"d":0,"k":"b","w":{"05":0}}"#)
                == .invalidValue(path: "t.ts.w"))
        #expect(try error(replacing: #""ts":{"d":0,"k":"b"}"#, with: #""ts":{"d":0,"k":"b","w":{"8":0}}"#)
                == .invalidValue(path: "t.ts.w"))
    }

    @Test func closedUnionsAndExclusiveKeyGroupsAreStrict() throws {
        let cases: [(String, String, String)] = [
            (#""w":1}"#, #""w":1,"c":1}"#, "l[0].w"),          // weekday and cycle day
            (#""s":0,"w":1}"#, #""s":0}"#, "l[0].w"),           // neither
            (#""p":0,"s":0"#, #""p":0,"a":"08:00","s":0"#, "l[0].p"),   // period and start
            (#""p":0,"s":0"#, #""s":0"#, "l[0].p"),             // no slot
            (#""w":1}"#, #""w":1,"vt":[],"vr":{"a":"2026-01-01","z":"2026-01-02"}}"#, "l[0].vt"),
            (#""n":"Math""#, #""n":"Math","ck":"palette.classic.color.red","cl":"Red""#, "s[0].ck"),
            (#""n":"Math""#, #""n":"Math","se":"x","si":"x""#, "s[0].se"),
            (#""ts":{"d":0,"k":"b"}"#, #""ts":{"d":0,"k":"x"}"#, "t.ts.k"),
            (#""dv":"grid""#, #""dv":"grid","ro":{"k":"q"}"#, "t.ro.k"),
            (#""dv":"grid""#, #""dv":"grid","ro":{"k":"w","n":2,"a":{"k":"zz"}}"#, "t.ro.a.k"),
        ]
        for (target, replacement, path) in cases {
            #expect(try error(replacing: target, with: replacement) == .malformedPayload(path: path), "\(replacement)")
        }
        // A time without a due date; a closed enum value this version does not know.
        var payload = ShareFixture.minimalPayload()
        payload.includesTasks = true
        payload.tasks = [ShareTask(title: "T")]
        let json = try ShareFixture.unvalidatedJSON(payload)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: json.replacingOccurrences(of: #""n":"T""#, with: #""n":"T","dt":"08:00""#)))
                == .malformedPayload(path: "k[0].dt"))
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: json.replacingOccurrences(of: #""n":"T""#, with: #""n":"T","pr":"critical""#)))
                == .malformedPayload(path: "k[0].pr"))
        #expect(try error(replacing: #""de":"comfortable""#, with: #""de":"spacious""#) == .malformedPayload(path: "t.de"))
        #expect(try error(replacing: #""w":1}"#, with: #""w":8}"#) == .malformedPayload(path: "l[0].w"))
        #expect(try error(replacing: ##""c":"#E53935""##, with: #""c":"red""#) == .malformedPayload(path: "s[0].c"))
    }

    // MARK: Limits

    @Test func countLimits() throws {
        let subject = ShareSubject(name: "S", color: .black)
        #expect(try error { $0.subjects = Array(repeating: subject, count: 201) } == .tooMany(.subjects, count: 201))
        #expect(try error { $0.subjects = Array(repeating: subject, count: 200) } == nil)
        let lesson = ShareFixture.minimalPayload().lessons[0]
        #expect(try error { $0.lessons = Array(repeating: lesson, count: 2001) } == .tooMany(.lessons, count: 2001))
        #expect(try error { $0.lessons = Array(repeating: lesson, count: 2000) } == nil)
        let schedule = ShareFixture.minimalPayload().bellSchedules[0]
        #expect(try error { $0.bellSchedules = Array(repeating: schedule, count: 21) } == .tooMany(.bellSchedules, count: 21))
        #expect(try error {
            $0.bellSchedules[0].periods = (0..<41).map {
                SharePeriod(key: $0, start: LocalTime(minuteOfDay: $0 * 20)!, end: LocalTime(minuteOfDay: $0 * 20 + 15)!)
            }
        } == .tooMany(.periods, count: 41))
        let term = ShareTerm(name: "T", range: LocalDateRange(day: Fixture.date("2026-09-01")))
        #expect(try error { $0.terms = Array(repeating: term, count: 21) } == .tooMany(.terms, count: 21))
        let holiday = ShareBreak(name: "B", range: LocalDateRange(day: Fixture.date("2026-09-01")))
        #expect(try error { $0.breaks = Array(repeating: holiday, count: 201) } == .tooMany(.breaks, count: 201))
        #expect(try error {
            $0.includesTasks = true
            $0.tasks = Array(repeating: ShareTask(title: "T"), count: 1001)
        } == .tooMany(.tasks, count: 1001))
        #expect(try error {
            $0.includesTasks = true
            $0.exams = Array(repeating: ShareExam(title: "E", date: Fixture.date("2026-10-01")), count: 1001)
        } == .tooMany(.exams, count: 1001))
        #expect(try error { $0.lessons[0].bringList = Array(repeating: "x", count: 51) } == .tooMany(.bringList, count: 51))
        #expect(try error { $0.lessons[0].bringList = Array(repeating: "x", count: 50) } == nil)
        #expect(try error {
            $0.includesTasks = true
            $0.tasks = [ShareTask(title: "T", subtasks: Array(repeating: "s", count: 51))]
        } == .tooMany(.subtasks, count: 51))
        #expect(try error {
            $0.includesTasks = true
            $0.exams = [ShareExam(title: "E", date: Fixture.date("2026-10-01"), topics: Array(repeating: "t", count: 51))]
        } == .tooMany(.topics, count: 51))
    }

    // MARK: Hostile text

    @Test(arguments: [
        "\u{0}", "\u{7}", "\u{8}", "\u{1B}[31m", "\u{7F}", "\u{85}", "\u{9B}", "\n", "\r", "\t", "\u{2028}", "\u{2029}",
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
        "\u{FFF9}", ShareFixture.scalar(0xFFFE), ShareFixture.scalar(0xFFFF), ShareFixture.scalar(0xFDD0),
        ShareFixture.scalar(0x1FFFE), ShareFixture.scalar(0x10FFFF),
    ])
    func forbiddenCharactersInNamesAreRejected(_ bad: String) throws {
        #expect(try error { $0.subjects[0].name = "Math\(bad)" } == .invalidCharacters(path: "s[0].n"))
        #expect(try error { $0.timetable.name = "\(bad)evil" } == .invalidCharacters(path: "t.n"))
        #expect(try error { $0.lessons[0].bringList = ["ok", "x\(bad)"] } == .invalidCharacters(path: "l[0].br[1]"))
    }

    @Test func notesAllowLineBreaksAndTabsOnly() throws {
        #expect(try error { $0.subjects[0].notes = "Line 1\nLine 2\tTabbed" } == nil)
        #expect(try error { $0.subjects[0].notes = "Line 1\r\nLine 2" } == .invalidCharacters(path: "s[0].no"))
        #expect(try error { $0.subjects[0].notes = "abc\u{202E}def" } == .invalidCharacters(path: "s[0].no"))
        #expect(try error { $0.subjects[0].notes = "abc\u{0}" } == .invalidCharacters(path: "s[0].no"))
    }

    @Test func overlongTextIsRejected() throws {
        let tenK = String(repeating: "A", count: 10_000)
        #expect(try error { $0.subjects[0].name = tenK } == .stringTooLong(path: "s[0].n", length: 10_000))
        #expect(try error { $0.subjects[0].name = String(repeating: "é", count: 101) } == .stringTooLong(path: "s[0].n", length: 101))
        #expect(try error { $0.subjects[0].name = String(repeating: "é", count: 100) } == nil)
        // Length counts Unicode scalars: a decomposed "é" is 2.
        #expect(try error { $0.subjects[0].name = String(repeating: "e\u{301}", count: 51) } == .stringTooLong(path: "s[0].n", length: 102))
        // Zalgo: one grapheme with thousands of combining marks.
        #expect(try error { $0.subjects[0].name = "Z" + String(repeating: "\u{336}", count: 5000) }
                == .stringTooLong(path: "s[0].n", length: 5001))
        #expect(try error { $0.subjects[0].notes = String(repeating: "n", count: 4001) } == .stringTooLong(path: "s[0].no", length: 4001))
        #expect(try error { $0.subjects[0].notes = String(repeating: "n", count: 4000) } == nil)
        #expect(try error { $0.lessons[0].bringList = [String(repeating: "b", count: 101)] }
                == .stringTooLong(path: "l[0].br[0]", length: 101))
        #expect(try error { $0.timetable.emoji = String(repeating: "😀", count: 17) } == .stringTooLong(path: "t.e", length: 17))
    }

    @Test func textIsDataAndNeverInterpreted() throws {
        let tricky = ["%@ %d %n %s %1$@", "{{name}} ${HOME} $(rm -rf /)", "<script>alert(1)</script>", "'; DROP TABLE subjects;--",
                      "palette.classic.color.red", "share.error.invalidLink", "not an override but text",
                      "👩‍🔬 Lab", "שלום עולם", "مرحبا", "\u{200F}RTL mark is fine"]
        var payload = ShareFixture.minimalPayload()
        payload.subjects = tricky.map { ShareSubject(name: $0, color: .black, colorName: .literal($0), defaultRoom: $0, notes: $0) }
        payload.lessons[0].room = tricky[0]
        let decoded = try ShareCodec.decode(ShareCodec.encode(payload).text)
        #expect(decoded == payload)
        let (db, _) = try ShareFixture.importIntoEmptyDatabase(decoded)
        #expect(db.subjects.map(\.name) == tricky)
        #expect(db.subjects.map(\.colorName) == tricky.map { .literal($0) }) // a literal that looks like a key stays literal
        #expect(db.lessons[0].room == tricky[0])
    }

    // MARK: Open vocabularies and warnings

    @Test func unknownOpenVocabularyValuesArePreserved() throws {
        var payload = ShareFixture.minimalPayload()
        payload.timetable.defaultView = TimetableViewKind(rawValue: "kanban")
        payload.timetable.palettePackID = PalettePackID(rawValue: "neon")
        payload.timetable.fieldVisibility = [.room, LessonField(rawValue: "zoomLink")]
        payload.bellSchedules[0].periods[1].kind = PeriodKind(rawValue: "assembly")
        payload.lessons[0].lessonType = LessonType(rawValue: "workshop")
        payload.lessons.append(ShareLesson(subject: 0, day: .weekday(.tuesday), slot: .period(key: 1, span: 1),
                                           lessonType: LessonType(rawValue: "workshop")))
        payload.breaks = [ShareBreak(name: "Strike", range: LocalDateRange(day: Fixture.date("2026-11-17")), kind: BreakKind(rawValue: "strike"))]
        payload.includesTasks = true
        payload.tasks = [ShareTask(title: "T", kind: TaskKind(rawValue: "project"),
                                   repeatRule: RepeatRule(frequency: RepeatFrequency(rawValue: "yearly")))]
        payload.exams = [ShareExam(title: "E", kind: ExamKind(rawValue: "viva"), date: Fixture.date("2027-01-20"))]
        let warnings = try payload.validate()
        #expect(warnings == [
            .unknownValue(field: "lessonField", value: "zoomLink"), .unknownValue(field: "timetableView", value: "kanban"),
            .unknownValue(field: "palettePack", value: "neon"), .unknownValue(field: "periodKind", value: "assembly"),
            .unknownValue(field: "breakKind", value: "strike"), .unknownValue(field: "lessonType", value: "workshop"),
            .unknownValue(field: "taskKind", value: "project"), .unknownValue(field: "repeatFrequency", value: "yearly"),
            .unknownValue(field: "examKind", value: "viva"),
        ]) // one warning per distinct value, in validation order
        let decoded = try ShareCodec.decode(ShareCodec.encode(payload).text)
        #expect(decoded == payload)
        let (db, _) = try ShareFixture.importIntoEmptyDatabase(decoded)
        #expect(db.timetables[0].defaultView.rawValue == "kanban")
        #expect(db.bellSchedules[0].periods[1].kind.rawValue == "assembly")
        #expect(db.lessons.allSatisfy { $0.lessonType?.rawValue == "workshop" })
        #expect(db.breaks[0].kind.rawValue == "strike")
        #expect(db.tasks[0].kind.rawValue == "project" && db.tasks[0].repeatRule?.frequency.rawValue == "yearly")
        #expect(db.exams[0].kind.rawValue == "viva")
    }

    @Test func importWarnings() throws {
        var payload = ShareFixture.minimalPayload()
        payload.subjects[0].colorName = .key("palette.neon.color.glow")
        payload.bellSchedules[0].periods[1].start = Fixture.time("08:30") // overlaps period 0
        payload.lessons.append(ShareLesson(subject: 0, day: .weekday(.saturday), slot: .period(key: 1, span: 1)))
        payload.lessons.append(ShareLesson(subject: 0, day: .weekday(.sunday), slot: .period(key: 1, span: 1)))
        #expect(try payload.validate() == [.unknownColorName(subjectIndex: 0), .overlappingPeriods(scheduleIndex: 0),
                                            .lessonsOnDisabledDays(count: 2)])
        let preview = try ShareImport.preview(payload)
        #expect(preview.warnings.count == 3)
        let (db, _) = try ShareFixture.importIntoEmptyDatabase(payload)
        #expect(db.subjects[0].colorName == nil) // unknown palette key dropped, colour kept
        #expect(db.subjects[0].color == payload.subjects[0].color)

        payload.lessons = []
        #expect(try payload.validate().contains(.noLessons))
    }

    // MARK: Accepted payloads are valid databases

    @Test func everyFixtureImportsAsAnErrorFreeDatabase() throws {
        for (db, id) in [(ShareFixture.secondary(), ShareFixture.secondaryTimetableID),
                         (ShareFixture.university(), ShareFixture.universityTimetableID),
                         (Fixture.fullDatabase(), Fixture.fullDatabase().timetables[0].id),
                         (Fixture.fullDatabase(), Fixture.fullDatabase().timetables[1].id)] {
            let payload = try ShareFixture.payload(db, id, includeTasks: true)
            let (imported, _) = try ShareFixture.importIntoEmptyDatabase(payload)
            let errors = imported.validate().filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
