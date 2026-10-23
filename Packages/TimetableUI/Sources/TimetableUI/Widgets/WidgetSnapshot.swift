// The compact, versioned data the app hands to its widgets (PHASE4_PLAN §0.1). The app writes it to the App Group
// after every data change, on day / time-zone / locale changes and on foreground (App/Sources/Widgets); the widget
// extension only reads it: widgets never open the database and never run the schedule engine. Phase 5 reuses it for
// the Watch (WatchConnectivity), so it must stay small (< 20 KB for the seeded scenarios, asserted in tests).
//
// Contents: the active timetable's days from today through the next school day after tomorrow (every day in between,
// so holidays and free days are known), the first lesson after that range, open tasks due within 7 days plus the
// overdue count, the next exam, the entitlement tier and the presentation preferences (locale, language, 12/24 h).
//
// Wall-clock values only: lessons carry their `LocalDate` + `LocalTime`, never instants. Instants are derived when
// the timeline is planned (`WidgetTimelinePlanner`) in the zone that applies *then* — the device zone for
// "follow device" timetables (so a zone change made after the snapshot was written still shows 08:00 lessons at
// 08:00 local time) or the timetable's fixed zone.
//
// Coding: synthesized Codable with short keys (size). `version` is checked by `WidgetSnapshotStore.decode`; a
// snapshot from a newer app version is ignored (the widget shows "Open Tabula" until the app writes again).
// Pure Foundation + TimetableCore, Linux-tested.
import Foundation
import TimetableCore

/// Everything a widget (and later the Watch) may show.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Format version written by this app version.
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// When the app built it (diagnostics only; never used to decide what to show).
    public var generatedAt: Date
    /// The zone the timetable's wall-clock times are interpreted in when the snapshot was built.
    public var timeZoneID: String
    /// `true` for "follow device" timetables: the planner uses the device zone at planning time instead.
    public var followsDeviceTimeZone: Bool
    /// The app's locale identifier (formatting of times and dates).
    public var localeID: String
    /// The app's UI language (`Bundle.main.preferredLocalizations.first`), so widget strings match the app.
    public var languageCode: String?
    /// 12/24 h preference.
    public var hourCycle: HourCycle
    /// Entitlement tier (Pro gate of widget families).
    public var tier: Tier
    /// `false` before onboarding finished / without a live timetable: the widgets ask the user to open the app.
    public var hasTimetable: Bool
    /// Contiguous days, ascending, starting with the app's "today" when it was built. Empty without a timetable.
    public var days: [Day]
    /// The first lesson after the last covered day (within 31 days), if any.
    public var followingLesson: Lesson?
    /// Open tasks due within `WidgetSnapshotBuilder.taskHorizonDays` (overdue ones excluded), by due date.
    public var tasks: [DueTask]
    /// Open tasks whose due date / time has passed (all of them, also those not listed in `overdueItems`).
    public var overdueTaskCount: Int
    /// The first exam that has not ended yet at build time, if any (always `exams.first` when `exams` is present).
    public var nextExam: UpcomingExam?
    /// The most overdue open tasks, oldest due date first, at most `WidgetSnapshotBuilder.maxOverdueTasks` (Phase 4 B1,
    /// for the Homework widget). Additive: an optional key, so v1 files written before B1 decode with `nil` (the widget
    /// then shows the overdue count only) and an older reader ignores the key; hence no version bump.
    public var overdueItems: [DueTask]?
    /// The next upcoming exams in date / start order, at most `WidgetSnapshotBuilder.maxExams` (B1 QA M1): the exam
    /// widget moves to the next one when one ends, and over midnight, without the app. Additive and optional like
    /// `overdueItems`; absent in files written before, where `nextExam` alone is the list.
    public var exams: [UpcomingExam]?
    /// The number of open tasks (the Tasks tab's Today + Upcoming + Overdue, undated ones included), for the Homework
    /// count (B1 QA M3). Additive and optional; absent in older files.
    public var openTaskCount: Int?
    /// Every live timetable in display order (Phase 4 B3, the widgets' timetable choice): the active one with its name
    /// only (its days are `days`), the others with their own days while the encoded snapshot stays within
    /// `WidgetSnapshotBuilder.maxEncodedBytes` (a section that does not fit has `days == nil`). Additive and optional
    /// (no version bump); absent in older files, where only the active timetable can be shown.
    public var timetables: [TimetableSection]?

    enum CodingKeys: String, CodingKey {
        case version = "v", generatedAt = "at", timeZoneID = "tz", followsDeviceTimeZone = "ftz", localeID = "loc"
        case languageCode = "lang", hourCycle = "hc", tier, hasTimetable = "tt", days, followingLesson = "after"
        case tasks, overdueTaskCount = "overdue", nextExam = "exam", overdueItems = "od"
        case exams = "exs", openTaskCount = "open", timetables = "tts"
    }

    /// Creates a snapshot.
    public init(version: Int = WidgetSnapshot.currentVersion, generatedAt: Date, timeZoneID: String,
                followsDeviceTimeZone: Bool, localeID: String, languageCode: String?, hourCycle: HourCycle, tier: Tier,
                hasTimetable: Bool, days: [Day], followingLesson: Lesson?, tasks: [DueTask], overdueTaskCount: Int,
                nextExam: UpcomingExam?, overdueItems: [DueTask]? = nil, exams: [UpcomingExam]? = nil,
                openTaskCount: Int? = nil, timetables: [TimetableSection]? = nil) {
        self.version = version
        self.generatedAt = generatedAt
        self.timeZoneID = timeZoneID
        self.followsDeviceTimeZone = followsDeviceTimeZone
        self.localeID = localeID
        self.languageCode = languageCode
        self.hourCycle = hourCycle
        self.tier = tier
        self.hasTimetable = hasTimetable
        self.days = days
        self.followingLesson = followingLesson
        self.tasks = tasks
        self.overdueTaskCount = overdueTaskCount
        self.nextExam = nextExam
        self.overdueItems = overdueItems
        self.exams = exams
        self.openTaskCount = openTaskCount
        self.timetables = timetables
    }

    /// The listed overdue tasks (empty for snapshots written before B1).
    public var overdueTasks: [DueTask] { overdueItems ?? [] }

    /// The exams the exam widget walks through: `exams`, else just `nextExam` (older files).
    public var upcomingExams: [UpcomingExam] { exams ?? nextExam.map { [$0] } ?? [] }

    /// First covered day.
    public var firstDay: LocalDate? { days.first?.date }
    /// Last covered day.
    public var lastDay: LocalDate? { days.last?.date }

    /// The covered day `date`, if any.
    public func day(_ date: LocalDate) -> Day? {
        guard let first = firstDay else { return nil }
        let offset = first.days(to: date)
        guard days.indices.contains(offset), days[offset].date == date else { return days.first { $0.date == date } }
        return days[offset]
    }

    /// The zone to plan in: the device zone for "follow device", else the stored zone (device zone if unknown).
    public func effectiveTimeZone(device: TimeZone) -> TimeZone {
        followsDeviceTimeZone ? device : (TimeZone(identifier: timeZoneID) ?? device)
    }

    /// The same snapshot with `generatedAt` cleared, for "did anything change?" comparisons.
    public var contentOnly: WidgetSnapshot {
        var copy = self
        copy.generatedAt = Date(timeIntervalSinceReferenceDate: 0)
        return copy
    }

    // MARK: - Nested types

    /// One calendar day of the active timetable.
    public struct Day: Codable, Equatable, Sendable {
        /// Why a day has no lessons (or that it is a normal school day).
        public enum Kind: String, Codable, Equatable, Sendable {
            /// A school day (lessons may still be empty).
            case school
            /// Not a school day (weekend, disabled weekday, outside the timetable's validity).
            case free
            /// A calendar break (holidays) covers it.
            case holiday
            /// The whole day was cancelled ("cancel day" override).
            case cancelled
        }

        /// Date.
        public var date: LocalDate
        /// Kind.
        public var kind: Kind
        /// The break's user name (`holiday`) or the cancel note (`cancelled`), trimmed; `nil` when blank.
        public var note: String?
        /// Lessons in start order, cancelled ones included (flagged by status).
        public var lessons: [Lesson]

        enum CodingKeys: String, CodingKey { case date = "d", kind = "k", note = "n", lessons = "l" }

        /// Creates a day.
        public init(date: LocalDate, kind: Kind, note: String? = nil, lessons: [Lesson] = []) {
            self.date = date
            self.kind = kind
            self.note = note
            self.lessons = lessons
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(LocalDate.self, forKey: .date)
            kind = try container.decode(Kind.self, forKey: .kind)
            note = try container.decodeIfPresent(String.self, forKey: .note)
            lessons = try container.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(note, forKey: .note)
            if !lessons.isEmpty { try container.encode(lessons, forKey: .lessons) }
        }
    }

    /// One lesson occurrence, already resolved (subject patches, rooms, overrides applied).
    public struct Lesson: Codable, Equatable, Sendable, Identifiable {
        /// `OccurrenceID.rawValue` (stable; deep links use it).
        public var id: String
        /// Subject name / short name / colour / symbol.
        public var subject: SubjectSummary
        /// Wall-clock date.
        public var date: LocalDate
        /// Wall-clock start.
        public var startTime: LocalTime
        /// Wall-clock end.
        public var endTime: LocalTime
        /// Room, only when the timetable shows rooms and it is not blank (PRODUCT.md field rule).
        public var room: String?
        /// Scheduled / modified / added / cancelled.
        public var status: ResolvedLesson.Status
        /// What changed (modified lessons); `nil` when nothing.
        public var reasons: [ModificationReason]?

        enum CodingKeys: String, CodingKey {
            case id, subject = "s", date = "d", startTime = "st", endTime = "et", room = "r", status = "x", reasons = "why"
        }

        /// Creates a lesson.
        public init(id: String, subject: SubjectSummary, date: LocalDate, startTime: LocalTime, endTime: LocalTime,
                    room: String? = nil, status: ResolvedLesson.Status = .scheduled, reasons: [ModificationReason]? = nil) {
            self.id = id
            self.subject = subject
            self.date = date
            self.startTime = startTime
            self.endTime = endTime
            self.room = room
            self.status = status
            self.reasons = reasons
        }

        /// `true` unless cancelled.
        public var takesPlace: Bool { status != .cancelled }

        /// Start instant in `context` (DST policy of `CalendarContext.date`).
        public func start(in context: CalendarContext) -> Date { context.date(date, startTime) }

        /// End instant in `context`; never before the start.
        public func end(in context: CalendarContext) -> Date { max(start(in: context), context.date(date, endTime)) }

        /// The occurrence ID.
        public var occurrenceID: OccurrenceID { OccurrenceID(rawValue: id) }
    }

    /// An open task.
    public struct DueTask: Codable, Equatable, Sendable, Identifiable {
        /// Task ID.
        public var id: UUID
        /// Title (user text, shortened to `WidgetSnapshotBuilder.maxTextLength`).
        public var title: String
        /// Subject, if any.
        public var subject: SubjectSummary?
        /// Due date.
        public var dueDate: LocalDate
        /// Due time, if any.
        public var dueTime: LocalTime?
        /// Priority.
        public var priority: TaskPriority

        enum CodingKeys: String, CodingKey { case id, title = "t", subject = "s", dueDate = "d", dueTime = "tm", priority = "p" }

        /// Creates a task.
        public init(id: UUID, title: String, subject: SubjectSummary?, dueDate: LocalDate, dueTime: LocalTime?,
                    priority: TaskPriority) {
            self.id = id
            self.title = title
            self.subject = subject
            self.dueDate = dueDate
            self.dueTime = dueTime
            self.priority = priority
        }
    }

    /// The next exam.
    public struct UpcomingExam: Codable, Equatable, Sendable, Identifiable {
        /// Exam ID.
        public var id: UUID
        /// Title (user text, shortened).
        public var title: String
        /// Subject, if any.
        public var subject: SubjectSummary?
        /// Date.
        public var date: LocalDate
        /// Start, if any.
        public var start: LocalTime?
        /// End, if any.
        public var end: LocalTime?
        /// Room (field rule applied), if any.
        public var room: String?

        enum CodingKeys: String, CodingKey { case id, title = "t", subject = "s", date = "d", start = "st", end = "et", room = "r" }

        /// Creates an exam.
        public init(id: UUID, title: String, subject: SubjectSummary?, date: LocalDate, start: LocalTime?,
                    end: LocalTime?, room: String?) {
            self.id = id
            self.title = title
            self.subject = subject
            self.date = date
            self.start = start
            self.end = end
            self.room = room
        }
    }
}
