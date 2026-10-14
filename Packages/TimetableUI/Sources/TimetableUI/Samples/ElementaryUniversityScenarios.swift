// Elementary (`-TabulaSeed elementary`) and university (`-TabulaSeed university`) scenarios.
// Same conventions as SecondaryScenario.swift: deterministic IDs/clocks, realistic Slovak user data.
import Foundation
import TimetableCore

extension SampleScenarios {
    // MARK: - Elementary

    /// Primary school (ZŠ, 3.A): 6 × 45 min bell schedule, no rotation, big tiles, a room change and a cancelled
    /// lesson on the reference day (Tue 2026-10-13), one homework, one dictation.
    public static func elementary() -> TabulaDatabase {
        let onboardingInstant = bootstrapContext.date(d(2026, 9, 1), t(18))
        let editInstant = bootstrapContext.date(d(2026, 10, 12), t(16))
        var ids = SequentialIDGenerator(namespace: 0x7AB0_E1E0)
        var clock = HybridLogicalClock(node: 0xE1E0)

        let answers = OnboardingAnswers(
            profile: .elementary, timetableName: "ZŠ – 3.A", timetableEmoji: "🎒", bellScheduleName: "Zvonenie",
            term: .init(name: "1. polrok 2026/27", range: LocalDateRange(start: d(2026, 9, 2), end: d(2027, 1, 31))),
            localeFirstWeekday: .monday, hourCycle: .h24)
        var db = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: onboardingInstant)
        let timetable = db.timetables[0]
        let periods = db.bellSchedules[0].lessonPeriods

        struct Seed { let short, name, emoji: String; let room: String?; let teacher: String }
        let classTeacher = "Mgr. Novotná"
        let seeds: [Seed] = [
            Seed(short: "SJL", name: "Slovenský jazyk", emoji: "📖", room: "3.A", teacher: classTeacher),
            Seed(short: "MAT", name: "Matematika", emoji: "➗", room: "3.A", teacher: classTeacher),
            Seed(short: "ANJ", name: "Anglický jazyk", emoji: "🗣️", room: "Jazyková učebňa", teacher: "Mgr. Hanková"),
            Seed(short: "PDA", name: "Prírodoveda", emoji: "🌱", room: "3.A", teacher: classTeacher),
            Seed(short: "VLA", name: "Vlastiveda", emoji: "🗺️", room: "3.A", teacher: classTeacher),
            Seed(short: "VYV", name: "Výtvarná výchova", emoji: "🎨", room: "3.A", teacher: classTeacher),
            Seed(short: "HUV", name: "Hudobná výchova", emoji: "🎵", room: "Hudobňa", teacher: "Mgr. Bartošová"),
            Seed(short: "TSV", name: "Telesná a športová výchova", emoji: "⚽", room: "Telocvičňa", teacher: "Mgr. Kučera"),
            Seed(short: "INF", name: "Informatika", emoji: "💻", room: "Učebňa INF", teacher: "Mgr. Šimko"),
        ]
        let palette = PalettePack.classic
        var subjects: [String: Subject] = [:]
        for (index, seed) in seeds.enumerated() {
            let colour = palette.colors[index % palette.colors.count]
            let subject = Subject(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                name: seed.name, shortName: seed.short, color: colour.value, colorName: .key(colour.nameKey),
                symbol: .emoji(seed.emoji), defaultRoom: seed.room, defaultTeacher: seed.teacher)
            subjects[seed.short] = subject
            db.subjects.append(subject)
        }
        var keyed: [String: Lesson] = [:]
        func lesson(_ weekday: Weekday, _ period: Int, _ short: String, bring: [String] = []) {
            let value = Lesson(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                subjectID: subjects[short]!.id, occurrence: .every(weekday),
                slot: .period(periods[period - 1].id, span: 1), bringList: bring)
            db.lessons.append(value)
            keyed["\(weekday.rawValue)-\(period)"] = value
        }
        let gym = ["cvičebný úbor", "tenisky"]
        let paints = ["vodové farby", "štetce", "obrus"]
        let week: [(Weekday, [String])] = [
            (.monday, ["SJL", "MAT", "ANJ", "PDA", "TSV"]),
            (.tuesday, ["MAT", "SJL", "VLA", "VYV", "HUV"]),
            (.wednesday, ["SJL", "MAT", "INF", "ANJ"]),
            (.thursday, ["MAT", "SJL", "PDA", "TSV", "VYV"]),
            (.friday, ["SJL", "MAT", "VLA", "HUV"]),
        ]
        for (weekday, shorts) in week {
            for (index, short) in shorts.enumerated() {
                lesson(weekday, index + 1, short,
                       bring: short == "TSV" ? gym : short == "VYV" ? paints : [])
            }
        }
        // Reference day: art moves to the school library, music is cancelled (teacher on a trip).
        let referenceDay = today
        for change in [OverrideChange.modifyLesson(keyed["2-4"]!.id, LessonPatch(room: "Knižnica")),
                       .cancelLesson(keyed["2-5"]!.id)] {
            db.overrides.append(ScheduleOverride(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                                 timetableID: timetable.id, date: referenceDay, change: change))
        }
        db.tasks.append(TaskItem(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                 title: "Prečítať rozprávku na s. 24", kind: .homework, subjectID: subjects["SJL"]!.id,
                                 timetableID: timetable.id, due: .date(d(2026, 10, 14))))
        db.exams.append(Exam(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)), timetableID: timetable.id,
                             subjectID: subjects["SJL"]!.id, title: "Diktát – vybrané slová po B", kind: .written,
                             date: d(2026, 10, 20)))
        return db
    }

    // MARK: - University

    /// University (FIIT STU, 2nd year Bc.): free-form 90-minute blocks, odd/even weeks, buildings, lecture /
    /// seminar / lab types, a winter semester, one cancelled lecture next week, an assignment and an exam.
    public static func university() -> TabulaDatabase {
        let onboardingInstant = bootstrapContext.date(d(2026, 9, 18), t(20))
        let editInstant = bootstrapContext.date(d(2026, 10, 12), t(21))
        var ids = SequentialIDGenerator(namespace: 0x7AB0_0E10)
        var clock = HybridLogicalClock(node: 0x0E10)

        let rotation = RotationScheme.weekCycle(WeekCycle(
            length: 2,
            anchor: .isoWeekParity(policy: WeekParity.defaultPolicy(for: .university, regionCode: "SK"), offset: 0),
            labels: ["Nepárny", "Párny"]))
        let answers = OnboardingAnswers(
            profile: .university, timetableName: "FIIT – 2. ročník", timetableEmoji: "🎓", bellScheduleName: "Bloky",
            rotation: rotation,
            term: .init(name: "Zimný semester 2026/27", range: LocalDateRange(start: d(2026, 9, 21), end: d(2026, 12, 18))),
            localeFirstWeekday: .monday, hourCycle: .h24)
        var db = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: onboardingInstant)
        let timetable = db.timetables[0]

        struct Seed { let short, name, emoji, teacher: String }
        let seeds: [Seed] = [
            Seed(short: "MA", name: "Matematická analýza", emoji: "📈", teacher: "doc. RNDr. Kováč, PhD."),
            Seed(short: "LA", name: "Lineárna algebra", emoji: "🧮", teacher: "Mgr. Pekárová, PhD."),
            Seed(short: "PROG", name: "Procedurálne programovanie", emoji: "💻", teacher: "Ing. Tomko, PhD."),
            Seed(short: "DBS", name: "Databázové systémy", emoji: "🗄️", teacher: "doc. Ing. Lacko, PhD."),
            Seed(short: "PS", name: "Pravdepodobnosť a štatistika", emoji: "📊", teacher: "RNDr. Ďurišová, PhD."),
            Seed(short: "AP", name: "Akademické písanie", emoji: "✍️", teacher: "Mgr. Rybárová"),
        ]
        let palette = PalettePack.classic
        var subjects: [String: Subject] = [:]
        for (index, seed) in seeds.enumerated() {
            let colour = palette.colors[(index * 2) % palette.colors.count]
            let subject = Subject(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                name: seed.name, shortName: seed.short, color: colour.value, colorName: .key(colour.nameKey),
                symbol: .emoji(seed.emoji), defaultBuilding: "FIIT", defaultTeacher: seed.teacher)
            subjects[seed.short] = subject
            db.subjects.append(subject)
        }
        var keyed: [String: Lesson] = [:]
        func block(_ weekday: Weekday, _ start: LocalTime, _ short: String, _ type: LessonType, room: String,
                   weeks: Set<Int>? = nil, teacher: String? = nil, notes: String? = nil) {
            let value = Lesson(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                subjectID: subjects[short]!.id, occurrence: LessonOccurrenceRule(day: .weekday(weekday), cycleWeeks: weeks),
                slot: .time(start: start, end: start.adding(minutes: 90)!), room: room, teacher: teacher,
                lessonType: type, notes: notes)
            db.lessons.append(value)
            keyed["\(weekday.rawValue)-\(short)-\(type.rawValue)"] = value
        }
        block(.monday, t(8), "MA", .lecture, room: "Aula Minor")
        block(.monday, t(10), "LA", .seminar, room: "-1.65", teacher: "Ing. Bednár")
        block(.monday, t(14), "PROG", .lab, room: "3.14", teacher: "Ing. Holub")
        block(.tuesday, t(9), "DBS", .lecture, room: "Aula Minor")
        block(.tuesday, t(11), "PS", .lecture, room: "Aula Minor")
        block(.tuesday, t(13), "DBS", .lab, room: "4.23", weeks: [1], teacher: "Ing. Krajčí")
        block(.tuesday, t(13), "PS", .seminar, room: "-1.40", weeks: [2], teacher: "Mgr. Fedor")
        block(.wednesday, t(8), "PROG", .lecture, room: "Aula Minor")
        block(.wednesday, t(10), "MA", .seminar, room: "-1.65", teacher: "Mgr. Šebo")
        block(.thursday, t(9), "LA", .lecture, room: "Aula Minor")
        block(.thursday, t(13), "AP", .seminar, room: "2.05", notes: "Konzultácie k semestrálnej práci")
        block(.friday, t(8), "PS", .lab, room: "3.14", weeks: [1], teacher: "Mgr. Fedor")

        // The Monday lecture next week is cancelled (dean's day).
        db.overrides.append(ScheduleOverride(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                             timetableID: timetable.id, date: d(2026, 10, 19),
                                             change: .cancelLesson(keyed["1-MA-lecture"]!.id)))
        db.tasks.append(TaskItem(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                 title: "Zadanie 2 – návrh databázy", kind: .assignment, subjectID: subjects["DBS"]!.id,
                                 timetableID: timetable.id, due: .dateTime(d(2026, 10, 20), t(23, 59)),
                                 priority: .high))
        db.exams.append(Exam(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)), timetableID: timetable.id,
                             subjectID: subjects["MA"]!.id, title: "Priebežný test 1", kind: .midterm,
                             date: d(2026, 10, 28), start: t(8), end: t(9, 30), room: "Aula Minor", building: "FIIT",
                             topics: ["limity", "derivácie"]))
        // Phase 3 C1: the winter exam period (an `examPeriod` break, so the Exams tab groups the finals under it; it
        // lies after the semester, so the shown weeks keep their lessons) with two finals inside it.
        db.breaks.append(CalendarBreak(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                       timetableID: timetable.id, name: "Skúškové obdobie – zimný semester",
                                       range: LocalDateRange(start: d(2027, 1, 4), end: d(2027, 2, 12)),
                                       kind: .examPeriod))
        db.exams.append(Exam(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)), timetableID: timetable.id,
                             subjectID: subjects["MA"]!.id, title: "Skúška – Matematická analýza", kind: .final,
                             date: d(2027, 1, 12), start: t(8), end: t(11), room: "Aula Minor", building: "FIIT",
                             topics: ["limity", "derivácie", "integrály", "rady"]))
        db.exams.append(Exam(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)), timetableID: timetable.id,
                             subjectID: subjects["DBS"]!.id, title: "Skúška – Databázové systémy", kind: .oral,
                             date: d(2027, 1, 21), start: t(9), room: "4.23", building: "FIIT"))
        return db
    }
}
