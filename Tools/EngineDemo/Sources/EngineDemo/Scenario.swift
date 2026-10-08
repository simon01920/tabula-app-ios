import Foundation
import TimetableCore

/// A fixed, deterministic sample scenario built and evaluated with the public `TimetableCore` API only:
/// a Slovak secondary school (gymnázium) with odd/even (A/B) weeks in Europe/Bratislava, evaluated at a fixed
/// "now" (Tue 2026-10-13 10:20). Every ID comes from `SequentialIDGenerator`, every timestamp from a
/// `HybridLogicalClock` fed with fixed instants, so the report is byte-for-byte reproducible.
struct Scenario {
    struct SubjectSeed {
        let short: String
        let name: String
        let emoji: String
        let room: String?
        let teacher: String
    }

    // Inputs
    let zone: TimeZone
    let context: CalendarContext
    let now: Date
    let today: LocalDate
    let onboardingInstant: Date
    let answers: OnboardingAnswers
    let preset: ProfilePreset
    let onboardedDB: TabulaDatabase
    let db: TabulaDatabase
    let timetable: Timetable
    let regularBell: BellSchedule
    let shortBell: BellSchedule
    let overrideDate: LocalDate

    // Engine results
    let resolver: ScheduleResolver
    let thisWeek: GridLayout
    let nextWeek: GridLayout
    let resolutions: [LocalDate: DayResolution]
    let todaySchedule: DaySchedule
    let nowNext: NowNext
    let timeBlocks: TimeBlockLayout
    let plannerInput: PlannerInput
    let plan: ReminderPlan
    let shareEnvelope: ShareEnvelope
    let shareWarnings: [ShareWarning]
    let decodedPayload: SharePayloadV1
    let sampleCode: ShortCode
    let inlineLink: String
    let codeLink: String
    let parsedLinkMatches: Bool
    let issues: [ValidationIssue]
    let jsonBytes: Int
    let prettyJSONBytes: Int
    let roundTripEqual: Bool

    static let seeds: [SubjectSeed] = [
        SubjectSeed(short: "SJL", name: "Slovenský jazyk a literatúra", emoji: "📖", room: "214", teacher: "Mgr. Kováčová"),
        SubjectSeed(short: "MAT", name: "Matematika", emoji: "➗", room: "214", teacher: "Mgr. Horváth"),
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

    // swiftlint:disable:next function_body_length
    static func build() throws -> Scenario {
        guard let zone = TimeZone(identifier: "Europe/Bratislava") else { throw DemoError.noTimeZone }
        func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day)! }
        func t(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }

        // Only used to turn the fixed wall-clock instants of the scenario into `Date`s; the engine itself gets the
        // settings-derived context below (asserted equal).
        let bootstrap = CalendarContext(timeZone: zone, firstWeekday: .monday)
        let onboardingInstant = bootstrap.date(d(2026, 9, 1), t(18))
        let editInstant = bootstrap.date(d(2026, 10, 12), t(7, 30))
        let today = d(2026, 10, 13)
        let now = bootstrap.date(today, t(10, 20))
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
        let context = CalendarContext(settings: db.settings, deviceTimeZone: zone, localeFirstWeekday: .monday)
        precondition(context == bootstrap, "settings-derived context differs from the bootstrap context")

        let timetable = db.timetables[0]
        let regularBell = db.bellSchedules[0]
        let periods = regularBell.lessonPeriods

        // Subjects: colours from the Classic palette pack, in order.
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

        // 2./3./5. Schedule engine ------------------------------------------------------------------------------
        guard let resolver = ScheduleResolver(database: db, timetableID: timetable.id, context: context) else {
            throw DemoError.noResolver
        }
        let thisWeek = GridLayout.week(containing: today, resolver: resolver)
        let nextWeek = GridLayout.week(containing: today.adding(days: 7), resolver: resolver)
        var resolutions: [LocalDate: DayResolution] = [:]
        for column in thisWeek.columns + nextWeek.columns {
            resolutions[column.date] = resolver.resolution(for: column.date)
        }
        let todaySchedule = resolver.day(today)
        let nowNext = resolver.nowAndNext(at: now)
        let timeBlocks = TimeBlockLayout.make(days: [todaySchedule, resolver.day(overrideDate)])

        // 6. Reminder planner -----------------------------------------------------------------------------------
        let horizonDays = 14
        // Occurrences for the horizon plus one day, so "pack tonight" sees the morning after the horizon's last evening.
        let window = DateInterval(start: context.startOfDay(today),
                                  end: context.startOfDay(today.adding(days: horizonDays + 2)))
        let occurrences = resolver.occurrences(in: window)
        let plannerInput = PlannerInput(
            now: now, context: context, settings: db.settings, rules: db.reminderRules, tasks: db.tasks,
            exams: db.exams, lessons: occurrences, packTonight: PackTonightDay.days(from: occurrences),
            horizonDays: horizonDays, canScheduleAlarms: false)
        let plan = ReminderPlanner.plan(plannerInput)

        // 7. Share -----------------------------------------------------------------------------------------------
        let (envelope, warnings) = try ShareExport.encode(from: db, timetableID: timetable.id, includeTasks: true)
        let decoded = try ShareCodec.decode(envelope.text)
        var rng = SplitMix64(seed: 20_261_013)
        let sampleCode = ShortCode.random(using: &rng)
        let inlineLink = ShareLink.inline(envelope: envelope.text).urlString()
        let codeLink = ShareLink.shortCode(sampleCode).urlString()
        let reparsed = try ShareLink.parse(envelope.route == .inline ? inlineLink : codeLink)
        let parsedLinkMatches = reparsed == (envelope.route == .inline
            ? ShareLink.inline(envelope: envelope.text) : ShareLink.shortCode(sampleCode))

        // 8. Validation + persistence -----------------------------------------------------------------------------
        let issues = db.validate()
        let json = try db.encoded()
        let pretty = try db.encoded(pretty: true)
        let roundTrip = try TabulaDatabase.decode(from: json)

        return Scenario(
            zone: zone, context: context, now: now, today: today, onboardingInstant: onboardingInstant,
            answers: answers, preset: ProfilePreset.for(.secondary), onboardedDB: onboarded, db: db,
            timetable: timetable, regularBell: regularBell, shortBell: shortBell, overrideDate: overrideDate,
            resolver: resolver, thisWeek: thisWeek, nextWeek: nextWeek, resolutions: resolutions,
            todaySchedule: todaySchedule, nowNext: nowNext, timeBlocks: timeBlocks, plannerInput: plannerInput,
            plan: plan, shareEnvelope: envelope, shareWarnings: warnings, decodedPayload: decoded,
            sampleCode: sampleCode, inlineLink: inlineLink, codeLink: codeLink, parsedLinkMatches: parsedLinkMatches,
            issues: issues, jsonBytes: json.count, prettyJSONBytes: pretty.count,
            roundTripEqual: roundTrip.canonicalized() == db.canonicalized())
    }
}

enum DemoError: Error, CustomStringConvertible {
    case noTimeZone
    case noResolver
    case usage

    var description: String {
        switch self {
        case .noTimeZone: return "Europe/Bratislava is not a known time zone on this system (install tzdata)."
        case .noResolver: return "ScheduleResolver could not be created for the sample timetable."
        case .usage: return "usage: EngineDemo <output.html> [Localizable.xcstrings]"
        }
    }
}

/// Deterministic RNG for the sample short code (SplitMix64; the demo must not depend on system randomness).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
