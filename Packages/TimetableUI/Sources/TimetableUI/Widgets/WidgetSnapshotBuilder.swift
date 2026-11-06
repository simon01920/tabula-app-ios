// Builds the `WidgetSnapshot` from the app's database (PHASE4_PLAN §0.1). Pure, Linux-tested; the app calls it on
// the main actor after every change (App/Sources/Widgets/WidgetSnapshotSource.swift, shared by the widget writer and
// the Live Activity controller since Phase 10 WP2).
//
// Rules (same sources of truth as the Today tab, so widget and app never disagree):
//   - Timetable: the active one (`ActiveTimetable.resolve`), resolved with the app's `CalendarContext`.
//   - Days: today through the next school day after tomorrow (`ScheduleResolver.nextSchoolDay`), every day in between
//     included; without a school day in the next 31 days: today + 7 days. Day kinds follow `TodayState`: a break wins
//     over a cancelled day, which wins over a free day.
//   - Lessons: `DaySchedule.entries` (cancelled ones kept and flagged), room only when the timetable shows rooms.
//   - Following lesson: the first non-cancelled lesson after the last covered day (31-day horizon).
//   - Tasks: the Tasks tab's Today + Upcoming segments (`TaskListModel`) due within 7 days, by due date, at most 20;
//     overdue = the Tasks tab's overdue count.
//   - Next exam: the Exams tab's featured exam (`ExamListModel.next`).
//   - User text is shortened to `maxTextLength` characters (bounded size; a widget cannot show more anyway).
//   - Timetable sections (Phase 4 B3, widget timetable choice): with ≥ 2 live timetables, one section each; the other
//     timetables' days only while the whole snapshot fits `maxEncodedBytes` (`addTimetableSections`).
//
// Cost (Phase 10 WP2, P12): the app passes the resolvers it already holds (`AppModel.resolvers`), and the size budget is
// enforced with ONE encode of the whole snapshot, plus one final encode only when something was trimmed or added: each
// trim step and each timetable section changes the size by an exactly known number of bytes (`SnapshotSizer`: the
// parts are encoded once with the same encoder, and sorted-key JSON without whitespace is the parts joined by fixed
// punctuation). The final encode is the real check of the 19 000 B hard guarantee (RISKS #83) and the bytes the writer
// stores (`build(...).data`). If it ever disagreed with the accounting, or the input is pathological (the lists and
// today's lessons must go), the Phase 4 algorithm runs instead (`legacyEnforceBudget`: one real encode per decision),
// so the output is the Phase 4 output in every case.
import Foundation
import TimetableCore

/// One build: the snapshot and its encoded bytes (what the app writes to the App Group and sends to the Watch).
public struct WidgetSnapshotBuild: Equatable, Sendable {
    /// How the size budget was enforced (tests / diagnostics).
    enum Sizing: Equatable, Sendable {
        /// Exact byte accounting: one or two encodes of the whole snapshot.
        case exact
        /// The Phase 4 algorithm (a real encode per decision): pathological input, or the accounting disagreed.
        case legacy
    }

    /// The snapshot.
    public let snapshot: WidgetSnapshot
    /// `WidgetSnapshotStore.encode(snapshot)`; `nil` only when encoding failed.
    public let data: Data?
    let sizing: Sizing
}

public enum WidgetSnapshotBuilder {
    /// Tasks due within this many days (today included as day 0).
    public static let taskHorizonDays = 7
    /// At most this many tasks.
    public static let maxTasks = 20
    /// At most this many overdue tasks are listed (the count is always complete).
    public static let maxOverdueTasks = 8
    /// User text longer than this is cut (characters).
    public static let maxTextLength = 60
    /// At most this many upcoming exams are listed (B1 QA M1).
    public static let maxExams = 4
    /// The encoded snapshot is trimmed (far-future tasks first) until it is at most this many bytes: the Watch
    /// reuses it and ARCHITECTURE.md budgets < 20 KB (B1 QA M2).
    public static let maxEncodedBytes = 19_000
    /// Days covered after today when no school day follows tomorrow within the horizon.
    public static let fallbackCoveredDays = 7
    /// Horizon of the next-school-day and following-lesson searches.
    public static let searchHorizonDays = 31

    /// The snapshot at `now`. `database` `nil` (first launch, onboarding) → a snapshot without timetable.
    /// `languageCode` is the app's UI language (`Bundle.main.preferredLocalizations.first`). `resolvers`: resolvers the
    /// caller already built from `database` in `context` (`AppModel.resolvers`); one built for another timetable value
    /// or context is ignored and built again.
    public static func make(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier,
                            locale: Locale, languageCode: String?,
                            resolvers: [Timetable.ID: ScheduleResolver]? = nil) -> WidgetSnapshot {
        build(database: database, now: now, context: context, tier: tier, locale: locale, languageCode: languageCode,
              resolvers: resolvers).snapshot
    }

    /// `make` plus the encoded bytes, so the writer does not encode again (Phase 10 WP2, P12).
    public static func build(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier,
                             locale: Locale, languageCode: String?,
                             resolvers: [Timetable.ID: ScheduleResolver]? = nil) -> WidgetSnapshotBuild {
        build(database: database, now: now, context: context, tier: tier, locale: locale, languageCode: languageCode,
              resolvers: resolvers, sizing: .exact, encode: WidgetSnapshotStore.encode)
    }

    /// The build with an injectable whole-snapshot encoder (tests count the encodes) and sizing (tests compare the
    /// exact accounting with the Phase 4 algorithm).
    static func build(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier, locale: Locale,
                      languageCode: String?, resolvers: [Timetable.ID: ScheduleResolver]?,
                      sizing: WidgetSnapshotBuild.Sizing,
                      encode: (WidgetSnapshot) throws -> Data) -> WidgetSnapshotBuild {
        let built = untrimmed(database: database, now: now, context: context, tier: tier, locale: locale,
                              languageCode: languageCode, resolvers: resolvers)
        guard let database else {
            return WidgetSnapshotBuild(snapshot: built.snapshot, data: try? encode(built.snapshot), sizing: .exact)
        }
        if sizing == .exact {
            let sizer = SnapshotSizer()
            var snapshot = built.snapshot
            do {
                var size = try trim(&snapshot, limit: maxEncodedBytes, sizer: sizer, encode: encode)
                if let active = built.active {
                    try addTimetableSections(&snapshot, size: &size, active: active, database: database,
                                             today: built.today, context: context, resolvers: resolvers, sizer: sizer)
                }
                let data = try size.data ?? encode(snapshot)
                if data.count == size.bytes, data.count <= maxEncodedBytes {
                    return WidgetSnapshotBuild(snapshot: snapshot, data: data, sizing: .exact)
                }
            } catch {
                // Pathological input or an encoding failure: the Phase 4 algorithm below decides.
            }
        }
        var snapshot = built.snapshot
        legacyEnforceBudget(&snapshot, limit: maxEncodedBytes, encode: encode)
        if let active = built.active {
            legacyAddTimetableSections(&snapshot, active: active, database: database, today: built.today,
                                       context: context, resolvers: resolvers, encode: encode)
        }
        return WidgetSnapshotBuild(snapshot: snapshot, data: try? encode(snapshot), sizing: .legacy)
    }

    /// Everything before the size budget: the active timetable's days, the tasks, overdue items and exams.
    static func untrimmed(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier, locale: Locale,
                          languageCode: String?, resolvers: [Timetable.ID: ScheduleResolver]?)
        -> (snapshot: WidgetSnapshot, active: Timetable?, today: LocalDate) {
        let settings = database?.settings ?? .untouchedDefaults
        let follows: Bool
        if case .followDevice = settings.timeZoneMode { follows = true } else { follows = false }
        var snapshot = WidgetSnapshot(
            generatedAt: now, timeZoneID: context.timeZone.identifier, followsDeviceTimeZone: follows,
            localeID: locale.identifier, languageCode: languageCode, hourCycle: settings.hourCycle, tier: tier,
            hasTimetable: false, days: [], followingLesson: nil, tasks: [], overdueTaskCount: 0, nextExam: nil)
        let today = context.localDate(of: now)
        guard let database else { return (snapshot, nil, today) }

        let active = ActiveTimetable.resolve(database)
        if let timetable = active,
           let covered = coverage(timetable, database: database, today: today, context: context, resolvers: resolvers) {
            snapshot.hasTimetable = true
            snapshot.days = covered.days
            snapshot.followingLesson = covered.following
        }

        let nowLocal = context.local(from: now)
        let liveTasks = database.tasks.filter { !$0.isDeleted }
        snapshot.overdueTaskCount = TaskListModel.counts(of: liveTasks, now: nowLocal).overdue
        let subjects = Dictionary(database.subjects.filter { !$0.isDeleted }.map { ($0.id, SubjectSummary($0)) },
                                  uniquingKeysWith: { first, _ in first })
        let horizon = today.adding(days: taskHorizonDays)
        let due = TaskListModel.tasks(in: .today, from: liveTasks, now: nowLocal, sort: .due)
            + TaskListModel.tasks(in: .upcoming, from: liveTasks, now: nowLocal, sort: .due)
        func dueTask(_ task: TaskItem) -> WidgetSnapshot.DueTask? {
            guard let dueDate = task.due?.date else { return nil }
            return WidgetSnapshot.DueTask(id: task.id.uuid, title: shortened(task.title),
                                          subject: task.subjectID.flatMap { subjects[$0] }.map(shortened),
                                          dueDate: dueDate, dueTime: task.due?.time, priority: task.priority)
        }
        snapshot.tasks = due.compactMap { task in dueTask(task).flatMap { $0.dueDate <= horizon ? $0 : nil } }
            .prefix(maxTasks).map { $0 }
        // Open tasks (the Tasks tab's Today + Upcoming + Overdue; undated ones included) for the Homework count.
        let counts = TaskListModel.counts(of: liveTasks, now: nowLocal)
        snapshot.openTaskCount = counts.today + counts.upcoming + counts.overdue
        // Overdue tasks: those due today (time passed) first, then the oldest; listed oldest first.
        let overdueAll = TaskListModel.tasks(in: .overdue, from: liveTasks, now: nowLocal, sort: .due).compactMap(dueTask)
        let overdueToday = overdueAll.filter { $0.dueDate == today }
        let overdueOlder = overdueAll.filter { $0.dueDate != today }
        let overdue = (overdueToday + overdueOlder).prefix(maxOverdueTasks)
            .sorted { ($0.dueDate, $0.dueTime ?? .midnight) < ($1.dueDate, $1.dueTime ?? .midnight) }
        snapshot.overdueItems = overdue.isEmpty ? nil : overdue

        // Upcoming exams: not completed, and not ended yet (no end: the whole exam day), soonest first.
        let subjectsByID = subjects
        let upcoming = database.exams.filter { !$0.isDeleted && !$0.isCompleted && $0.date >= today }
            .filter { exam in
                guard exam.date == today, let end = exam.end, end > (exam.start ?? .midnight) else { return true }
                return context.date(exam.date, end) > now
            }
            .sorted { ($0.date, $0.start ?? LocalTime.midnight, $0.title) < ($1.date, $1.start ?? LocalTime.midnight, $1.title) }
            .prefix(maxExams)
        let exams = upcoming.map { exam -> WidgetSnapshot.UpcomingExam in
            let facts = ExamFacts(exam: exam, visibility: ExamFacts.visibility(for: exam, in: database))
            return WidgetSnapshot.UpcomingExam(
                id: exam.id.uuid, title: shortened(exam.title), subject: exam.subjectID.flatMap { subjectsByID[$0] }.map(shortened),
                date: exam.date, start: exam.start, end: exam.end, room: facts.room.map(shortened))
        }
        snapshot.nextExam = exams.first
        snapshot.exams = exams.isEmpty ? nil : exams
        return (snapshot, active, today)
    }

    /// The days of `timetable` from `today` through the next school day after tomorrow (every day in between), and the
    /// first lesson after them; `nil` when the timetable cannot be resolved. A prebuilt resolver is used only when it
    /// was built for this very timetable value in this context; otherwise one is built here, as before Phase 10.
    static func coverage(_ timetable: Timetable, database: TabulaDatabase, today: LocalDate, context: CalendarContext,
                         resolvers: [Timetable.ID: ScheduleResolver]? = nil)
        -> (days: [WidgetSnapshot.Day], following: WidgetSnapshot.Lesson?)? {
        let prebuilt = resolvers?[timetable.id].flatMap { $0.timetable == timetable && $0.context == context ? $0 : nil }
        guard let resolver = prebuilt ?? ScheduleResolver(database: database, timetableID: timetable.id, context: context)
        else { return nil }
        let tomorrow = today.adding(days: 1)
        let last = resolver.nextSchoolDay(after: tomorrow, horizonDays: searchHorizonDays)?.date
            ?? today.adding(days: fallbackCoveredDays)
        var days: [WidgetSnapshot.Day] = []
        var date = today
        while date <= last {
            days.append(day(date, resolver: resolver, database: database, visibility: timetable.fieldVisibility))
            date = date.adding(days: 1)
        }
        // One second before the day after `last` starts: `nowAndNext` then looks at `last` (nothing starts later
        // that day) and the following days.
        let probe = context.startOfDay(last.adding(days: 1)).addingTimeInterval(-1)
        let following = resolver.nowAndNext(at: probe, horizonDays: searchHorizonDays).next
            .map { lesson($0, reasons: [], visibility: timetable.fieldVisibility) }
        return (days, following)
    }

    // MARK: Size budget (exact byte accounting)

    /// The encoded size of the snapshot being trimmed, and its bytes while they still describe it.
    struct EncodedSize: Equatable {
        var bytes: Int
        var data: Data?
    }

    /// Thrown where the exact accounting hands over to the Phase 4 algorithm.
    enum SizingFallback: Error {
        /// The far days are gone and it still does not fit: the lists and today's lessons must go (pathological).
        case pathological
    }

    /// The lists that are trimmed, in `trim`'s step order.
    enum TrimmedList {
        case tasks, overdue, exams
    }

    /// Phase 4 B1 / B3 budget with exact byte accounting: trims the lowest-priority lists until the snapshot fits
    /// `limit` (tasks beyond the first 8, overdue beyond 3, exams beyond 2, tasks beyond 4, exams beyond 1, overdue
    /// beyond 1), then covered days from the far end, never today. The same decisions as `legacyEnforceBudget` with one
    /// encode of the whole snapshot (`encode`) plus one encode of each part; throws `SizingFallback.pathological` where
    /// the Phase 4 algorithm goes on to clear the lists and today's lessons.
    static func trim(_ snapshot: inout WidgetSnapshot, limit: Int, sizer: SnapshotSizer,
                     encode: (WidgetSnapshot) throws -> Data) throws -> EncodedSize {
        let data = try encode(snapshot)
        var bytes = data.count
        guard bytes > limit else { return EncodedSize(bytes: bytes, data: data) }
        var tasks = try sizer.sizes(snapshot.tasks)
        var overdue = try snapshot.overdueItems.map { try sizer.sizes($0) }
        var exams = try snapshot.exams.map { try sizer.sizes($0) }
        let steps: [(list: TrimmedList, keep: Int)] = [(.tasks, 8), (.overdue, 3), (.exams, 2), (.tasks, 4), (.exams, 1),
                                                       (.overdue, 1)]
        for step in steps {
            guard bytes > limit else { return EncodedSize(bytes: bytes, data: nil) }
            switch step.list {
            case .tasks:
                snapshot.tasks = Array(snapshot.tasks.prefix(step.keep))
                bytes += SnapshotSizer.keepingPrefix(&tasks, step.keep)
            case .overdue:
                snapshot.overdueItems = snapshot.overdueItems.map { Array($0.prefix(step.keep)) }
                if overdue != nil { bytes += SnapshotSizer.keepingPrefix(&overdue!, step.keep) }
            case .exams:
                snapshot.exams = snapshot.exams.map { Array($0.prefix(step.keep)) }
                if exams != nil { bytes += SnapshotSizer.keepingPrefix(&exams!, step.keep) }
            }
        }
        // Phase 4 B3 final QA m2 (a hard guarantee; the Phase 5 Watch reuses the snapshot): drop covered days from the
        // far end, never today. The first lesson that takes place on a dropped day becomes `followingLesson` (it IS the
        // first lesson after the new last covered day), so "Next lesson" stays right; days past the covered range show
        // "Open Tabula" (outdated), never invented data.
        var days = try sizer.sizes(snapshot.days)
        var following = try snapshot.followingLesson.map { try sizer.size(of: $0) }
        let followingKey = WidgetSnapshot.CodingKeys.followingLesson.stringValue
        while bytes > limit, snapshot.days.count > 1 {
            let dropped = snapshot.days.removeLast()
            bytes -= days.removeLast() + 1   // the day and its comma (at least one day stays)
            if let first = dropped.lessons.first(where: { $0.takesPlace }) {
                let size = try sizer.size(of: first)
                bytes += SnapshotSizer.memberBytes(followingKey, size)
                    - (following.map { SnapshotSizer.memberBytes(followingKey, $0) } ?? 0)
                snapshot.followingLesson = first
                following = size
            }
        }
        guard bytes <= limit else { throw SizingFallback.pathological }
        return EncodedSize(bytes: bytes, data: nil)
    }

    /// Phase 4 B3 (widget timetable choice): one section per live timetable, display order. Added AFTER the B1 trim, so
    /// the active timetable, tasks and exams keep everything they had; another timetable's days are kept only while
    /// the encoded snapshot stays within `maxEncodedBytes` (else that section has no days and a widget configured for it
    /// shows "Open Tabula"). Nothing is added with a single timetable (no choice to make). `size` is the exact encoded
    /// size of `snapshot` on entry and is kept exact.
    static func addTimetableSections(_ snapshot: inout WidgetSnapshot, size: inout EncodedSize, active: Timetable,
                                     database: TabulaDatabase, today: LocalDate, context: CalendarContext,
                                     resolvers: [Timetable.ID: ScheduleResolver]?, sizer: SnapshotSizer) throws {
        let ordered = ActiveTimetable.ordered(database)
        guard ordered.count > 1 else { return }
        let sections = ordered.map {
            TimetableSection(id: $0.id.uuid, name: shortened($0.name), isActive: $0.id == active.id)
        }
        let key = WidgetSnapshot.CodingKeys.timetables.stringValue
        var sectionSizes = try sizer.sizes(sections)
        let replaced = try snapshot.timetables.map { SnapshotSizer.memberBytes(key, SnapshotSizer.arrayBytes(try sizer.sizes($0))) }
            ?? 0
        let namedBytes = size.bytes - replaced + SnapshotSizer.memberBytes(key, SnapshotSizer.arrayBytes(sectionSizes))
        // Not even the names fit (final QA m2): no sections, the widgets follow the active timetable.
        guard namedBytes <= maxEncodedBytes else { return }
        snapshot.timetables = sections
        size = EncodedSize(bytes: namedBytes, data: nil)
        for (index, timetable) in ordered.enumerated() where timetable.id != active.id {
            guard let covered = coverage(timetable, database: database, today: today, context: context,
                                         resolvers: resolvers) else { continue }
            var section = sections[index]
            section.days = covered.days
            section.followingLesson = covered.following
            let sectionSize = try sizer.size(of: section)
            let candidate = size.bytes - sectionSizes[index] + sectionSize
            if candidate <= maxEncodedBytes {
                snapshot.timetables?[index] = section
                sectionSizes[index] = sectionSize
                size.bytes = candidate
            }
        }
    }

    /// The budget alone (tests): the exact accounting, checked by a real encode, else the Phase 4 algorithm.
    /// `limit` is a parameter for tests only.
    static func enforceBudget(_ snapshot: inout WidgetSnapshot, limit: Int = maxEncodedBytes) {
        let encode: (WidgetSnapshot) throws -> Data = WidgetSnapshotStore.encode
        var trimmed = snapshot
        if let size = try? trim(&trimmed, limit: limit, sizer: SnapshotSizer(), encode: encode),
           let data = try? size.data ?? encode(trimmed), data.count == size.bytes {
            snapshot = trimmed
            return
        }
        legacyEnforceBudget(&snapshot, limit: limit, encode: encode)
    }

    // MARK: Size budget (Phase 4 algorithm: the fallback, and the tests' reference)

    /// Trims the lowest-priority lists until the encoded snapshot fits `limit`: tasks beyond the first 8, overdue beyond
    /// the first 3, exams beyond 2, tasks beyond 4, exams beyond 1, overdue beyond 1; then (B3 final QA) covered days
    /// from the far end, never today; then, for pathological input only, the lists and today's last lessons.
    static func legacyEnforceBudget(_ snapshot: inout WidgetSnapshot, limit: Int,
                                    encode: (WidgetSnapshot) throws -> Data) {
        let steps: [(inout WidgetSnapshot) -> Void] = [
            { $0.tasks = Array($0.tasks.prefix(8)) },
            { $0.overdueItems = $0.overdueItems.map { Array($0.prefix(3)) } },
            { $0.exams = $0.exams.map { Array($0.prefix(2)) } },
            { $0.tasks = Array($0.tasks.prefix(4)) },
            { $0.exams = $0.exams.map { Array($0.prefix(1)) } },
            { $0.overdueItems = $0.overdueItems.map { Array($0.prefix(1)) } },
        ]
        for step in steps {
            guard encodedSize(snapshot, encode) > limit else { return }
            step(&snapshot)
        }
        while encodedSize(snapshot, encode) > limit, snapshot.days.count > 1 {
            let dropped = snapshot.days.removeLast()
            if let first = dropped.lessons.first(where: { $0.takesPlace }) { snapshot.followingLesson = first }
        }
        // Pathological input only (dozens of lessons today with maximal text): the lists go, then today's last
        // lessons, then the remaining optional items, until the snapshot fits.
        if encodedSize(snapshot, encode) > limit {
            snapshot.tasks = []
            snapshot.overdueItems = nil
            snapshot.exams = snapshot.nextExam.map { [$0] }
        }
        while encodedSize(snapshot, encode) > limit, let today = snapshot.days.indices.first,
              !snapshot.days[today].lessons.isEmpty {
            snapshot.days[today].lessons.removeLast()
        }
        if encodedSize(snapshot, encode) > limit {
            snapshot.followingLesson = nil
            snapshot.exams = nil
            snapshot.nextExam = nil
        }
    }

    /// `addTimetableSections` with a real encode per decision (Phase 4).
    static func legacyAddTimetableSections(_ snapshot: inout WidgetSnapshot, active: Timetable, database: TabulaDatabase,
                                           today: LocalDate, context: CalendarContext,
                                           resolvers: [Timetable.ID: ScheduleResolver]?,
                                           encode: (WidgetSnapshot) throws -> Data) {
        let ordered = ActiveTimetable.ordered(database)
        guard ordered.count > 1 else { return }
        var named = snapshot
        named.timetables = ordered.map {
            TimetableSection(id: $0.id.uuid, name: shortened($0.name), isActive: $0.id == active.id)
        }
        guard let namedSize = try? encode(named).count, namedSize <= maxEncodedBytes else { return }
        snapshot = named
        for (index, timetable) in ordered.enumerated() where timetable.id != active.id {
            guard let covered = coverage(timetable, database: database, today: today, context: context,
                                         resolvers: resolvers) else { continue }
            var candidate = snapshot
            candidate.timetables?[index].days = covered.days
            candidate.timetables?[index].followingLesson = covered.following
            if let size = try? encode(candidate).count, size <= maxEncodedBytes { snapshot = candidate }
        }
    }

    /// The encoded size; 0 when encoding fails (Phase 4 behaviour: the trim loops end).
    private static func encodedSize(_ snapshot: WidgetSnapshot, _ encode: (WidgetSnapshot) throws -> Data) -> Int {
        (try? encode(snapshot).count) ?? 0
    }

    // MARK: Internals

    static func day(_ date: LocalDate, resolver: ScheduleResolver, database: TabulaDatabase,
                    visibility: FieldVisibility) -> WidgetSnapshot.Day {
        let resolution = resolver.resolution(for: date)
        let schedule = resolution.schedule
        let kind: WidgetSnapshot.Day.Kind
        var note: String?
        if let breakID = schedule.activeBreakID {
            kind = .holiday
            note = TodayState.nonBlank(database.breaks.first { $0.id == breakID }?.name)
        } else if let overrideID = schedule.cancellingOverrideID {
            kind = .cancelled
            if case .cancelDay(let text)? = database.overrides.first(where: { $0.id == overrideID })?.change {
                note = TodayState.nonBlank(text)
            }
        } else {
            kind = schedule.isSchoolDay ? .school : .free
        }
        let lessons = schedule.entries.map { lesson($0, reasons: resolution.reasons(for: $0.id), visibility: visibility) }
        return WidgetSnapshot.Day(date: date, kind: kind, note: note.map(shortened), lessons: lessons)
    }

    static func lesson(_ lesson: ResolvedLesson, reasons: [ModificationReason],
                       visibility: FieldVisibility) -> WidgetSnapshot.Lesson {
        WidgetSnapshot.Lesson(id: lesson.id.rawValue, subject: shortened(lesson.subject), date: lesson.date,
                              startTime: lesson.startTime, endTime: lesson.endTime,
                              room: VisibleLessonFields(lesson: lesson, visibility: visibility).room.map(shortened),
                              status: lesson.status, reasons: reasons.isEmpty ? nil : reasons)
    }

    /// `text` cut to `maxTextLength` characters (whole grapheme clusters).
    static func shortened(_ text: String) -> String {
        text.count > maxTextLength ? String(text.prefix(maxTextLength)) : text
    }

    static func shortened(_ subject: SubjectSummary) -> SubjectSummary {
        var copy = subject
        copy.name = shortened(subject.name)
        copy.shortName = subject.shortName.map(shortened)
        return copy
    }
}

/// Exact encoded sizes of snapshot parts (Phase 10 WP2). `WidgetSnapshotStore.encode` is `JSONEncoder` with sorted keys
/// and no whitespace, so a value's bytes inside the file are its bytes encoded alone with the same configuration, an
/// array is `[` + elements joined by `,` + `]`, and an object member is `"key":value`, joined to the others by `,`.
struct SnapshotSizer {
    private let encoder = WidgetSnapshotStore.makeEncoder()

    /// The encoded size of `value`.
    func size(of value: some Encodable) throws -> Int { try encoder.encode(value).count }

    /// The encoded size of each element.
    func sizes<Element: Encodable>(_ values: [Element]) throws -> [Int] {
        try values.map { try encoder.encode($0).count }
    }

    /// The encoded size of an array whose elements have `sizes` bytes.
    static func arrayBytes(_ sizes: [Int]) -> Int { sizes.isEmpty ? 2 : sizes.reduce(1, +) + sizes.count }

    /// The bytes an object member `"key":value` adds to an object that has at least one other member (incl. its comma).
    static func memberBytes(_ key: String, _ valueBytes: Int) -> Int { key.utf8.count + 3 + valueBytes + 1 }

    /// Keeps the first `count` element sizes; returns how much the array's encoded size changed.
    static func keepingPrefix(_ sizes: inout [Int], _ count: Int) -> Int {
        let before = arrayBytes(sizes)
        sizes = Array(sizes.prefix(count))
        return arrayBytes(sizes) - before
    }
}
