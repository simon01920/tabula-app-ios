// The English App Store preview scenario (`-TabulaSeed preview`): a fictional UK class, one plain week, no A/B
// rotation. Fixture data (like the Slovak scenarios), so not in the String Catalog.
// Reference instant: Tue 2026-11-10 10:20 Europe/London (= 10:20Z) — Mathematics now, Biology next.
import Foundation
import TimetableCore

extension SampleScenarios {
    /// Time zone of the preview scenario.
    public static let previewTimeZoneIdentifier = "Europe/London"

    /// London zone. Traps without a tz database entry (Linux without tzdata).
    public static var previewTimeZone: TimeZone {
        guard let zone = TimeZone(identifier: previewTimeZoneIdentifier) else {
            preconditionFailure("\(previewTimeZoneIdentifier) is not a known time zone on this system (install tzdata)")
        }
        return zone
    }

    /// Tue 2026-11-10.
    public static let previewToday = d(2026, 11, 10)

    /// Tue 2026-11-10 10:20 in London.
    public static var previewReferenceNow: Date {
        CalendarContext(timeZone: previewTimeZone, firstWeekday: .monday).date(previewToday, t(10, 20))
    }

    /// Builds the preview database (deterministic).
    // swiftlint:disable:next function_body_length
    /// `blank: true` stops after onboarding + the bell grid (the photo-import starting point).
    public static func preview(blank: Bool = false) -> TabulaDatabase {
        let context = CalendarContext(timeZone: previewTimeZone, firstWeekday: .monday)
        let onboardingInstant = context.date(d(2026, 9, 1), t(18))
        let editInstant = context.date(d(2026, 11, 9), t(19))
        var ids = SequentialIDGenerator(namespace: 0x7AB0_9E11)
        var clock = HybridLogicalClock(node: 0x9E11)

        let answers = OnboardingAnswers(
            profile: .secondary, timetableName: "Class 11B", timetableEmoji: "🏫", bellScheduleName: "Regular day",
            term: .init(name: "Autumn term 2026", range: LocalDateRange(start: d(2026, 9, 2), end: d(2026, 12, 18))),
            enabledReminderTargets: [.homework, .exam], localeFirstWeekday: .monday, hourCycle: .h24,
            timeZoneMode: .followDevice, palettePackID: .classic)
        var db = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: onboardingInstant)
        let timetable = db.timetables[0]

        // Bell schedule: the exact grid of the printable import photo (6 periods, 45 minutes).
        let times = [(8, 0, 8, 45), (8, 55, 9, 40), (9, 55, 10, 40), (10, 50, 11, 35), (11, 45, 12, 30), (13, 15, 14, 0)]
        let periods = times.map { Period(id: ids.next(), label: nil, start: t($0.0, $0.1), end: t($0.2, $0.3), kind: .lesson) }
        db.bellSchedules[0].periods = periods
        if blank { return db }

        struct Seed { let short, name, emoji, room, teacher: String }
        let seeds = [
            Seed(short: "Maths", name: "Mathematics", emoji: "📐", room: "204", teacher: "Ms Carter"),
            Seed(short: "Eng", name: "English", emoji: "📖", room: "112", teacher: "Mr Patel"),
            Seed(short: "Bio", name: "Biology", emoji: "🧬", room: "Lab 2", teacher: "Dr Okafor"),
            Seed(short: "Hist", name: "History", emoji: "🏛️", room: "118", teacher: "Mr Hughes"),
            Seed(short: "Chem", name: "Chemistry", emoji: "🧪", room: "Lab 1", teacher: "Ms Nguyen"),
            Seed(short: "Phys", name: "Physics", emoji: "⚛️", room: "Lab 3", teacher: "Mr Fraser"),
            Seed(short: "Geog", name: "Geography", emoji: "🌍", room: "120", teacher: "Ms Bailey"),
            Seed(short: "CS", name: "Computer Science", emoji: "💻", room: "IT 1", teacher: "Mr Ahmed"),
            Seed(short: "PE", name: "PE", emoji: "⚽", room: "Sports hall", teacher: "Ms Walker"),
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
        let grid: [(Weekday, [String?])] = [
            (.monday, ["Eng", "Maths", "Hist", "Chem", "PE", "Geog"]),
            (.tuesday, ["Hist", "Eng", "Maths", "Bio", "CS", "Phys"]),
            (.wednesday, ["Maths", "Phys", "Eng", "Geog", "Bio", "PE"]),
            (.thursday, ["Chem", "Maths", "Bio", "Hist", "Eng", "CS"]),
            (.friday, ["Bio", "Geog", "Maths", "Eng", "Hist", nil]),
        ]
        for (day, shorts) in grid {
            for (index, short) in shorts.enumerated() {
                guard let short else { continue }
                let value = Lesson(
                    id: ids.next(), meta: .created(at: clock.tick(now: onboardingInstant)), timetableID: timetable.id,
                    subjectID: subjects[short]!.id, occurrence: LessonOccurrenceRule(day: .weekday(day), cycleWeeks: nil),
                    slot: .period(periods[index].id, span: 1), room: nil, notes: nil, bringList: [])
                db.lessons.append(value)
                keyed["\(day.rawValue)-\(index + 1)-\(short)"] = value
            }
        }

        func meta() -> EntityMeta { .created(at: clock.tick(now: editInstant)) }
        let algebraDue = d(2026, 11, 11)   // next Mathematics lesson: Wed period 1
        let algebraID: TaskItem.ID = ids.next()
        let algebraMeta = meta()
        let subtasks = ["Questions 1–10", "Check answers"].enumerated().map { index, title in
            Subtask(id: ids.next(), meta: meta(), title: title, completedAt: nil, sortIndex: index)
        }
        db.tasks.append(TaskItem(
            id: algebraID, meta: algebraMeta, title: "Finish algebra exercises", kind: .homework,
            subjectID: subjects["Maths"]!.id, timetableID: timetable.id, due: .dateTime(algebraDue, t(8)),
            linkedLesson: LessonLink(lessonID: keyed["3-1-Maths"]!.id, date: algebraDue), subtasks: subtasks))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Read chapter 4", kind: .homework,
                                 subjectID: subjects["Eng"]!.id, timetableID: timetable.id, due: .date(d(2026, 11, 12))))
        db.tasks.append(TaskItem(id: ids.next(), meta: meta(), title: "Lab report draft", kind: .homework,
                                 subjectID: subjects["Bio"]!.id, timetableID: timetable.id, due: .date(d(2026, 11, 13))))

        db.exams.append(Exam(
            id: ids.next(), meta: meta(), timetableID: timetable.id, subjectID: subjects["Bio"]!.id,
            title: "Biology quiz", kind: .test, date: d(2026, 11, 13), start: periods[0].start, end: periods[0].end,
            room: "Lab 2", topics: ["Cells", "Photosynthesis"],
            reminderOverride: ReminderOverride(offsets: [.daysBefore(1, at: t(18))])))
        db.exams.append(Exam(
            id: ids.next(), meta: meta(), timetableID: timetable.id, subjectID: subjects["Hist"]!.id,
            title: "History test", kind: .test, date: d(2026, 11, 19), start: periods[3].start, end: periods[3].end,
            room: "118", topics: ["The Tudors"]))
        return db
    }
}
