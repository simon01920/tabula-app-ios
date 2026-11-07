// Plans a widget timeline from a `WidgetSnapshot` (PHASE4_PLAN §0.1): the entry dates, the Now & Next state of each
// entry and the reload date. Pure, Linux-tested; the widget extension's TimelineProvider only maps the result.
//
// State at an instant mirrors `ScheduleResolver.nowAndNext(at:)` + `TodayState.make` exactly (tested against them on
// the seeded scenarios): half-open lesson boundaries, cancelled lessons ignored, the current lesson of overlapping ones
// is the one that started last; before/between lessons → "upcoming" (first of day or not); after the last lesson →
// "day over"; a day without lessons → holiday (break) / cancelled day / free day, each with the next lesson.
//
// Entries: `now`, then every start and end of a lesson that takes place, and every midnight of the covered days (the
// day changes the state: "tomorrow" becomes "today", a holiday begins) — at most `maxEntries` (ARCHITECTURE.md: < 30
// per timeline). Spacing: entries are whole-minute lesson boundaries, so they are usually a break (often exactly 5
// minutes) apart, but a 1–4-minute changeover produces entries closer than the "at least about 5 minutes" WidgetKit
// recommends. They are kept on purpose: merging them would show a finished lesson (timer at 0:00) or a lesson that has
// not started for those minutes. Boundary entries are at least 1 minute apart (identical instants are merged); only the
// first entry, at `now`, can be closer to the next one.
// Live remaining time is NOT an entry: views use `Text(timerInterval:)` / `ProgressView(timerInterval:)`.
//
// Instants come from the snapshot's wall-clock values in the zone that applies now (`effectiveTimeZone`): after a
// time-zone change a "follow device" timetable's 08:00 lesson is at 08:00 in the new zone. A day outside the covered
// range (the app has not written for days, or the zone change moved "today" before the first covered day) is
// `.unavailable(.outdated)`: the widget asks to open the app instead of guessing.
//
// Reload: when the list was cut at `maxEntries`, at its last midnight (else its last entry); otherwise at the end of
// the covered range (where the state becomes outdated); for an unavailable state `unavailableRetry` later. Always at
// most `maxReloadInterval` after now, because WidgetKit does not reload on a time-zone change and the next natural
// reload can be days away (the app also reloads after every write).
import Foundation
import TimetableCore

/// What Now & Next shows at one instant.
public enum NowNextState: Equatable, Sendable {
    /// Why nothing can be shown.
    public enum Unavailable: Equatable, Sendable {
        /// No snapshot (no App Group, the app never ran, unreadable file).
        case noSnapshot
        /// The app has no timetable yet (onboarding).
        case noTimetable
        /// "Today" lies outside the snapshot's days.
        case outdated
    }

    /// A lesson is in progress; `next` is the following lesson (maybe on a later day).
    case current(WidgetSnapshot.Lesson, next: WidgetSnapshot.Lesson?)
    /// Before the first lesson or between lessons; the lesson starts later today.
    case upcoming(WidgetSnapshot.Lesson, isFirstOfDay: Bool)
    /// Today's lessons are over.
    case dayOver(next: WidgetSnapshot.Lesson?)
    /// No lessons today.
    case free(next: WidgetSnapshot.Lesson?)
    /// A holiday covers today.
    case holiday(name: String?, next: WidgetSnapshot.Lesson?)
    /// Today was cancelled.
    case dayCancelled(note: String?, next: WidgetSnapshot.Lesson?)
    /// Nothing to show; the widget offers to open the app.
    case unavailable(Unavailable)

    /// The next lesson shown, if any (the upcoming lesson itself for `.upcoming`).
    public var next: WidgetSnapshot.Lesson? {
        switch self {
        case let .current(_, next): return next
        case let .upcoming(lesson, _): return lesson
        case let .dayOver(next), let .free(next), let .holiday(_, next), let .dayCancelled(_, next): return next
        case .unavailable: return nil
        }
    }

    /// The lesson in progress, if any.
    public var current: WidgetSnapshot.Lesson? {
        if case let .current(lesson, _) = self { return lesson }
        return nil
    }
}

/// One timeline entry.
public struct NowNextTimelineEntry: Equatable, Sendable {
    /// When the entry becomes current.
    public var date: Date
    /// The state from `date` until the next entry.
    public var state: NowNextState
    /// Lessons after the shown next lesson on the same day (taking place, start order, at most
    /// `WidgetTimelinePlanner.maxLaterLessons`), for the medium family's list.
    public var laterLessons: [WidgetSnapshot.Lesson]

    public init(date: Date, state: NowNextState, laterLessons: [WidgetSnapshot.Lesson] = []) {
        self.date = date
        self.state = state
        self.laterLessons = laterLessons
    }
}

/// A planned timeline.
public struct NowNextTimelinePlan: Equatable, Sendable {
    /// Entries, ascending by date, the first at "now"; never empty.
    public var entries: [NowNextTimelineEntry]
    /// When WidgetKit should ask for a new timeline.
    public var reloadDate: Date
    /// The calendar context the instants were computed in (`nil` without a snapshot).
    public var context: CalendarContext?
}

public enum WidgetTimelinePlanner {
    /// Upper bound of entries per timeline (ARCHITECTURE.md budget: < 30).
    public static let maxEntries = 29
    /// Lessons listed after the next one.
    public static let maxLaterLessons = 3
    /// Reload delay while nothing can be shown.
    public static let unavailableRetry: TimeInterval = 6 * 3600
    /// The latest reload after `now` (time-zone changes, RISKS #67): ≤ 4 reloads a day, far below the 40–70 budget.
    public static let maxReloadInterval: TimeInterval = 6 * 3600

    /// The calendar context the snapshot is planned in on a device in `deviceTimeZone`.
    public static func context(for snapshot: WidgetSnapshot, deviceTimeZone: TimeZone) -> CalendarContext {
        CalendarContext(timeZone: snapshot.effectiveTimeZone(device: deviceTimeZone), firstWeekday: .monday)
    }

    /// The timeline from `now`. `includeCancelledBoundaries` also puts entries at the start / end of cancelled lessons
    /// (the Today widget lists them struck through and drops them when over); the Now & Next state ignores them.
    /// `includeTaskDueBoundaries` adds an entry one minute after each due time of a listed task (the large Today
    /// widget's "Due today" list flips a task to overdue then).
    public static func plan(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone,
                            includeCancelledBoundaries: Bool = false,
                            includeTaskDueBoundaries: Bool = false) -> NowNextTimelinePlan {
        guard let snapshot else {
            return NowNextTimelinePlan(entries: [NowNextTimelineEntry(date: now, state: .unavailable(.noSnapshot))],
                                       reloadDate: now.addingTimeInterval(unavailableRetry), context: nil)
        }
        let context = context(for: snapshot, deviceTimeZone: deviceTimeZone)
        // Phase 10 WP2 (C3): each day's lessons are resolved to instants and sorted once for the whole plan.
        var timed = TimedLessons(snapshot: snapshot, context: context)
        let first = entry(&timed, at: now)
        if case .unavailable = first.state {
            return NowNextTimelinePlan(entries: [first], reloadDate: now.addingTimeInterval(unavailableRetry),
                                       context: context)
        }
        var boundaries: Set<Date> = []
        var midnights: Set<Date> = []
        for day in snapshot.days {
            midnights.insert(context.startOfDay(day.date.adding(days: 1)))
            for lesson in day.lessons where lesson.takesPlace || includeCancelledBoundaries {
                let start = lesson.start(in: context)
                boundaries.insert(start)
                boundaries.insert(TimedLessons.end(of: lesson, start: start, in: context))
            }
        }
        if includeTaskDueBoundaries, let last = snapshot.lastDay {
            for task in snapshot.tasks {
                guard let time = task.dueTime, task.dueDate >= context.localDate(of: now), task.dueDate <= last else { continue }
                boundaries.insert(context.date(task.dueDate, time).addingTimeInterval(60))
            }
        }
        boundaries.formUnion(midnights)
        let future = boundaries.filter { $0 > now }.sorted()
        var kept = Array(future.prefix(maxEntries - 1))
        let isCut = kept.count < future.count
        // Cut at the last midnight inside the kept range: if the reload comes late, the last state (the next day's
        // "first lesson / starts in") stays valid for hours instead of a mid-day state that is wrong minutes later.
        if isCut, let lastMidnight = kept.lastIndex(where: { midnights.contains($0) }) {
            kept = Array(kept[...lastMidnight])
        }
        var entries = [first]
        for date in kept {
            entries.append(entry(&timed, at: date))
        }
        let coverageEnd = snapshot.lastDay.map { context.startOfDay($0.adding(days: 1)) } ?? now
        let natural = isCut ? (kept.last ?? now) : max(coverageEnd, now)
        // Never later than `maxReloadInterval`: WidgetKit does not reload on a time-zone change (RISKS #67), so a
        // re-plan in the current zone must come within hours even when the timeline itself would last for days.
        let reload = min(natural, now.addingTimeInterval(maxReloadInterval))
        return NowNextTimelinePlan(entries: entries, reloadDate: reload, context: context)
    }

    /// The entry (state + later lessons) at `instant`.
    public static func entry(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextTimelineEntry {
        var timed = TimedLessons(snapshot: snapshot, context: context)
        return entry(&timed, at: instant)
    }

    /// The state at `instant`.
    public static func state(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextState {
        var timed = TimedLessons(snapshot: snapshot, context: context)
        return state(&timed, at: instant)
    }

    // MARK: Internals

    /// The entry at `instant`, from lessons resolved at most once per day.
    static func entry(_ timed: inout TimedLessons, at instant: Date) -> NowNextTimelineEntry {
        let state = state(&timed, at: instant)
        var later: [WidgetSnapshot.Lesson] = []
        if let next = state.next, let index = timed.snapshot.dayIndex(next.date) {
            let nextStart = next.start(in: timed.context)
            later = timed.active(dayAt: index).filter { candidate in
                candidate.lesson.id != next.id && candidate.start >= nextStart && candidate.start > instant
            }
            .prefix(maxLaterLessons).map(\.lesson)
        }
        return NowNextTimelineEntry(date: instant, state: state, laterLessons: later)
    }

    /// The state at `instant`, from lessons resolved at most once per day.
    static func state(_ timed: inout TimedLessons, at instant: Date) -> NowNextState {
        let snapshot = timed.snapshot
        guard snapshot.hasTimetable else { return .unavailable(.noTimetable) }
        let today = timed.context.localDate(of: instant)
        guard let index = snapshot.dayIndex(today) else { return .unavailable(.outdated) }
        let day = snapshot.days[index]
        let lessons = timed.active(dayAt: index)
        let running = lessons.filter { $0.start <= instant && instant < $0.end }
        let current = running.max { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            return lhs.lesson.id > rhs.lesson.id
        }?.lesson
        let next = nextLesson(&timed, after: instant, from: today)
        if let current { return .current(current, next: next) }
        if lessons.isEmpty {
            switch day.kind {
            case .holiday: return .holiday(name: day.note, next: next)
            case .cancelled: return .dayCancelled(note: day.note, next: next)
            case .school, .free: return .free(next: next)
            }
        }
        let lastEnd = lessons.map(\.end).max() ?? instant
        if instant >= lastEnd { return .dayOver(next: next) }
        // Before the first lesson or between lessons (TodayState: only "upcoming" when the next lesson is today).
        guard let next, next.date == today else { return .dayOver(next: next) }
        return .upcoming(next, isFirstOfDay: instant < lessons[0].start)
    }

    /// Lessons that take place, by (start, end, id) like `ScheduleResolver`'s instant order.
    static func active(_ day: WidgetSnapshot.Day, _ context: CalendarContext) -> [WidgetSnapshot.Lesson] {
        TimedLessons.active(day, context).map(\.lesson)
    }

    /// The first lesson that takes place and starts after `instant`: today, the later covered days, then the
    /// snapshot's following lesson.
    static func nextLesson(_ timed: inout TimedLessons, after instant: Date,
                           from today: LocalDate) -> WidgetSnapshot.Lesson? {
        for index in timed.snapshot.days.indices where timed.snapshot.days[index].date >= today {
            if let item = timed.active(dayAt: index).first(where: { $0.start > instant }) { return item.lesson }
        }
        if let following = timed.snapshot.followingLesson, let start = timed.followingStart, start > instant {
            return following
        }
        return nil
    }
}

/// The snapshot's lessons as instants in one planning context (Phase 10 WP2, C3). `Lesson.start(in:)` / `end(in:)` each
/// resolve a wall-clock time (DST policy) and `end` resolves the start again, and a plan asked for the same days'
/// sorted lessons for each of up to 29 entries. Here each day is filtered, resolved and sorted at most once (on first
/// use) and shared by every entry of the plan. The instants are exactly `start(in:)` / `end(in:)`, the order is the one
/// `WidgetTimelinePlanner.active` always had (same comparator on the same input order).
struct TimedLessons {
    /// One lesson that takes place, with its instants.
    struct Item {
        let lesson: WidgetSnapshot.Lesson
        /// `lesson.start(in: context)`.
        let start: Date
        /// `lesson.end(in: context)`.
        let end: Date
    }

    let snapshot: WidgetSnapshot
    let context: CalendarContext
    /// `snapshot.followingLesson?.start(in: context)`.
    let followingStart: Date?
    /// `active(snapshot.days[index], context)` by day index, filled on first use.
    private var days: [Int: [Item]] = [:]

    init(snapshot: WidgetSnapshot, context: CalendarContext) {
        self.snapshot = snapshot
        self.context = context
        followingStart = snapshot.followingLesson?.start(in: context)
    }

    /// The lessons of `snapshot.days[index]` that take place, by (start, end, id).
    mutating func active(dayAt index: Int) -> [Item] {
        if let cached = days[index] { return cached }
        let items = Self.active(snapshot.days[index], context)
        days[index] = items
        return items
    }

    /// The lessons of `day` that take place, by (start, end, id) like `ScheduleResolver`'s instant order.
    static func active(_ day: WidgetSnapshot.Day, _ context: CalendarContext) -> [Item] {
        day.lessons.filter(\.takesPlace)
            .map { lesson -> Item in
                let start = lesson.start(in: context)
                return Item(lesson: lesson, start: start, end: end(of: lesson, start: start, in: context))
            }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.end != rhs.end { return lhs.end < rhs.end }
                return lhs.lesson.id < rhs.lesson.id
            }
    }

    /// `lesson.end(in: context)` when `start == lesson.start(in: context)` (one resolve instead of two).
    static func end(of lesson: WidgetSnapshot.Lesson, start: Date, in context: CalendarContext) -> Date {
        max(start, context.date(lesson.date, lesson.endTime))
    }
}

extension WidgetSnapshot {
    /// The index in `days` of the day `day(_:)` returns for `date`, if any.
    func dayIndex(_ date: LocalDate) -> Int? {
        guard let first = firstDay else { return nil }
        let offset = first.days(to: date)
        guard days.indices.contains(offset), days[offset].date == date else { return days.firstIndex { $0.date == date } }
        return offset
    }
}
