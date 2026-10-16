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
// per timeline, and well above the 5-minute spacing WidgetKit asks for, because lesson times are whole minutes).
// Live remaining time is NOT an entry: views use `Text(timerInterval:)` / `ProgressView(timerInterval:)`.
//
// Instants come from the snapshot's wall-clock values in the zone that applies now (`effectiveTimeZone`): after a
// time-zone change a "follow device" timetable's 08:00 lesson is at 08:00 in the new zone. A day outside the covered
// range (the app has not written for days, or the zone change moved "today" before the first covered day) is
// `.unavailable(.outdated)`: the widget asks to open the app instead of guessing.
//
// Reload: after the last entry when the list was cut at `maxEntries`, else at the end of the covered range (where
// the state becomes outdated); for an unavailable state `unavailableRetry` later (the app also reloads after writing).
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

    /// The calendar context the snapshot is planned in on a device in `deviceTimeZone`.
    public static func context(for snapshot: WidgetSnapshot, deviceTimeZone: TimeZone) -> CalendarContext {
        CalendarContext(timeZone: snapshot.effectiveTimeZone(device: deviceTimeZone), firstWeekday: .monday)
    }

    /// The timeline from `now`.
    public static func plan(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone) -> NowNextTimelinePlan {
        guard let snapshot else {
            return NowNextTimelinePlan(entries: [NowNextTimelineEntry(date: now, state: .unavailable(.noSnapshot))],
                                       reloadDate: now.addingTimeInterval(unavailableRetry), context: nil)
        }
        let context = context(for: snapshot, deviceTimeZone: deviceTimeZone)
        let first = entry(snapshot: snapshot, at: now, context: context)
        if case .unavailable = first.state {
            return NowNextTimelinePlan(entries: [first], reloadDate: now.addingTimeInterval(unavailableRetry),
                                       context: context)
        }
        var boundaries: Set<Date> = []
        for day in snapshot.days {
            boundaries.insert(context.startOfDay(day.date.adding(days: 1)))
            for lesson in day.lessons where lesson.takesPlace {
                boundaries.insert(lesson.start(in: context))
                boundaries.insert(lesson.end(in: context))
            }
        }
        let future = boundaries.filter { $0 > now }.sorted()
        let kept = future.prefix(maxEntries - 1)
        var entries = [first]
        for date in kept {
            entries.append(entry(snapshot: snapshot, at: date, context: context))
        }
        let coverageEnd = snapshot.lastDay.map { context.startOfDay($0.adding(days: 1)) } ?? now
        let reload = kept.count < future.count ? (kept.last ?? now) : max(coverageEnd, now)
        return NowNextTimelinePlan(entries: entries, reloadDate: reload, context: context)
    }

    /// The entry (state + later lessons) at `instant`.
    public static func entry(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextTimelineEntry {
        let state = state(snapshot: snapshot, at: instant, context: context)
        var later: [WidgetSnapshot.Lesson] = []
        if let next = state.next, let day = snapshot.day(next.date) {
            let nextStart = next.start(in: context)
            later = active(day, context).filter { candidate in
                candidate.id != next.id && candidate.start(in: context) >= nextStart && candidate.start(in: context) > instant
            }
            .prefix(maxLaterLessons).map { $0 }
        }
        return NowNextTimelineEntry(date: instant, state: state, laterLessons: later)
    }

    /// The state at `instant`.
    public static func state(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextState {
        guard snapshot.hasTimetable else { return .unavailable(.noTimetable) }
        let today = context.localDate(of: instant)
        guard let day = snapshot.day(today) else { return .unavailable(.outdated) }
        let lessons = active(day, context)
        let running = lessons.filter { $0.start(in: context) <= instant && instant < $0.end(in: context) }
        let current = running.max { lhs, rhs in
            let (ls, rs) = (lhs.start(in: context), rhs.start(in: context))
            if ls != rs { return ls < rs }
            let (le, re) = (lhs.end(in: context), rhs.end(in: context))
            if le != re { return le > re }
            return lhs.id > rhs.id
        }
        let next = nextLesson(after: instant, from: today, snapshot: snapshot, context: context)
        if let current { return .current(current, next: next) }
        if lessons.isEmpty {
            switch day.kind {
            case .holiday: return .holiday(name: day.note, next: next)
            case .cancelled: return .dayCancelled(note: day.note, next: next)
            case .school, .free: return .free(next: next)
            }
        }
        let lastEnd = lessons.map { $0.end(in: context) }.max() ?? instant
        if instant >= lastEnd { return .dayOver(next: next) }
        // Before the first lesson or between lessons (TodayState: only "upcoming" when the next lesson is today).
        guard let next, next.date == today else { return .dayOver(next: next) }
        return .upcoming(next, isFirstOfDay: instant < lessons[0].start(in: context))
    }

    // MARK: Internals

    /// Lessons that take place, by (start, end, id) like `ScheduleResolver`'s instant order.
    static func active(_ day: WidgetSnapshot.Day, _ context: CalendarContext) -> [WidgetSnapshot.Lesson] {
        day.lessons.filter(\.takesPlace).sorted { lhs, rhs in
            let (ls, rs) = (lhs.start(in: context), rhs.start(in: context))
            if ls != rs { return ls < rs }
            let (le, re) = (lhs.end(in: context), rhs.end(in: context))
            if le != re { return le < re }
            return lhs.id < rhs.id
        }
    }

    /// The first lesson that takes place and starts after `instant`: today, the later covered days, then the
    /// snapshot's following lesson.
    static func nextLesson(after instant: Date, from today: LocalDate, snapshot: WidgetSnapshot,
                           context: CalendarContext) -> WidgetSnapshot.Lesson? {
        for day in snapshot.days where day.date >= today {
            if let lesson = active(day, context).first(where: { $0.start(in: context) > instant }) { return lesson }
        }
        if let following = snapshot.followingLesson, following.start(in: context) > instant { return following }
        return nil
    }
}
