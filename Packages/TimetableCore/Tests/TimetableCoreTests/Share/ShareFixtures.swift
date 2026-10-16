import Foundation
import Testing
@testable import TimetableCore

/// Fixtures and helpers for the share codec tests (Stage 2D). Reuses Stage 1's `Fixture`, `TestRNG`, `TestClock`.
enum ShareFixture {
    static let secondaryTimetableID = Timetable.ID(UUID(uuidString: "5EC0DA77-0000-4000-8000-000000000001")!)
    static let universityTimetableID = Timetable.ID(UUID(uuidString: "0A1BE757-0000-4000-8000-000000000001")!)

    /// A realistic Slovak secondary-school (gymnázium) timetable: 14 subjects with teachers and rooms, a normal
    /// and a shortened bell schedule sharing period IDs, A/B weeks, 32 lessons, two terms, six holidays, plus
    /// three open homework tasks, one completed task and two exams (one completed).
    static func secondary() -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: 0x5EC0_0000)
        let meta = Fixture.meta()
        let tt = secondaryTimetableID
        let normal: BellSchedule.ID = ids.next(), short: BellSchedule.ID = ids.next()
        let periodIDs: [Period.ID] = (0..<10).map { _ in ids.next() }
        let times = [("08:00", "08:45"), ("08:45", "08:55"), ("08:55", "09:40"), ("09:40", "10:00"), ("10:00", "10:45"),
                     ("10:55", "11:40"), ("11:50", "12:35"), ("12:35", "13:05"), ("13:05", "13:50"), ("13:55", "14:40")]
        let kinds: [PeriodKind] = [.lesson, .breakTime, .lesson, .breakTime, .lesson, .lesson, .lesson, .lunch, .lesson, .lesson]
        let normalPeriods = zip(periodIDs, zip(times, kinds)).map { id, value in
            Period(id: id, start: Fixture.time(value.0.0), end: Fixture.time(value.0.1), kind: value.1)
        }
        let shortTimes = [("08:00", "08:30"), ("08:30", "08:35"), ("08:35", "09:05"), ("09:05", "09:15"), ("09:15", "09:45"),
                          ("09:50", "10:20"), ("10:25", "10:55"), ("10:55", "11:15"), ("11:15", "11:45"), ("11:50", "12:20")]
        let shortPeriods = zip(periodIDs, zip(shortTimes, kinds)).map { id, value in
            Period(id: id, start: Fixture.time(value.0.0), end: Fixture.time(value.0.1), kind: value.1)
        }
        let lessonPeriods = zip(periodIDs, kinds).filter { $0.1 == .lesson }.map(\.0) // 7 lesson periods

        let names: [(String, String, String, String, String)] = [
            ("Slovenský jazyk a literatúra", "SJL", "red", "Mgr. Kováčová", "204"),
            ("Anglický jazyk", "ANJ", "blue", "Mgr. Smith", "112"),
            ("Nemecký jazyk", "NEJ", "orange", "Mgr. Bauer", "113"),
            ("Matematika", "MAT", "indigo", "RNDr. Novák", "201"),
            ("Fyzika", "FYZ", "purple", "Mgr. Horváth", "Lab F"),
            ("Chémia", "CHE", "green", "Ing. Tóthová", "Lab CH"),
            ("Biológia", "BIO", "teal", "Mgr. Lukáč", "Lab B"),
            ("Dejepis", "DEJ", "brown", "PhDr. Varga", "105"),
            ("Geografia", "GEG", "cyan", "Mgr. Baláž", "106"),
            ("Informatika", "INF", "gray", "Ing. Kollár", "Učebňa INF"),
            ("Telesná a športová výchova", "TSV", "yellow", "Mgr. Molnár", "Telocvičňa"),
            ("Občianska náuka", "OBN", "pink", "Mgr. Szabóová", "107"),
            ("Etická výchova", "ETV", "teal", "Mgr. Krajčí", "108"),
            ("Umenie a kultúra", "UKL", "orange", "Mgr. Šimko", "Ateliér"),
        ]
        let classic = PalettePack.classic.colors
        // Manually ordered (P3-2): the list order, so the size budget includes the `o` keys.
        let subjects: [Subject] = names.enumerated().map { order, entry in
            let (name, short, color, teacher, room) = entry
            let paletteColor = classic.first { $0.nameKey.hasSuffix(".\(color)") }!
            return Subject(id: ids.next(), meta: meta, timetableID: tt, name: name, shortName: short,
                           color: paletteColor.value, colorName: .key(paletteColor.nameKey),
                           symbol: short == "TSV" ? .emoji("⚽️") : (short == "INF" ? .systemImage("desktopcomputer") : nil),
                           defaultRoom: room, defaultTeacher: teacher, sortIndex: order)
        }
        func subject(_ short: String) -> Subject.ID { subjects[names.firstIndex { $0.1 == short }!].id }

        let winter = Term(id: ids.next(), meta: meta, timetableID: tt, name: "1. polrok",
                          range: LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2027-01-31")))
        let summer = Term(id: ids.next(), meta: meta, timetableID: tt, name: "2. polrok",
                          range: LocalDateRange(start: Fixture.date("2027-02-01"), end: Fixture.date("2027-06-30")))

        // Week plan: (weekday, [subject short name per lesson period]); "FYZ/A" = week A only.
        let plan: [(Weekday, [String])] = [
            (.monday, ["SJL", "MAT", "ANJ", "FYZ/A", "DEJ", "TSV"]),
            (.tuesday, ["MAT", "NEJ", "SJL", "BIO", "GEG", "INF", "INF"]),
            (.wednesday, ["ANJ", "CHE/B", "MAT", "OBN", "SJL", "TSV"]),
            (.thursday, ["NEJ", "MAT", "FYZ", "BIO", "ETV", "UKL", "UKL"]),
            (.friday, ["SJL", "ANJ", "CHE", "DEJ", "GEG", "MAT"]),
        ]
        var lessons: [Lesson] = []
        for (weekday, slots) in plan {
            for (index, entry) in slots.enumerated() {
                let parts = entry.split(separator: "/").map(String.init)
                let cycleWeeks: Set<Int>? = parts.count == 2 ? [parts[1] == "A" ? 1 : 2] : nil
                let short = parts[0]
                lessons.append(Lesson(
                    id: ids.next(), meta: meta, timetableID: tt, subjectID: subject(short),
                    occurrence: LessonOccurrenceRule(day: .weekday(weekday), cycleWeeks: cycleWeeks),
                    slot: .period(lessonPeriods[index], span: 1),
                    validity: short == "UKL" ? .terms([summer.id]) : .always,
                    room: short == "TSV" && weekday == .wednesday ? "Ihrisko" : nil,
                    notes: short == "FYZ" && cycleWeeks != nil ? "Laboratórne cvičenie" : nil,
                    bringList: short == "TSV" ? ["Úbor", "Tenisky", "Fľaša s vodou"] : []))
            }
        }

        let breaks = [
            ("Jesenné prázdniny", "2026-10-29", "2026-10-30", BreakKind.vacation),
            ("Vianočné prázdniny", "2026-12-23", "2027-01-07", .vacation),
            ("Polročné prázdniny", "2027-02-01", "2027-02-01", .vacation),
            ("Jarné prázdniny", "2027-02-22", "2027-02-26", .vacation),
            ("Veľkonočné prázdniny", "2027-03-25", "2027-03-30", .holiday),
            ("Letné prázdniny", "2027-07-01", "2027-08-31", .vacation),
        ].map { name, start, end, kind in
            CalendarBreak(id: ids.next(), meta: meta, timetableID: nil, name: name,
                          range: LocalDateRange(start: Fixture.date(start), end: Fixture.date(end)), kind: kind)
        }

        let timetable = Timetable(
            id: tt, meta: meta, name: "3.A Gymnázium", emoji: "🏫", enabledDays: Weekday.workweek,
            rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0), labels: ["A", "B"])),
            timeStructure: .bellSchedule(defaultID: normal, perWeekday: [:]),
            fieldVisibility: FieldVisibility([.room, .teacher, .notes, .bringList]), defaultView: .grid, density: .compact,
            palettePackID: .classic, sortIndex: 0)
        let schedules = [
            BellSchedule(id: normal, meta: meta, timetableID: tt, name: "Normálny deň", periods: normalPeriods),
            BellSchedule(id: short, meta: meta, timetableID: tt, name: "Skrátené hodiny", periods: shortPeriods),
        ]
        let tasks = [
            TaskItem(id: ids.next(), meta: meta, title: "Slohová práca – úvaha", kind: .assignment, subjectID: subject("SJL"),
                     timetableID: tt, due: .date(Fixture.date("2026-10-12")), priority: .high, notes: "Min. 250 slov",
                     subtasks: [Subtask(id: ids.next(), meta: meta, title: "Osnova", sortIndex: 0),
                                Subtask(id: ids.next(), meta: meta, title: "Koncept", sortIndex: 1)]),
            TaskItem(id: ids.next(), meta: meta, title: "Pracovný zošit s. 42", subjectID: subject("MAT"),
                     due: .dateTime(Fixture.date("2026-10-08"), Fixture.time("08:00")),
                     linkedLesson: LessonLink(lessonID: lessons[1].id, date: Fixture.date("2026-10-12"))),
            TaskItem(id: ids.next(), meta: meta, title: "Slovíčka Unit 3", subjectID: subject("ANJ"), timetableID: tt,
                     due: .date(Fixture.date("2026-10-09")),
                     repeatRule: RepeatRule(frequency: .weekly, interval: 1, weekdays: [.wednesday, .monday])),
            TaskItem(id: ids.next(), meta: meta, title: "Hotová úloha", subjectID: subject("BIO"), timetableID: tt,
                     completedAt: Fixture.now),
        ]
        let exams = [
            Exam(id: ids.next(), meta: meta, timetableID: tt, subjectID: subject("MAT"), title: "Písomka – funkcie", kind: .test,
                 date: Fixture.date("2026-10-20"), start: Fixture.time("08:00"), end: Fixture.time("08:45"), room: "201",
                 topics: ["Lineárna funkcia", "Kvadratická funkcia"]),
            Exam(id: ids.next(), meta: meta, timetableID: tt, subjectID: subject("DEJ"), title: "Ústna odpoveď", kind: .oral,
                 date: Fixture.date("2026-09-20"), completedAt: Fixture.now),
        ]
        return TabulaDatabase(settings: AppSettings(meta: meta, profile: .secondary, activeTimetableID: tt),
                              timetables: [timetable], subjects: subjects, bellSchedules: schedules, lessons: lessons,
                              terms: [winter, summer], breaks: breaks, tasks: tasks, exams: exams)
    }

    /// A large university timetable (free-form times, two semesters): 45 courses with long names, ~360 lessons with
    /// rooms, buildings, teachers, types and notes, 12 breaks, 150 tasks and 40 exams. Deterministic (seeded).
    static func university() -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: 0x0A1B_0000)
        var rng = TestRNG(seed: 0x00C0_FFEE_2026)
        let meta = Fixture.meta()
        let tt = universityTimetableID
        let words = ["Pokročilé", "metódy", "strojového", "učenia", "Diskrétna", "matematika", "Teória", "grafov",
                     "Databázové", "systémy", "Počítačové", "siete", "Operačné", "Softvérové", "inžinierstvo",
                     "Algoritmy", "dátové", "štruktúry", "Kryptografia", "Paralelné", "programovanie", "Analýza",
                     "Numerická", "Pravdepodobnosť", "štatistika", "Logika", "Formálne", "jazyky", "automaty",
                     "Umelá", "inteligencia", "Grafika", "Bezpečnosť", "Distribuované", "Kompilátory"]
        func pick<T>(_ array: [T]) -> T { array[Int(rng.next() % UInt64(array.count))] }
        func phrase(_ count: Int) -> String { (0..<count).map { _ in pick(words) }.joined(separator: " ") }

        let winter = Term(id: ids.next(), meta: meta, timetableID: tt, name: "Zimný semester 2026/27",
                          range: LocalDateRange(start: Fixture.date("2026-09-21"), end: Fixture.date("2027-02-14")))
        let summer = Term(id: ids.next(), meta: meta, timetableID: tt, name: "Letný semester 2026/27",
                          range: LocalDateRange(start: Fixture.date("2027-02-15"), end: Fixture.date("2027-06-30")))
        let colors = PalettePack.all.flatMap(\.colors)
        let subjects: [Subject] = (0..<45).map { index in
            let color = colors[index % colors.count]
            return Subject(id: ids.next(), meta: meta, timetableID: tt, name: "\(phrase(4)) \(index + 1)",
                           shortName: "C\(100 + index)", color: color.value, colorName: .key(color.nameKey),
                           defaultRoom: "\(pick(["A", "B", "C", "BC", "M"]))-\(100 + Int(rng.next() % 400))",
                           defaultBuilding: pick(["FMFI UK Mlynská dolina", "Pavilón informatiky", "Pavilón matematiky"]),
                           defaultTeacher: "doc. \(pick(["Novák", "Horváth", "Kováč", "Varga", "Tóth", "Nagy", "Baláž"])), PhD.",
                           notes: index % 3 == 0 ? "Konzultácie: \(phrase(6))" : nil, sortIndex: index)
        }
        var lessons: [Lesson] = []
        for (index, subject) in subjects.enumerated() {
            let count = 6 + index % 5 // 6…10 sessions per course over both terms
            for session in 0..<count {
                let weekday = Weekday(rawValue: 1 + Int(rng.next() % 5))!
                let startMinute = 7 * 60 + 30 + Int(rng.next() % 20) * 30
                let duration = pick([90, 90, 100, 120, 180])
                let start = LocalTime(minuteOfDay: startMinute)!
                let end = LocalTime(minuteOfDay: min(startMinute + duration, 22 * 60))!
                lessons.append(Lesson(
                    id: ids.next(), meta: meta, timetableID: tt, subjectID: subject.id,
                    occurrence: LessonOccurrenceRule(day: .weekday(weekday), cycleWeeks: session % 4 == 3 ? [1] : nil),
                    slot: .time(start: start, end: end),
                    validity: .terms([session % 2 == 0 ? winter.id : summer.id]),
                    room: "\(pick(["F1", "F2", "M-II", "H-3", "I-9", "I-23", "A-108"]))",
                    building: session % 3 == 0 ? pick(["Pavilón informatiky", "Pavilón matematiky"]) : nil,
                    teacher: session % 2 == 1 ? "Mgr. \(pick(["Kráľ", "Lacko", "Bystrický", "Medveď"])), PhD." : nil,
                    lessonType: pick([.lecture, .seminar, .lab, .tutorial]),
                    notes: session % 5 == 0 ? phrase(8) : nil,
                    bringList: session % 7 == 0 ? ["Notebook", "Kalkulačka"] : []))
            }
        }
        let breaks: [CalendarBreak] = (0..<12).map { index in
            let start = Fixture.date("2026-10-01").adding(days: index * 21)
            return CalendarBreak(id: ids.next(), meta: meta, timetableID: index % 2 == 0 ? tt : nil,
                                 name: "Dekanské voľno \(index + 1)", range: LocalDateRange(start: start, end: start.adding(days: 1)),
                                 kind: index == 11 ? .examPeriod : .noSchool)
        }
        let tasks: [TaskItem] = (0..<150).map { index in
            TaskItem(id: ids.next(), meta: meta, title: "Úloha \(index + 1): \(phrase(3))",
                     kind: index % 4 == 0 ? .assignment : .homework, subjectID: subjects[index % subjects.count].id,
                     timetableID: index % 2 == 0 ? tt : nil,
                     due: .date(Fixture.date("2026-10-05").adding(days: index)),
                     priority: index % 10 == 0 ? .urgent : .normal, notes: index % 3 == 0 ? phrase(10) : nil,
                     subtasks: index % 5 == 0 ? [Subtask(id: ids.next(), meta: meta, title: "Časť A", sortIndex: 0),
                                                 Subtask(id: ids.next(), meta: meta, title: "Časť B", sortIndex: 1)] : [])
        }
        let exams: [Exam] = (0..<40).map { index in
            Exam(id: ids.next(), meta: meta, timetableID: tt, subjectID: subjects[index % subjects.count].id,
                 title: "Skúška \(index + 1)", kind: index % 2 == 0 ? .written : .oral,
                 date: Fixture.date("2027-01-10").adding(days: index), start: Fixture.time("09:00"), end: Fixture.time("12:00"),
                 room: "A-\(100 + index)", topics: [phrase(2), phrase(2)], notes: index % 4 == 0 ? phrase(12) : nil)
        }
        let timetable = Timetable(id: tt, meta: meta, name: "FMFI – Informatika, 2. ročník", emoji: "🎓",
                                  enabledDays: Weekday.workweek,
                                  rotation: .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: Fixture.date("2026-09-21"),
                                                                                                    cycleWeek: 1))),
                                  timeStructure: .freeForm(defaultDurationMinutes: 90), fieldVisibility: .all,
                                  defaultView: .timeBlocks, density: .comfortable)
        return TabulaDatabase(settings: AppSettings(meta: meta, profile: .university, activeTimetableID: tt),
                              timetables: [timetable], subjects: subjects, lessons: lessons, terms: [winter, summer],
                              breaks: breaks, tasks: tasks, exams: exams)
    }

    /// A one-scalar string built at run time (the compiler rejects noncharacter literals such as `\u{FDD0}`).
    static func scalar(_ value: UInt32) -> String { String(Unicode.Scalar(value)!) }

    /// A small valid payload built directly (no database).
    static func minimalPayload() -> SharePayloadV1 {
        SharePayloadV1(
            timetable: ShareTimetable(name: "Mini", enabledDays: [.monday, .tuesday],
                                      timeStructure: .bellSchedule(defaultIndex: 0, perWeekday: [:])),
            subjects: [ShareSubject(name: "Math", color: ColorValue(hex: "#E53935")!)],
            bellSchedules: [ShareBellSchedule(name: "Normal", periods: [
                SharePeriod(key: 0, start: Fixture.time("08:00"), end: Fixture.time("08:45")),
                SharePeriod(key: 1, start: Fixture.time("08:55"), end: Fixture.time("09:40")),
            ])],
            lessons: [ShareLesson(subject: 0, day: .weekday(.monday), slot: .period(key: 0, span: 1))])
    }

    /// Exported payload of a fixture database.
    static func payload(_ db: TabulaDatabase, _ id: Timetable.ID, includeTasks: Bool = false) throws -> SharePayloadV1 {
        try ShareExport.makePayload(from: db, timetableID: id, includeTasks: includeTasks).payload
    }

    /// An envelope wrapping arbitrary JSON text (bypasses the encoder, for hostile-payload tests).
    static func envelope(json: String) throws -> String {
        try envelope(bytes: Array(json.utf8))
    }

    /// An envelope wrapping arbitrary bytes as the decompressed JSON.
    static func envelope(bytes: [UInt8]) throws -> String {
        "1." + Base64URL.encode(try ShareDeflate.compress(bytes))
    }

    /// Canonical JSON text of a payload, skipping validation (to build invalid payload JSON).
    static func unvalidatedJSON(_ payload: SharePayloadV1) throws -> String {
        String(decoding: try TabulaJSON.makeEncoder().encode(payload), as: UTF8.self)
    }

    /// Decodes an envelope and returns the thrown `ShareError`, or `nil` when decoding succeeded.
    static func error(decoding envelope: String) -> ShareError? {
        do {
            _ = try ShareCodec.decode(envelope)
            return nil
        } catch {
            return error
        }
    }

    /// Validates a payload and returns the thrown `ShareError`, or `nil`.
    static func error(validating payload: SharePayloadV1) -> ShareError? {
        do {
            _ = try payload.validate()
            return nil
        } catch {
            return error
        }
    }

    /// Materializes `payload` into an empty database (fresh namespace) and returns the database.
    static func importIntoEmptyDatabase(_ payload: SharePayloadV1, namespace: UInt32 = 0x1E_0000) throws -> (TabulaDatabase, Timetable.ID) {
        var ids = SequentialIDGenerator(namespace: namespace)
        var clock = TestClock(node: 0xBEEF)
        let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now)
        let empty = TabulaDatabase(settings: AppSettings(meta: Fixture.meta()))
        return (try imported.inserted(into: empty), imported.timetable.id)
    }
}
