import Foundation

/// An overlap in the regular timetable (no dates): lessons of the same day key that overlap in the same
/// cycle week, with validities that can meet. For the timetable editor ("warn, never block").
public struct TemplateConflict: Hashable, Sendable, Codable {
    /// The day of the schedule.
    public var dayKey: DayKey
    /// The cycle week (week cycles only); `nil` without a week cycle.
    public var cycleWeek: Int?
    /// The overlapping lessons, ascending.
    public var lessonIDs: [Lesson.ID]

    /// Creates a template conflict (`lessonIDs` are sorted).
    public init(dayKey: DayKey, cycleWeek: Int?, lessonIDs: [Lesson.ID]) {
        self.dayKey = dayKey
        self.cycleWeek = cycleWeek
        self.lessonIDs = lessonIDs.sorted()
    }

    /// Localisable message (`conflict.overlap`, argument: number of lessons).
    public var message: LocalizedText {
        LocalizedText(key: Conflict.Kind.overlap.l10nKey, args: [.integer(lessonIDs.count)])
    }
}

/// Finds schedule conflicts. Conflicts warn; they never block (PRODUCT.md).
public enum ConflictDetector {
    /// Overlap conflicts among the non-cancelled `entries` of one date: one `Conflict` per connected group of
    /// overlapping occurrences (A overlaps B, B overlaps C → one conflict of three). Overlap uses wall-clock
    /// times, half-open (a lesson ending at 09:00 does not overlap one starting at 09:00). Different cycle
    /// weeks never meet on one date, so only lessons of the same week can conflict.
    public static func overlaps(in entries: [ResolvedLesson], on date: LocalDate) -> [Conflict] {
        let active = entries.filter { $0.status != .cancelled }
            .map { (id: $0.id, start: $0.startTime.minuteOfDay, end: $0.endTime.minuteOfDay) }
        return clusters(of: active).map { Conflict(kind: .overlap, date: date, occurrenceIDs: $0) }
    }

    /// Overlaps in the regular timetable of `resolver`: for every day key and (for week cycles) every cycle
    /// week, lessons that run in that week, overlap in time, and whose validities can coincide.
    ///
    /// Times come from the bell schedule the day key normally uses (`perWeekday` for weekday keys, the
    /// default schedule for cycle days); unplaceable lessons are skipped (the dated resolution reports them).
    /// Ascending by day key, cycle week, then lesson IDs.
    public static func templateConflicts(in resolver: ScheduleResolver) -> [TemplateConflict] {
        var result: [TemplateConflict] = []
        let weeks: [Int?]
        if case .weekCycle(let cycle) = resolver.timetable.rotation {
            weeks = Array(1...max(1, cycle.length))
        } else {
            weeks = [nil]
        }
        var defaultIndex: BellScheduleIndex?
        if case let .bellSchedule(defaultID, _) = resolver.timetable.timeStructure {
            defaultIndex = resolver.schedulesByID[defaultID]
        }
        for (dayKey, lessons) in resolver.lessonsByDayKey.sorted(by: { $0.key < $1.key }) {
            var scheduleIndex = defaultIndex
            if case .weekday(let weekday) = dayKey {
                scheduleIndex = resolver.timetable.timeStructure.bellScheduleID(for: weekday).flatMap { resolver.schedulesByID[$0] }
            }
            let sources = [defaultIndex, scheduleIndex].compactMap { $0 }
            var placed: [(lesson: Lesson, start: Int, end: Int)] = []
            for lesson in lessons {
                if case .success(let slot) = SlotPlacement.place(lesson.slot, in: scheduleIndex, ordinalSources: sources) {
                    placed.append((lesson, slot.startTime.minuteOfDay, slot.endTime.minuteOfDay))
                }
            }
            for week in weeks {
                let running = placed.filter { resolver.occurs($0.lesson, inCycleWeek: week) }
                var groups = UnionFind(count: running.count)
                for i in running.indices {
                    for j in running.indices where j > i {
                        let a = running[i], b = running[j]
                        if a.start < b.end && b.start < a.end
                            && validitiesMeet(a.lesson.validity, b.lesson.validity, terms: resolver.termsByID) {
                            groups.union(i, j)
                        }
                    }
                }
                for members in groups.groups() where members.count > 1 {
                    result.append(TemplateConflict(dayKey: dayKey, cycleWeek: week,
                                                   lessonIDs: members.map { running[$0].lesson.id }))
                }
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
            if lhs.cycleWeek != rhs.cycleWeek { return (lhs.cycleWeek ?? 0) < (rhs.cycleWeek ?? 0) }
            return lhs.lessonIDs.lexicographicallyPrecedes(rhs.lessonIDs)
        }
    }

    /// `true` when two validities share at least one date (deleted/unknown terms contribute no dates).
    public static func validitiesMeet(_ lhs: LessonValidity, _ rhs: LessonValidity, terms: [Term.ID: Term]) -> Bool {
        func ranges(_ validity: LessonValidity) -> [LocalDateRange]? { // nil = unbounded
            switch validity {
            case .always: return nil
            case .unknown: return [] // never shown
            case .range(let range): return range.isEmpty ? [] : [range]
            case .terms(let ids): return ids.compactMap { terms[$0]?.range }.filter { !$0.isEmpty }
            }
        }
        switch (ranges(lhs), ranges(rhs)) {
        case (nil, nil): return true
        case (nil, let other?), (let other?, nil): return !other.isEmpty
        case let (a?, b?): return a.contains { x in b.contains { x.overlaps($0) } }
        }
    }

    /// Connected groups (≥ 2 members) of overlapping intervals, by a sweep over start times.
    static func clusters<ID: Comparable>(of items: [(id: ID, start: Int, end: Int)]) -> [[ID]] {
        let sorted = items.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        var result: [[ID]] = []
        var current: [ID] = []
        var currentEnd = Int.min
        for item in sorted {
            if !current.isEmpty && item.start < currentEnd {
                current.append(item.id)
                currentEnd = max(currentEnd, item.end)
            } else {
                if current.count > 1 { result.append(current.sorted()) }
                current = [item.id]
                currentEnd = item.end
            }
        }
        if current.count > 1 { result.append(current.sorted()) }
        return result
    }
}

/// Minimal union–find for grouping template overlaps.
struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let (ra, rb) = (find(a), find(b))
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }

    /// Members grouped by root, each group ascending, groups ordered by their smallest member.
    mutating func groups() -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for index in parent.indices { byRoot[find(index), default: []].append(index) }
        return byRoot.values.sorted { $0[0] < $1[0] }
    }
}
