// Edit state of the bell schedule editor: the timetable's default schedule plus its other schedules, each with
// editable periods; overlap/invalid-time checks and the mutations that store the result. Pure, Linux-tested.
//
// Schedules (UX overhaul R6): the default ("Regular") applies to every day without its own schedule; a weekday
// variant applies to the weekdays assigned to it; a schedule with no weekday (e.g. "Shortened") is kept and is used
// for single dates through "Change for this day" (`OverrideChange.useBellSchedule`). Before R6 such schedules were
// not loaded here at all, and a variant whose weekdays were all removed was deleted on save; now it is kept.
//
// Design decisions
// - A variant created with "copy from" keeps the SAME period IDs as its source: lessons reference period IDs and the
//   resolver then finds them directly in the variant (no "moved by ordinal" warning).
// - A period that a lesson refers to cannot be removed (the validator rejects dangling period references as an error).
// - Overlapping periods are a warning in the data model ("warn, never block"); a period ending at or before its start
//   is an error and blocks saving.
import Foundation
import TimetableCore

/// The bell schedule editor's state.
public struct BellSetDraft: Equatable, Sendable {
    /// One schedule being edited.
    public struct Entry: Equatable, Identifiable, Sendable {
        public var id: BellSchedule.ID
        public var name: String
        public var periods: [Period]
        /// Weekdays that use this schedule (empty for the default schedule: it applies to all other days; empty for
        /// an occasional schedule used only by day changes).
        public var weekdays: Set<Weekday>
        public var isNew: Bool

        public init(id: BellSchedule.ID, name: String, periods: [Period], weekdays: Set<Weekday>, isNew: Bool) {
            self.id = id
            self.name = name
            self.periods = periods
            self.weekdays = weekdays
            self.isNew = isNew
        }
    }

    /// A problem in one period.
    public enum PeriodIssue: Equatable, Sendable {
        /// Ends at or before its start (blocks saving).
        case endBeforeStart
        /// Overlaps another period of the same schedule (warning).
        case overlaps
    }

    public let timetableID: Timetable.ID
    public var defaultEntry: Entry
    public var variants: [Entry]
    /// IDs of variant schedules that existed and were removed in the editor.
    public private(set) var removedVariantIDs: [BellSchedule.ID]

    /// Loads the schedules of `timetable` (must use a bell schedule; otherwise the default entry is empty).
    public init(timetable: Timetable, schedules: [BellSchedule], defaultScheduleName: String, ids: () -> BellSchedule.ID) {
        timetableID = timetable.id
        removedVariantIDs = []
        let live = schedules.filter { !$0.isDeleted && $0.timetableID == timetable.id }
        var variantEntries: [Entry] = []
        var defaultEntry: Entry?
        if case let .bellSchedule(defaultID, perWeekday) = timetable.timeStructure {
            if let schedule = live.first(where: { $0.id == defaultID }) {
                defaultEntry = Entry(id: schedule.id, name: schedule.name, periods: schedule.periods, weekdays: [], isNew: false)
            }
            for id in Set(perWeekday.values).subtracting([defaultID]).sorted() {
                guard let schedule = live.first(where: { $0.id == id }) else { continue }
                let days = Set(perWeekday.filter { $0.value == id }.keys)
                variantEntries.append(Entry(id: id, name: schedule.name, periods: schedule.periods, weekdays: days, isNew: false))
            }
            variantEntries.sort { ($0.weekdays.min() ?? .sunday) < ($1.weekdays.min() ?? .sunday) }
            // Schedules without a weekday (used by day changes), by name.
            let occasional = live.filter { schedule in
                schedule.id != defaultID && !perWeekday.values.contains(schedule.id)
            }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            variantEntries += occasional.map {
                Entry(id: $0.id, name: $0.name, periods: $0.periods, weekdays: [], isNew: false)
            }
        }
        self.defaultEntry = defaultEntry ?? Entry(id: ids(), name: defaultScheduleName, periods: [], weekdays: [], isNew: true)
        variants = variantEntries
    }

    /// All entries, default first.
    public var entries: [Entry] { [defaultEntry] + variants }

    /// The entry with `id`.
    public func entry(_ id: BellSchedule.ID) -> Entry? { entries.first { $0.id == id } }

    /// Renames a schedule.
    public mutating func rename(_ entryID: BellSchedule.ID, to name: String) {
        update(entryID) { $0.name = name }
    }

    /// Adds a schedule without weekdays as a copy of `sourceID` (same period IDs, so lessons keep their periods).
    @discardableResult
    public mutating func addSchedule(copying sourceID: BellSchedule.ID, name: String, id: BellSchedule.ID) -> BellSchedule.ID {
        addVariant(copying: sourceID, weekdays: [], name: name, id: id)
    }

    // MARK: Editing

    /// Adds a period behind the last one of `entryID` (default lesson length 45 min, 5 min gap), or a lesson at
    /// 08:00 into an empty schedule.
    public mutating func addPeriod(to entryID: BellSchedule.ID, id: Period.ID) {
        update(entryID) { entry in
            let last = entry.periods.max { $0.end < $1.end }
            let start = last.flatMap { $0.end.adding(minutes: 5) } ?? SlotDraft.defaultStart
            let end = start.adding(minutes: 45) ?? start
            entry.periods.append(Period(id: id, label: nil, start: start, end: end, kind: .lesson))
        }
    }

    /// Removes the period `periodID` unless it is in `lockedPeriods` (used by lessons).
    public mutating func removePeriod(_ periodID: Period.ID, from entryID: BellSchedule.ID, locked lockedPeriods: Set<Period.ID>) {
        guard !lockedPeriods.contains(periodID) else { return }
        update(entryID) { $0.periods.removeAll { $0.id == periodID } }
    }

    /// Moves periods like `Array.move(fromOffsets:toOffset:)` (list drag). Times do not change; the schedule is
    /// always shown in time order, so this is only used for the order of equal start times.
    public mutating func sortByTime(_ entryID: BellSchedule.ID) {
        update(entryID) { $0.periods.sort { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) } }
    }

    /// Replaces one period.
    public mutating func setPeriod(_ period: Period, in entryID: BellSchedule.ID) {
        update(entryID) { entry in
            if let index = entry.periods.firstIndex(where: { $0.id == period.id }) { entry.periods[index] = period }
        }
    }

    /// Adds a variant for `weekdays` as a copy of `sourceID` (same period IDs). The weekdays are taken away from
    /// other variants. Returns the new entry's ID.
    @discardableResult
    public mutating func addVariant(copying sourceID: BellSchedule.ID, weekdays: Set<Weekday>, name: String,
                                    id: BellSchedule.ID) -> BellSchedule.ID {
        let source = entries.first { $0.id == sourceID } ?? defaultEntry
        variants.append(Entry(id: id, name: name, periods: source.periods, weekdays: [], isNew: true))
        assign(weekdays, to: id)
        return id
    }

    /// Assigns `weekdays` to a variant exclusively.
    public mutating func assign(_ weekdays: Set<Weekday>, to entryID: BellSchedule.ID) {
        for index in variants.indices {
            if variants[index].id == entryID {
                variants[index].weekdays = weekdays
            } else {
                variants[index].weekdays.subtract(weekdays)
            }
        }
    }

    /// Removes a variant (its weekdays use the default schedule again).
    public mutating func removeVariant(_ entryID: BellSchedule.ID) {
        guard let entry = variants.first(where: { $0.id == entryID }) else { return }
        variants.removeAll { $0.id == entryID }
        if !entry.isNew { removedVariantIDs.append(entryID) }
    }

    /// Weekdays that no variant uses yet.
    public func freeWeekdays(enabledDays: Set<Weekday>) -> [Weekday] {
        let taken = variants.reduce(into: Set<Weekday>()) { $0.formUnion($1.weekdays) }
        return Weekday.allCases.filter { enabledDays.contains($0) && !taken.contains($0) }
    }

    private mutating func update(_ entryID: BellSchedule.ID, _ edit: (inout Entry) -> Void) {
        if defaultEntry.id == entryID {
            edit(&defaultEntry)
        } else if let index = variants.firstIndex(where: { $0.id == entryID }) {
            edit(&variants[index])
        }
    }

    // MARK: Checks

    /// Issues per period of `entry`.
    public static func issues(of entry: Entry) -> [Period.ID: PeriodIssue] {
        var result: [Period.ID: PeriodIssue] = [:]
        for period in entry.periods {
            if period.end <= period.start { result[period.id] = .endBeforeStart }
        }
        let valid = entry.periods.filter { $0.end > $0.start }
        for i in valid.indices {
            for j in valid.indices where j > i {
                let a = valid[i], b = valid[j]
                if a.start < b.end && b.start < a.end {
                    if result[a.id] == nil { result[a.id] = .overlaps }
                    if result[b.id] == nil { result[b.id] = .overlaps }
                }
            }
        }
        return result
    }

    /// `true` when any period ends at or before its start, or a schedule has no name.
    public var hasBlockingIssues: Bool {
        hasBlankName || entries.contains { entry in Self.issues(of: entry).values.contains(.endBeforeStart) }
    }

    /// `true` when the default schedule has no lesson period (a bell-schedule timetable needs at least one).
    public var defaultHasNoLessons: Bool { !defaultEntry.periods.contains { $0.kind == .lesson } }

    /// `true` when any schedule has overlapping periods (warning only).
    public var hasOverlaps: Bool {
        entries.contains { entry in Self.issues(of: entry).values.contains(.overlaps) }
    }

    /// IDs of periods referenced by live lessons of the timetable (these cannot be removed).
    public static func lockedPeriods(lessons: [Lesson], timetableID: Timetable.ID) -> Set<Period.ID> {
        var ids = Set<Period.ID>()
        for lesson in lessons where !lesson.isDeleted && lesson.timetableID == timetableID {
            if case .period(let id, _) = lesson.slot { ids.insert(id) }
        }
        return ids
    }

    // MARK: Result

    /// The time structure to store.
    public func timeStructure() -> TimeStructure {
        Self.timeStructure(default: defaultEntry, variants: variants)
    }

    private static func timeStructure(default defaultEntry: Entry, variants: [Entry]) -> TimeStructure {
        var perWeekday: [Weekday: BellSchedule.ID] = [:]
        for variant in variants {
            for day in variant.weekdays { perWeekday[day] = variant.id }
        }
        return .bellSchedule(defaultID: defaultEntry.id, perWeekday: perWeekday)
    }

    /// Mutations that store the edited schedules and update `timetable`. Every schedule is kept; only the ones with
    /// weekdays appear in the timetable's per-weekday map.
    public func mutations(for timetable: Timetable) -> [DatabaseMutation] {
        func schedule(_ entry: Entry) -> BellSchedule {
            BellSchedule(id: entry.id, meta: EditorEntities.placeholderMeta, timetableID: timetableID,
                         name: EditorText.trimmedOrNil(entry.name) ?? entry.name,
                         periods: entry.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) })
        }
        var steps: [DatabaseMutation] = [.upsert(schedule(defaultEntry))]
        for entry in variants { steps.append(.upsert(schedule(entry))) }
        var edited = timetable
        edited.timeStructure = timeStructure()
        steps.append(.upsert(edited))
        for id in removedVariantIDs { steps.append(.delete(id)) }
        return steps
    }
}

// MARK: - Rows, usage and regeneration (UX overhaul R6)

extension BellSetDraft {
    /// One row of the period list: the period, its lesson number and the computed break before the next period.
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: Period.ID { period.id }
        public let period: Period
        /// 1-based number among the lesson periods ("1", "2" …); `nil` for breaks and lunch.
        public let ordinal: Int?
        /// Minutes between this period's end and the next period's start, when positive (shown as "10 min break").
        public let gapAfterMinutes: Int?
    }

    /// The periods of `entry` in time order with their numbers and the computed breaks between them.
    public static func rows(of entry: Entry) -> [Row] {
        let sorted = entry.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        var lessonNumber = 0
        return sorted.enumerated().map { index, period in
            var ordinal: Int?
            if period.kind == .lesson {
                lessonNumber += 1
                ordinal = lessonNumber
            }
            var gap: Int?
            if sorted.indices.contains(index + 1) {
                let minutes = sorted[index + 1].start.minuteOfDay - period.end.minuteOfDay
                if minutes > 0 { gap = minutes }
            }
            return Row(period: period, ordinal: ordinal, gapAfterMinutes: gap)
        }
    }

    /// How many live lessons of the timetable start in each period: recurring lessons plus extra or moved lessons of
    /// day changes. A period in use cannot be deleted (the reference would dangle).
    public static func periodUsage(lessons: [Lesson], overrides: [ScheduleOverride],
                                   timetableID: Timetable.ID) -> [Period.ID: Int] {
        var counts: [Period.ID: Int] = [:]
        func count(_ slot: LessonSlot?) {
            if case .period(let id, _)? = slot { counts[id, default: 0] += 1 }
        }
        for lesson in lessons where !lesson.isDeleted && lesson.timetableID == timetableID { count(lesson.slot) }
        for item in overrides where !item.isDeleted && item.timetableID == timetableID {
            switch item.change {
            case .addLesson(let oneOff): count(oneOff.slot)
            case .modifyLesson(_, let patch): count(patch.slot)
            default: break
            }
        }
        return counts
    }

    /// How many live day changes of the timetable use each bell schedule ("Shortened lessons" on a date). A schedule
    /// in use cannot be deleted.
    public static func scheduleUsage(overrides: [ScheduleOverride], timetableID: Timetable.ID) -> [BellSchedule.ID: Int] {
        var counts: [BellSchedule.ID: Int] = [:]
        for item in overrides where !item.isDeleted && item.timetableID == timetableID {
            if case .useBellSchedule(let id) = item.change { counts[id, default: 0] += 1 }
        }
        return counts
    }

    /// `true` when some schedule has a blank name (blocks saving: the schedule picker would show an empty choice).
    public var hasBlankName: Bool { entries.contains { EditorText.trimmedOrNil($0.name) == nil } }

    /// Replaces the periods of `entryID` with the ones `regeneration` describes. Lesson periods keep their IDs and
    /// labels in order (lessons keep their period numbers); new ones get IDs from `newID`. Remaining periods are
    /// removed unless `inUse` contains them (`BellRegeneration.minimumCount` keeps every used lesson period placed).
    public mutating func regenerate(_ entryID: BellSchedule.ID, with regeneration: BellRegeneration,
                                    inUse: Set<Period.ID>, newID: () -> Period.ID) {
        guard var entry = entry(entryID) else { return }
        let sorted = entry.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let lessons = sorted.filter { $0.kind == .lesson }
        let times = regeneration.template.lessonTimes()
        var result: [Period] = times.enumerated().map { index, time in
            let reused = lessons.indices.contains(index) ? lessons[index] : nil
            return Period(id: reused?.id ?? newID(), label: reused?.label, start: time.start, end: time.end, kind: .lesson)
        }
        let placed = Set(result.map(\.id))
        result += sorted.filter { !placed.contains($0.id) && inUse.contains($0.id) }
        entry.periods = result
        replace(entry)
    }

    /// Replaces the stored entry with the same ID.
    mutating func replace(_ entry: Entry) {
        if defaultEntry.id == entry.id {
            defaultEntry = entry
        } else if let index = variants.firstIndex(where: { $0.id == entry.id }) {
            variants[index] = entry
        }
    }
}

/// The "Regenerate from lesson length" form: the onboarding generator (`BellScheduleTemplate`) with values read from
/// an existing schedule.
public struct BellRegeneration: Equatable, Sendable {
    public static let lessonMinutesRange = 20...120
    public static let breakMinutesRange = 0...60
    public static let lessonCountRange = 1...14

    public var firstStart: LocalTime
    public var lessonMinutes: Int
    /// Break after every lesson except the second.
    public var shortBreakMinutes: Int
    /// Break after the second lesson (the long break of most schools).
    public var longBreakMinutes: Int
    public var lessonCount: Int

    /// Values read from `entry`: first start, first lesson's length, the gaps after lessons 1 and 2, the count.
    public init(entry: BellSetDraft.Entry) {
        let lessons = entry.periods.filter { $0.kind == .lesson }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }
        func gap(after index: Int) -> Int? {
            guard lessons.indices.contains(index + 1) else { return nil }
            return lessons[index + 1].start.minuteOfDay - lessons[index].end.minuteOfDay
        }
        firstStart = lessons.first?.start ?? SlotDraft.defaultStart
        let length = lessons.first.map { $0.end.minuteOfDay - $0.start.minuteOfDay } ?? 45
        lessonMinutes = clamp(length, Self.lessonMinutesRange)
        let short = gap(after: 0) ?? 10
        shortBreakMinutes = clamp(short, Self.breakMinutesRange)
        longBreakMinutes = clamp(gap(after: 1) ?? short, Self.breakMinutesRange)
        lessonCount = clamp(lessons.isEmpty ? 6 : lessons.count, Self.lessonCountRange)
    }

    /// The generator input (same break pattern as onboarding: short, long, then short).
    public var template: BellScheduleTemplate {
        BellScheduleTemplate(firstStart: firstStart, lessonMinutes: lessonMinutes,
                             breakMinutes: [shortBreakMinutes, longBreakMinutes, shortBreakMinutes], count: lessonCount)
    }

    /// The generated lesson times (fewer than `lessonCount` when the day would run past midnight).
    public var preview: [(start: LocalTime, end: LocalTime)] { template.lessonTimes() }

    /// The smallest lesson count that still places every lesson period in use (counted in time order in `entry`).
    public static func minimumCount(of entry: BellSetDraft.Entry, inUse: Set<Period.ID>) -> Int {
        let lessons = entry.periods.filter { $0.kind == .lesson }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let lastUsed = lessons.lastIndex { inUse.contains($0.id) }
        return max(lessonCountRange.lowerBound, (lastUsed ?? -1) + 1)
    }
}
