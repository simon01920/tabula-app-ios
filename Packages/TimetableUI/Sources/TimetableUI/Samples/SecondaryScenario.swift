// The secondary-school scenario (`-TabulaSeed secondary`), extracted verbatim from
// Tools/EngineDemo/Sources/EngineDemo/Scenario.swift so that the engine report and the app screenshots show the
// same data. Changing anything here changes docs/screenshots/current/engine-demo.html (regenerate it with
// `bash scripts/engine-demo.sh`); the ID/clock call order is part of the output.
import Foundation
import TimetableCore

/// A Slovak secondary school (gymnázium, 2.B) with odd/even (A/B) weeks, a short-day override on Thursday
/// 2026-10-15, homework and exams.
public struct SecondaryScenario: Sendable {
    /// One subject of the scenario.
    public struct SubjectSeed: Sendable {
        public let short: String
        public let name: String
        public let emoji: String
        public let room: String?
        public let teacher: String
    }

    /// Onboarding answers used.
    public let answers: OnboardingAnswers
    /// The database straight after onboarding (before subjects, lessons, overrides …).
    public let onboardedDatabase: TabulaDatabase
    /// The full database.
    public let database: TabulaDatabase
    /// The settings-derived calendar context (Europe/Bratislava, Monday).
    public let context: CalendarContext
    /// The only timetable.
    public let timetable: Timetable
    /// The regular bell schedule.
    public let regularBell: BellSchedule
    /// The short-day bell schedule used by the override.
    public let shortBell: BellSchedule
    /// Date carrying the overrides (Thu 2026-10-15).
    public let overrideDate: LocalDate
    /// Onboarding instant (2026-09-01 18:00).
    public let onboardingInstant: Date

    /// The subjects, in creation order.
    public static let seeds: [SubjectSeed] = [
        SubjectSeed(short: "SJL", name: "Slovenský jazyk a literatúra", emoji: "📖", room: "214", teacher: "Mgr. Kováčová"),
        SubjectSeed(short: "MAT", name: "Matematika", emoji: "📐", room: "214", teacher: "Mgr. Horváth"),
        SubjectSeed(short: "ANJ", name: "Anglický jazyk", emoji: "🗣️", room: "JAZ-2", teacher: "Mgr. Baláž"),
        SubjectSeed(short: "FYZ", name: "Fyzika", emoji: "⚛️", room: "Lab FYZ", teacher: "RNDr. Tóth"),
        SubjectSeed(short: "CHE", name: "Chémia", emoji: "🧪", room: "Lab CHE", teacher: "Ing. Vargová"),
        SubjectSeed(short: "BIO", name: "Biológia", emoji: "🧬", room: "214", teacher: "Mgr. Lukáčová"),
        SubjectSeed(short: "DEJ", name: "Dejepis", emoji: "🏛️", room: "214", teacher: "PhDr. Molnár"),
        SubjectSeed(short: "GEO", name: "Geografia", emoji: "🌍", room: "214", teacher: "Mgr. Szabová"),
        SubjectSeed(short: "INF", name: "Informatika", emoji: "💻", room: "INF-1", teacher: "Ing. Kollár"),
        SubjectSeed(short: "TSV", name: "Telesná a športová výchova", emoji: "⚽", room: "Telocvičňa", teacher: "Mgr. Hudák"),
        SubjectSeed(short: "NEJ", name: "Nemecký jazyk", emoji: "💬", room: "JAZ-1", teacher: "Mgr. Németh"),
        SubjectSeed(short: "ETV", name: "Etická výchova", emoji: "🤝", room: "214", teacher: "Mgr. Králová"),
    ]
}

extension SampleScenarios {
    /// Builds the secondary scenario (deterministic).
    // swiftlint:disable:next function_body_length
    public static func secondary() -> SecondaryScenario {
        let bootstrap = bootstrapContext
        let onboardingInstant = bootstrap.date(d(2026, 9, 1), t(18))
        let editInstant = bootstrap.date(d(2026, 10, 12), t(7, 30))
        let overrideDate = d(2026, 10, 15)

        var ids = SequentialIDGenerator(namespace: 0x7AB0_DE30)
        var clock = HybridLogicalClock(node: 0xDE30)

        // 1. Onboarding ---------------------------------------------------------------------------------------
        let rotation = RotationScheme.weekCycle(WeekCycle(
            length: 2,
            anchor: .isoWeekParity(policy: WeekParity.defaultPolicy(for: .secondary, regionCode: "SK"), offset: 0),
            labels: ["A", "B"]))
        let answers = OnboardingAnswers(
            profile: .secondary, timetableName: "Gymnázium – 2.B", timetableEmoji: "🏫",
            bellScheduleName: "Bežný deň", rotation: rotation,
            term: .init(name: "1. polrok 2026/27", range: LocalDateRange(start: d(2026, 9, 2), end: d(2027, 1, 31))),
            enabledReminderTargets: [.homework, .exam, .packTonight],
            localeFirstWeekday: .monday, hourCycle: .h24, timeZoneMode: .followDevice, palettePackID: .classic)
        let onboarded = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock,
                                                              now: onboardingInstant)
        var db = onboarded
        let context = CalendarContext(settings: db.settings, deviceTimeZone: timeZone, localeFirstWeekday: .monday)
        precondition(context == bootstrap, "settings-derived context differs from the bootstrap context")

        let timetable = db.timetables[0]
        let regularBell = db.bellSchedules[0]
        let periods = regularBell.lessonPeriods

        // Subjects: colours from the Classic palette pack, in order.
        let palette = PalettePack.classic
        var subjects: [String: Subject] = [:]
        for (index, seed) in SecondaryScenario.seeds.enumerated() {
            let colour = palette.colors[index % palette.colors.count]
            let subject = Subject(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                name: seed.name, shortName: seed.short, color: colour.value, colorName: .key(colour.nameKey),
                symbol: .emoji(seed.emoji), defaultRoom: seed.room, defaultTeacher: seed.teacher)
            subjects[seed.short] = subject
            db.subjects.append(subject)
        }

        // Lessons (a realistic gymnázium week; a few only in week A = cycle week 1 or week B = 2).
        var keyed: [String: Lesson] = [:]
        func lesson(_ weekday: Weekday, _ period: Int, _ short: String, span: Int = 1, weeks: Set<Int>? = nil,
                    room: String? = nil, bring: [String] = [], notes: String? = nil) {
            let value = Lesson(
                id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                subjectID: subjects[short]!.id, occurrence: LessonOccurrenceRule(day: .weekday(weekday), cycleWeeks: weeks),
                slot: .period(periods[period - 1].id, span: span), room: room, notes: notes, bringList: bring)
            db.lessons.append(value)
            keyed["\(weekday.rawValue)-\(period)-\(short)"] = value
        }
        let sportsKit = ["športový úbor", "prezuvky do telocvične"]
        // Monday
        lesson(.monday, 1, "SJL"); lesson(.monday, 2, "MAT"); lesson(.monday, 3, "ANJ"); lesson(.monday, 4, "FYZ")
        lesson(.monday, 5, "DEJ"); lesson(.monday, 6, "TSV", bring: sportsKit)
        // Tuesday
        lesson(.tuesday, 1, "MAT"); lesson(.tuesday, 2, "CHE"); lesson(.tuesday, 3, "SJL"); lesson(.tuesday, 4, "BIO")
        lesson(.tuesday, 5, "NEJ"); lesson(.tuesday, 6, "GEO")
        lesson(.tuesday, 7, "INF", weeks: [1], notes: "Len v týždni A")
        lesson(.tuesday, 7, "ETV", weeks: [2], notes: "Len v týždni B")
        // Wednesday (double Informatika)
        lesson(.wednesday, 1, "ANJ"); lesson(.wednesday, 2, "SJL"); lesson(.wednesday, 3, "MAT")
        lesson(.wednesday, 4, "INF", span: 2, notes: "Projekt: webová stránka triedy"); lesson(.wednesday, 6, "DEJ")
        // Thursday
        lesson(.thursday, 1, "FYZ"); lesson(.thursday, 2, "MAT")
        lesson(.thursday, 3, "CHE", bring: ["laboratórny plášť", "ochranné okuliare"])
        lesson(.thursday, 4, "ANJ"); lesson(.thursday, 5, "SJL"); lesson(.thursday, 6, "TSV", bring: sportsKit)
        // Friday (labs alternate by week)
        lesson(.friday, 1, "BIO"); lesson(.friday, 2, "GEO"); lesson(.friday, 3, "NEJ"); lesson(.friday, 4, "MAT")
        lesson(.friday, 5, "BIO", weeks: [1], room: "Lab BIO", bring: ["zošit na laboratórne práce"])
        lesson(.friday, 5, "FYZ", weeks: [2], notes: "Laboratórne cvičenie")
        lesson(.friday, 6, "ETV", weeks: [1])

        // Autumn holidays (outside the shown weeks; counted in the entity totals and the share payload).
        db.breaks.append(CalendarBreak(id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)),
                                       timetableID: nil, name: "Jesenné prázdniny",
                                       range: LocalDateRange(start: d(2026, 10, 29), end: d(2026, 10, 30)),
                                       kind: .holiday))

        // 4. Overrides ------------------------------------------------------------------------------------------
        // Short-day schedule: a copy of the regular schedule *with the same period IDs* (BellSchedule docs) and
        // 30-minute lessons.
        let shortTimes = BellScheduleTemplate(firstStart: t(8), lessonMinutes: 30, breakMinutes: [5, 10, 5],
                                              count: periods.count).lessonTimes()
        let shortPeriods = zip(periods, shortTimes).map { period, time in
            Period(id: period.id, label: period.label, start: time.start, end: time.end, kind: .lesson)
        }
        let shortBell = BellSchedule(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                     timetableID: timetable.id, name: "Skrátené vyučovanie", periods: shortPeriods)
        db.bellSchedules.append(shortBell)
        func override(_ change: OverrideChange) {
            db.overrides.append(ScheduleOverride(id: ids.next(), meta: .created(at: clock.tick(now: editInstant)),
                                                 timetableID: timetable.id, date: overrideDate, change: change))
        }
        override(.useBellSchedule(shortBell.id))
        override(.cancelLesson(keyed["4-4-ANJ"]!.id))
        override(.modifyLesson(keyed["4-2-MAT"]!.id, LessonPatch(room: "Aula", teacher: "Mgr. Novák (suplovanie)")))
        override(.addLesson(OneOffLesson(subjectID: subjects["INF"]!.id, slot: .period(periods[6].id, span: 1),
                                         notes: "Konzultácia k projektu")))

        // 6. Tasks, exams ---------------------------------------------------------------------------------------
        func meta() -> EntityMeta { .created(at: clock.tick(now: editInstant)) }
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Slovná zásoba – Unit 4", kind: .homework,
                                 subjectID: subjects["ANJ"]!.id, timetableID: timetable.id, due: .date(d(2026, 10, 14))))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Pracovný list – kvadratické rovnice",
                                 kind: .homework, subjectID: subjects["MAT"]!.id, timetableID: timetable.id,
                                 due: .date(d(2026, 10, 15))))
        db.tasks.append(TaskItem(
            id: ids.next(), meta: meta(), title: "Slohová práca: úvaha", kind: .homework,
            subjectID: subjects["SJL"]!.id, timetableID: timetable.id, due: .dateTime(d(2026, 10, 19), t(8)),
            reminderOverride: ReminderOverride(offsets: [.daysBefore(1, at: t(17)), .minutesBefore(30)],
                                               tier: .timeSensitive)))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Referát – Veľká Morava", kind: .homework,
                                 subjectID: subjects["DEJ"]!.id, timetableID: timetable.id, due: .date(d(2026, 10, 16)),
                                 completedAt: editInstant))
        db.exams.append(Exam(id: ids.next(), meta: meta(), timetableID: timetable.id, subjectID: subjects["CHE"]!.id,
                             title: "Písomka – organická chémia", kind: .test, date: d(2026, 10, 22),
                             start: t(10), end: t(10, 45), room: "Lab CHE", topics: ["alkány", "alkény"]))
        db.exams.append(Exam(id: ids.next(), meta: meta(), timetableID: timetable.id, subjectID: subjects["BIO"]!.id,
                             title: "Test – stavba bunky", kind: .test, date: d(2026, 10, 27), start: t(8),
                             reminderOverride: ReminderOverride(tier: .alarm)))

        // 7. Phase 3 C1 cross-feature scenarios (appended after everything above, so the earlier IDs/clock ticks and
        // the engine report's entities keep their values). Relative to the reference day Tue 2026-10-13:
        //   overdue (due Mon 12th), due today with 2/5 subtasks + weekly repeat, a high-priority assignment next week
        //   linked to one lesson occurrence, a completed task due today (no badge), a past History exam (Mon 12th).
        let yesterday = d(2026, 10, 12)
        let eveningBefore = bootstrap.date(yesterday, t(19))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Laboratórny protokol – hustota telies",
                                 kind: .homework, subjectID: subjects["FYZ"]!.id, timetableID: timetable.id,
                                 due: .date(yesterday)))
        let vocabularyID: TaskItem.ID = ids.next()
        let vocabularyMeta = meta()
        let steps = ["Slovíčka 1–10", "Slovíčka 11–20", "Gramatika: Perfekt", "Cvičenie 4 v pracovnom zošite",
                     "Nahrať výslovnosť"]
        var vocabularySubtasks: [Subtask] = []
        for (index, title) in steps.enumerated() {
            vocabularySubtasks.append(Subtask(id: ids.next(), meta: meta(), title: title,
                                              completedAt: index < 2 ? eveningBefore : nil, sortIndex: index))
        }
        db.tasks.append(TaskItem(id: vocabularyID, meta: vocabularyMeta, title: "Nemčina – Lektion 3",
                                 kind: .homework, subjectID: subjects["NEJ"]!.id, timetableID: timetable.id,
                                 due: .date(today), notes: "Každý utorok nová lekcia.",
                                 repeatRule: RepeatRule(frequency: .weekly, interval: 1, weekdays: [.tuesday]),
                                 subtasks: vocabularySubtasks))
        let projectDate = d(2026, 10, 21)
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Projekt – prvá verzia webovej stránky triedy",
                                 kind: .assignment, subjectID: subjects["INF"]!.id, timetableID: timetable.id,
                                 due: .date(projectDate),
                                 linkedLesson: LessonLink(lessonID: keyed["3-4-INF"]!.id, date: projectDate),
                                 priority: .high))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Prečítať kapitolu Bunka", kind: .homework,
                                 subjectID: subjects["BIO"]!.id, timetableID: timetable.id, due: .date(today),
                                 completedAt: eveningBefore))
        db.exams.append(Exam(id: ids.next(), meta: meta(), timetableID: timetable.id, subjectID: subjects["DEJ"]!.id,
                             title: "Písomka – Veľká Morava", kind: .test, date: yesterday,
                             start: periods[4].start, end: periods[4].end, room: "214",
                             topics: ["Samova ríša", "Cyril a Metod"]))

        return SecondaryScenario(answers: answers, onboardedDatabase: onboarded, database: db, context: context,
                                 timetable: timetable, regularBell: regularBell, shortBell: shortBell,
                                 overrideDate: overrideDate, onboardingInstant: onboardingInstant)
    }
}
