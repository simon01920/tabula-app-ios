// Edit state of the bell schedule editor: the timetable's default schedule plus per-weekday variants, each with
// editable periods; overlap/invalid-time checks and the mutations that store the result. Pure, Linux-tested.
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
        /// Weekdays that use this schedule (empty for the default schedule: it applies to all other days).
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
        }
        self.defaultEntry = defaultEntry ?? Entry(id: ids(), name: defaultScheduleName, periods: [], weekdays: [], isNew: true)
        variants = variantEntries.sorted { ($0.weekdays.min() ?? .sunday) < ($1.weekdays.min() ?? .sunday) }
    }

    /// All entries, default first.
    public var entries: [Entry] { [defaultEntry] + variants }

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

    /// `true` when any period ends at or before its start.
    public var hasBlockingIssues: Bool {
        entries.contains { entry in Self.issues(of: entry).values.contains(.endBeforeStart) }
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

    /// Mutations that store the edited schedules and update `timetable` (variants without weekdays are dropped).
    public func mutations(for timetable: Timetable) -> [DatabaseMutation] {
        let kept = variants.filter { !$0.weekdays.isEmpty }
        let dropped = variants.filter { $0.weekdays.isEmpty && !$0.isNew }.map(\.id)
        func schedule(_ entry: Entry) -> BellSchedule {
            BellSchedule(id: entry.id, meta: EditorEntities.placeholderMeta, timetableID: timetableID,
                         name: EditorText.trimmedOrNil(entry.name) ?? entry.name,
                         periods: entry.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) })
        }
        var steps: [DatabaseMutation] = [.upsert(schedule(defaultEntry))]
        for entry in kept { steps.append(.upsert(schedule(entry))) }
        var edited = timetable
        edited.timeStructure = Self.timeStructure(default: defaultEntry, variants: kept)
        steps.append(.upsert(edited))
        for id in removedVariantIDs + dropped { steps.append(.delete(id)) }
        return steps
    }
}
