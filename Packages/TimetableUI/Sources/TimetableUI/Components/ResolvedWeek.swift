// The Timetable tab's shown week, resolved once per body pass (Phase 10 P11). Before, one pass resolved the same dates
// four to five times (week strip, lesson badges, grid / time-block layout, change reasons), and again every minute.
// Every output here equals the per-call factory it replaces (`WeekStripModel.make(selection:today:resolver:)`,
// `GridLayout.week(containing:resolver:)`, `TimeBlockLayout.week(containing:resolver:)`, `LessonWorkSupport.index`,
// the view's own change-reason loop): Linux equivalence tests in `Phase10WP1Tests`.
// Pure, Linux-tested.
import Foundation
import TimetableCore

/// The resolutions of one shown week (plus the selected day).
public struct ResolvedWeek: Sendable {
    public let selection: TimetableSelection
    public let resolver: ScheduleResolver
    /// The week start the layouts use (`context.startOfWeek(containing: selection.weekStart)`; normally the same day).
    public let layoutWeekStart: LocalDate
    private let resolutions: [LocalDate: DayResolution]

    /// Resolves the seven days from `selection.weekStart`, the layout week and the selected day, each date once.
    public init(selection: TimetableSelection, resolver: ScheduleResolver) {
        self.selection = selection
        self.resolver = resolver
        let layoutStart = resolver.context.startOfWeek(containing: selection.weekStart)
        layoutWeekStart = layoutStart
        var dates = (0..<7).map { selection.weekStart.adding(days: $0) }
        dates += (0..<7).map { layoutStart.adding(days: $0) }
        dates.append(selection.selectedDate)
        var resolutions: [LocalDate: DayResolution] = [:]
        for date in dates where resolutions[date] == nil {
            resolutions[date] = resolver.resolution(for: date)
        }
        self.resolutions = resolutions
    }

    /// `resolver.resolution(for: date)` (resolved now when the date is outside the week).
    public func resolution(for date: LocalDate) -> DayResolution {
        resolutions[date] ?? resolver.resolution(for: date)
    }

    /// `resolver.day(date)`.
    public func day(_ date: LocalDate) -> DaySchedule { resolution(for: date).schedule }

    /// = `WeekStripModel.make(selection:today:resolver:)`.
    public func strip(today: LocalDate) -> WeekStripModel {
        WeekStripModel.make(selection: selection, today: today, resolver: resolver, scheduleOf: { day($0) })
    }

    /// The layout week's dates the timetable shows (its enabled days), as `GridLayout.week` / `TimeBlockLayout.week`
    /// pick them.
    private var layoutDates: [LocalDate] {
        let shown = resolver.timetable.enabledDays
        return (0..<7).map { layoutWeekStart.adding(days: $0) }.filter { shown.contains($0.weekday) }
    }

    /// = `GridLayout.week(containing: selection.weekStart, resolver: resolver)`.
    public func gridLayout() -> TimetableCore.GridLayout {
        var layout = TimetableCore.GridLayout.make(days: layoutDates.map { day($0) }, resolver: resolver)
        layout.weekStart = layoutWeekStart
        layout.cycleWeek = resolver.rotation.cycleWeek(on: layoutWeekStart.adding(days: 3))
        layout.cycleLabel = layout.cycleWeek.flatMap(resolver.rotation.label(forCycleWeek:))
        return layout
    }

    /// = `TimeBlockLayout.week(containing: selection.weekStart, resolver: resolver)`.
    public func timeBlockWeekLayout() -> TimeBlockLayout {
        TimeBlockLayout.make(days: layoutDates.map { day($0) })
    }

    /// The modification reasons of every changed occurrence on `dates` (later dates win on a repeated id).
    public func reasons(for dates: [LocalDate]) -> [OccurrenceID: [ModificationReason]] {
        var result: [OccurrenceID: [ModificationReason]] = [:]
        for date in dates {
            for change in resolution(for: date).changes { result[change.occurrenceID] = change.reasons }
        }
        return result
    }

    /// = `LessonWorkSupport.index(dates: <7 days from weekStart> + [selectedDate], resolver:, database:)`.
    public func lessonWork(database: TabulaDatabase?) -> LessonWorkIndex {
        guard let database, !(database.tasks.isEmpty && database.exams.isEmpty) else { return .empty }
        var seen = Set<LocalDate>()
        let dates = (0..<7).map { selection.weekStart.adding(days: $0) } + [selection.selectedDate]
        let lessons = dates.filter { seen.insert($0).inserted }.flatMap { day($0).entries }
        return LessonWorkIndex.make(lessons: lessons, tasks: database.tasks, exams: database.exams)
    }
}
