// View state of the Today tab: the Now & Next header and today's timeline (lessons + break/free separators), plus
// the next school day's lessons once today has nothing left. Built from `ScheduleResolver.nowAndNext(at:)`, so the
// header follows the engine's half-open boundaries (at a lesson's exact end it is no longer current). Pure,
// Linux-tested; the view only renders it and re-builds it once a minute (or never, with a fixed screenshot clock).
import Foundation
import TimetableCore

/// One row of a day's timeline.
public enum TodayItem: Equatable, Sendable, Identifiable {
    /// Where a lesson is relative to "now".
    public enum Timing: Equatable, Sendable { case past, current, upcoming }

    /// What fills a gap between lessons.
    public enum GapKind: Equatable, Sendable {
        /// A lunch period of the day's bell schedule lies in the gap.
        case lunch
        /// At least one whole lesson period of the bell schedule is free.
        case freePeriod
        /// A short break.
        case breakTime
    }

    case lesson(ResolvedLesson, reasons: [ModificationReason], timing: Timing)
    case gap(start: LocalTime, end: LocalTime, kind: GapKind)

    public var id: String {
        switch self {
        case let .lesson(lesson, _, _): return lesson.id.rawValue
        case let .gap(start, end, _): return "gap:\(start.isoString)-\(end.isoString)"
        }
    }

    /// The timing of a lesson (`nil` for gaps).
    public var timing: Timing? {
        if case let .lesson(_, _, timing) = self { return timing }
        return nil
    }

    /// Minutes of a gap (0 for lessons).
    public var gapMinutes: Int {
        if case let .gap(start, end, _) = self { return start.minutes(to: end) }
        return 0
    }
}

/// The Today tab.
public struct TodayState: Equatable, Sendable {
    /// The Now & Next header.
    public enum Header: Equatable, Sendable {
        /// A lesson is in progress; `next` is the following lesson (maybe on a later day).
        case current(ResolvedLesson, next: ResolvedLesson?)
        /// Before the first lesson or between lessons: `next` starts later today.
        case upcoming(ResolvedLesson, isFirstOfDay: Bool)
        /// Today's lessons are over; `next` is the next lesson within the horizon, if any.
        case dayOver(next: ResolvedLesson?)
        /// No lessons today (weekend, free day); `next` as above.
        case free(next: ResolvedLesson?)
        /// A holiday/break covers today (`name` = the break's user name).
        case holiday(name: String?, next: ResolvedLesson?)
        /// Today was cancelled ("cancel day" with an optional user note).
        case dayCancelled(note: String?, next: ResolvedLesson?)

        /// The next lesson shown by the header, if any.
        public var next: ResolvedLesson? {
            switch self {
            case let .current(_, next): return next
            case let .upcoming(lesson, _): return lesson
            case let .dayOver(next), let .free(next), let .holiday(_, next), let .dayCancelled(_, next): return next
            }
        }
    }

    public var date: LocalDate
    public var header: Header
    /// Today's lessons (cancelled ones included, struck through) with separators.
    public var items: [TodayItem]
    /// When today has nothing left: the next school day's schedule (the day of the header's next lesson).
    public var upcomingDay: DaySchedule?
    /// Its timeline (all upcoming).
    public var upcomingItems: [TodayItem]
    /// The last day of the holiday shown by a `.holiday` header ("until Fri, Oct 30"; U3).
    public var holidayEnd: LocalDate?
    /// Today's rotation position ("Week B"), for the navigation subtitle (U3, Opus L2).
    public var cycle: CycleLabel?

    /// "Rest of today" (U3, Opus H3.2 / Astra F14, verification D8): today's lessons that have not started yet, minus
    /// what the hero already shows (the current lesson, and its "Next" or the before-school / break lesson). Earlier
    /// lessons are in `earlierItems`. Gaps are dropped (the rows show times).
    public var remainingItems: [TodayItem] {
        items.filter { $0.timing == .upcoming && $0.id != header.next?.id.rawValue }
    }
    /// "Earlier today": the lessons that are over (a collapsed disclosure on Today).
    public var earlierItems: [TodayItem] { items.filter { $0.timing == .past } }

    /// What to bring for `items` (a day's timeline): the visible bring lists of the lessons that take place, in
    /// lesson order, without repeats (case-insensitive). Empty when the field is hidden or nothing is listed.
    public static func bringList(_ items: [TodayItem], visibility: FieldVisibility) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for case let .lesson(lesson, _, _) in items where lesson.status != .cancelled {
            for item in VisibleLessonFields(lesson: lesson, visibility: visibility).bringList
            where seen.insert(item.lowercased()).inserted {
                result.append(item)
            }
        }
        return result
    }

    /// Modification reasons of every listed occurrence (for the header's badge and VoiceOver sentence).
    public var reasonsByOccurrence: [OccurrenceID: [ModificationReason]] {
        var result: [OccurrenceID: [ModificationReason]] = [:]
        for item in items + upcomingItems {
            if case let .lesson(lesson, reasons, _) = item, !reasons.isEmpty { result[lesson.id] = reasons }
        }
        return result
    }

    /// Builds the state at `now` for the resolver's timetable. `database` provides break names, cancel-day notes and
    /// bell schedules (for gap kinds).
    public static func make(now: Date, resolver: ScheduleResolver, database: TabulaDatabase) -> TodayState {
        let today = resolver.context.localDate(of: now)
        let resolution = resolver.resolution(for: today)
        let schedule = resolution.schedule
        let nowNext = resolver.nowAndNext(at: now)
        let header: Header
        var holidayID = schedule.activeBreakID
        switch nowNext.state {
        case .inLesson:
            header = nowNext.current.map { .current($0, next: nowNext.next) } ?? .dayOver(next: nowNext.next)
        case .beforeFirstLesson, .betweenLessons:
            if let next = nowNext.next, next.date == today {
                header = .upcoming(next, isFirstOfDay: nowNext.state == .beforeFirstLesson)
            } else {
                header = .dayOver(next: nowNext.next)
            }
        case .afterLastLesson:
            header = .dayOver(next: nowNext.next)
        case .inBreak(let id):
            holidayID = id
            header = .holiday(name: breakName(id, database), next: nowNext.next)
        case .noLessonsToday:
            if let id = schedule.cancellingOverrideID {
                header = .dayCancelled(note: cancelNote(id, database), next: nowNext.next)
            } else if let id = schedule.activeBreakID {
                header = .holiday(name: breakName(id, database), next: nowNext.next)
            } else {
                header = .free(next: nowNext.next)
            }
        }
        let bell = bellSchedule(schedule.bellScheduleID, database)
        let items = timeline(schedule.entries, resolution: resolution, bell: bell, now: now)

        var upcomingDay: DaySchedule?
        var upcomingItems: [TodayItem] = []
        switch header {
        case .current, .upcoming:
            break
        case .dayOver, .free, .holiday, .dayCancelled:
            if let next = header.next, next.date != today {
                let nextResolution = resolver.resolution(for: next.date)
                upcomingDay = nextResolution.schedule
                upcomingItems = timeline(nextResolution.schedule.entries, resolution: nextResolution,
                                         bell: bellSchedule(nextResolution.schedule.bellScheduleID, database), now: now)
            }
        }
        var holidayEnd: LocalDate?
        if case .holiday = header, let holidayID {
            holidayEnd = database.breaks.first { $0.id == holidayID }?.range.end
        }
        return TodayState(date: today, header: header, items: items, upcomingDay: upcomingDay, upcomingItems: upcomingItems,
                          holidayEnd: holidayEnd, cycle: CycleLabel.of(schedule, scheme: resolver.timetable.rotation))
    }

    /// Lessons in wall-clock order with a gap item wherever time passes between the end of everything so far and the
    /// next start (overlapping lessons produce no gap).
    public static func timeline(_ entries: [ResolvedLesson], resolution: DayResolution, bell: BellSchedule?,
                                now: Date) -> [TodayItem] {
        var items: [TodayItem] = []
        var latestEnd: LocalTime?
        // Gaps are measured between lessons that take place; cancelled lessons are listed but do not close a gap.
        for entry in entries {
            if entry.status != .cancelled, let end = latestEnd, end < entry.startTime {
                items.append(.gap(start: end, end: entry.startTime, kind: gapKind(from: end, to: entry.startTime, bell: bell)))
            }
            let timing: TodayItem.Timing
            if entry.end <= now {
                timing = .past
            } else if entry.start <= now {
                timing = entry.status == .cancelled ? .upcoming : .current
            } else {
                timing = .upcoming
            }
            items.append(.lesson(entry, reasons: resolution.reasons(for: entry.id), timing: timing))
            if entry.status != .cancelled {
                latestEnd = max(latestEnd ?? entry.endTime, entry.endTime)
            }
        }
        return items
    }

    /// What a gap from `start` to `end` is, from the day's bell schedule (a plain break without one).
    public static func gapKind(from start: LocalTime, to end: LocalTime, bell: BellSchedule?) -> TodayItem.GapKind {
        guard let bell else { return .breakTime }
        let inside = bell.periods.filter { $0.start < end && start < $0.end }
        if inside.contains(where: { $0.kind == .lunch }) { return .lunch }
        if inside.contains(where: { $0.kind == .lesson && start <= $0.start && $0.end <= end }) { return .freePeriod }
        return .breakTime
    }

    private static func breakName(_ id: CalendarBreak.ID, _ database: TabulaDatabase) -> String? {
        nonBlank(database.breaks.first { $0.id == id }?.name)
    }

    private static func cancelNote(_ id: ScheduleOverride.ID, _ database: TabulaDatabase) -> String? {
        guard case .cancelDay(let note)? = database.overrides.first(where: { $0.id == id })?.change else { return nil }
        return nonBlank(note)
    }

    private static func bellSchedule(_ id: BellSchedule.ID?, _ database: TabulaDatabase) -> BellSchedule? {
        guard let id else { return nil }
        return database.bellSchedules.first { $0.id == id && !$0.isDeleted }
    }

    static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
