import Foundation

/// "Use sample data" content for a freshly onboarded timetable.
///
/// Sample text (subject names, a homework title, an exam title, a bring-list item) is defined as catalog
/// keys and turned into user text through the injected `localize` closure, so the persisted entities hold
/// ordinary, editable user text in the user's language while core contains no user-facing strings.
/// Rooms/buildings are language-neutral codes ("101", "A1.02").
public enum SampleData {
    /// The generated entities.
    public struct Content: Hashable, Sendable {
        /// Subjects (one per sample subject).
        public var subjects: [Subject]
        /// Recurring lessons.
        public var lessons: [Lesson]
        /// One sample homework.
        public var tasks: [TaskItem]
        /// One sample exam.
        public var exams: [Exam]

        /// `database` with this content appended.
        public func merged(into database: TabulaDatabase) -> TabulaDatabase {
            var copy = database
            copy.subjects += subjects
            copy.lessons += lessons
            copy.tasks += tasks
            copy.exams += exams
            return copy
        }
    }

    struct SubjectSeed {
        let name: String
        let symbol: String
    }

    /// Sample subjects per profile (catalog key suffixes after `sample.subject.`, plus an emoji).
    static func seeds(for profile: UserProfile) -> [SubjectSeed] {
        func seed(_ name: String, _ symbol: String) -> SubjectSeed { SubjectSeed(name: name, symbol: symbol) }
        switch profile.effective {
        case .elementary:
            return [seed("mathematics", "➗"), seed("nativeLanguage", "📖"), seed("foreignLanguage", "🗣️"),
                    seed("science", "🔬"), seed("art", "🎨"), seed("music", "🎵"), seed("physicalEducation", "⚽")]
        case .secondary:
            return [seed("mathematics", "➗"), seed("nativeLanguage", "📖"), seed("foreignLanguage", "🗣️"),
                    seed("physics", "⚛️"), seed("chemistry", "🧪"), seed("biology", "🧬"), seed("history", "🏛️"),
                    seed("geography", "🌍"), seed("informatics", "💻"), seed("physicalEducation", "⚽")]
        case .university:
            return [seed("calculus", "📈"), seed("linearAlgebra", "🧮"), seed("programming", "💻"),
                    seed("databases", "🗄️"), seed("statistics", "📊"), seed("academicWriting", "✍️")]
        default: // .other and (never reached) unknown profiles
            return [seed("mathematics", "➗"), seed("nativeLanguage", "📖"), seed("foreignLanguage", "🗣️"),
                    seed("history", "🏛️"), seed("physicalEducation", "⚽")]
        }
    }

    /// Catalog key of a sample subject name.
    static func subjectKey(_ name: String) -> String { "sample.subject.\(name)" }
    /// Catalog key of the sample homework title.
    static let homeworkTitleKey = "sample.task.homework"
    /// Catalog key of the sample exam title.
    static let examTitleKey = "sample.exam.title"
    /// Catalog key of the sample bring-list item for physical education.
    static let sportsKitKey = "sample.bring.sportsKit"

    /// Every catalog key `make` may request, sorted (for the String Catalog and DOMAIN_MODEL.md).
    public static var allKeys: [String] {
        let subjects = UserProfile.knownValues.flatMap { seeds(for: $0) }.map { subjectKey($0.name) }
        return Array(Set(subjects + [homeworkTitleKey, examTitleKey, sportsKitKey])).sorted()
    }

    /// Lessons per school day in the sample timetable.
    static func lessonsPerDay(for profile: UserProfile) -> Int {
        switch profile.effective {
        case .elementary: return 5
        case .secondary: return 6
        case .university: return 3
        default: return 5 // .other
        }
    }

    /// Builds sample subjects, a week of lessons, one homework and one exam for `timetable`.
    ///
    /// - Parameters:
    ///   - bellSchedule: the timetable's default bell schedule when it uses one (lessons go into its lesson
    ///     periods); `nil` → explicit times based on the free-form default duration (90 min if unknown).
    ///   - palette: colours for the subjects, assigned in order.
    ///   - today: the user's current date; the homework is due on the next school day, the exam a week later.
    ///   - localize: resolves a catalog key into user text in the current language.
    public static func make<G: IDGenerator, C: TimestampClock>(
        profile: UserProfile, timetable: Timetable, bellSchedule: BellSchedule?, palette: PalettePack = .classic,
        today: LocalDate, localize: (LocalizedText) -> String, ids: inout G, clock: inout C, now: Date
    ) -> Content {
        let seeds = seeds(for: profile)
        var subjects: [Subject] = []
        for (index, seed) in seeds.enumerated() {
            let color = palette.colors[index % palette.colors.count]
            let isUniversity = profile == .university
            subjects.append(Subject(
                id: ids.next(), meta: .created(at: clock.tick(now: now)), timetableID: timetable.id,
                name: localize(LocalizedText(key: subjectKey(seed.name))), color: color.value,
                colorName: .key(color.nameKey), symbol: .emoji(seed.symbol),
                defaultRoom: isUniversity ? "\(index % 2 == 0 ? "A" : "B")1.0\(index + 1)" : String(101 + index),
                defaultBuilding: isUniversity ? (index % 2 == 0 ? "A" : "B") : nil))
        }

        let days: [DayKey]
        switch timetable.rotation {
        case .dayCycle(let cycle): days = (1...max(1, cycle.length)).map { .cycleDay($0) }
        case .none, .weekCycle: days = timetable.enabledDays.sorted().map { .weekday($0) }
        }

        let slots = makeSlots(profile: profile, timetable: timetable, bellSchedule: bellSchedule)
        var lessons: [Lesson] = []
        let lessonTypes: [LessonType] = [.lecture, .seminar, .lab]
        for (dayIndex, day) in days.enumerated() {
            for (slotIndex, slot) in slots.enumerated() {
                let seedIndex = (dayIndex * 2 + slotIndex) % seeds.count
                let isPE = seeds[seedIndex].name == "physicalEducation"
                lessons.append(Lesson(
                    id: ids.next(), meta: .created(at: clock.tick(now: now)), timetableID: timetable.id,
                    subjectID: subjects[seedIndex].id, occurrence: LessonOccurrenceRule(day: day), slot: slot,
                    lessonType: profile == .university ? lessonTypes[(dayIndex + slotIndex) % lessonTypes.count] : nil,
                    bringList: isPE ? [localize(LocalizedText(key: sportsKitKey))] : []))
            }
        }

        let schoolDays = timetable.enabledDays.isEmpty ? Weekday.workweek : timetable.enabledDays
        let homeworkDue = nextSchoolDay(after: today, in: schoolDays)
        let examDate = nextSchoolDay(after: today.adding(days: 6), in: schoolDays)
        let task = TaskItem(
            id: ids.next(), meta: .created(at: clock.tick(now: now)),
            title: localize(LocalizedText(key: homeworkTitleKey)), kind: profile == .university ? .assignment : .homework,
            subjectID: subjects.first?.id, timetableID: timetable.id, due: .date(homeworkDue))
        let exam = Exam(
            id: ids.next(), meta: .created(at: clock.tick(now: now)), timetableID: timetable.id,
            subjectID: subjects.count > 1 ? subjects[1].id : subjects.first?.id,
            title: localize(LocalizedText(key: examTitleKey)), kind: profile == .university ? .written : .test,
            date: examDate)
        return Content(subjects: subjects, lessons: lessons, tasks: [task], exams: [exam])
    }

    /// The first date after `date` whose weekday is in `days` (within a week; `date + 1` if `days` is empty).
    static func nextSchoolDay(after date: LocalDate, in days: Set<Weekday>) -> LocalDate {
        for offset in 1...7 where days.contains(date.adding(days: offset).weekday) {
            return date.adding(days: offset)
        }
        return date.adding(days: 1)
    }

    private static func makeSlots(profile: UserProfile, timetable: Timetable, bellSchedule: BellSchedule?) -> [LessonSlot] {
        let count = lessonsPerDay(for: profile)
        if let bellSchedule, !bellSchedule.lessonPeriods.isEmpty {
            return bellSchedule.lessonPeriods.prefix(count).map { .period($0.id, span: 1) }
        }
        var duration = 90
        if case .freeForm(let minutes) = timetable.timeStructure, (1..<LocalTime.minutesPerDay).contains(minutes) {
            duration = minutes
        }
        var slots: [LessonSlot] = []
        var start = 8 * 60
        while slots.count < count, let startTime = LocalTime(minuteOfDay: start),
              let endTime = LocalTime(minuteOfDay: start + duration) {
            slots.append(.time(start: startTime, end: endTime))
            start += duration + 15
        }
        return slots
    }
}
