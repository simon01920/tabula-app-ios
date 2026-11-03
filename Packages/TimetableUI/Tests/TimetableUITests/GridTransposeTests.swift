import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Human decision 2026-11-01: the default Grid layout is days × periods (`DayPeriodGrid`): period columns from the bell schedule,
// spans across breaks, rotation weeks, holidays, lessons outside the periods, free-form (university) columns, and the
// width / height maths.

private let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
private let today = SampleScenarios.today   // Tue 2026-10-13, week B in the secondary scenario
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func makeResolver(_ database: TabulaDatabase) throws -> ScheduleResolver {
    try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id, context: context))
}
private func grid(_ database: TabulaDatabase, week: LocalDate = today) throws -> DayPeriodGrid {
    DayPeriodGrid(GridLayout.week(containing: week, resolver: try makeResolver(database)))
}
/// The secondary scenario with an explicit lunch period between periods 4 and 5 (its own schedule has only gaps).
private func secondaryWithLunch() -> (database: TabulaDatabase, lunch: Period) {
    var database = SampleScenarios.secondary().database
    let periods = database.bellSchedules[0].periods
    let lunch = Period(id: Period.ID(UUID()), start: periods[3].end, end: periods[4].start, kind: .lunch)
    database.bellSchedules[0].periods.insert(lunch, at: 4)
    return (database, lunch)
}

@Suite("Grid days × periods")
struct GridTransposeTests {
    @Test func periodColumnsComeFromTheBellScheduleWithoutBreaks() throws {
        let database = secondaryWithLunch().database
        let layout = GridLayout.week(containing: today, resolver: try makeResolver(database))
        let grid = DayPeriodGrid(layout)
        #expect(layout.rows.contains { !$0.isLessonRow })   // the schedule has a lunch period …
        #expect(grid.periods.allSatisfy { $0.isLessonRow })      // … the grid has no break columns
        #expect(grid.periods.count == database.bellSchedules[0].lessonPeriods.count)
        #expect(grid.periods.map(\.lessonNumber) == Array(1...grid.periods.count).map(Optional.init))
        #expect(grid.days.map(\.date) == (12...16).map { date(2026, 10, $0) })
        #expect(grid.unplaced.isEmpty)
        // Every cell and free period sits inside the grid; no free period is covered by a cell.
        var covered = Set<[Int]>()
        for cell in grid.cells {
            #expect(cell.period >= 0 && cell.period + cell.span <= grid.periods.count)
            for period in cell.period..<(cell.period + cell.span) { covered.insert([cell.day, period]) }
        }
        for free in grid.free { #expect(!covered.contains([free.day, free.period])) }
        #expect(covered.count + grid.free.count == grid.days.count * grid.periods.count)
    }

    @Test func doublePeriodSpansTwoColumnsAcrossTheBreak() throws {
        let grid = try grid(secondaryWithLunch().database)
        let wednesday = grid.cells.filter { $0.day == 2 }
        let inf = try #require(wednesday.first { $0.cell.entry.subject.shortName == "INF" })
        #expect(inf.period == 3)        // period 4
        #expect(inf.span == 2)          // periods 4–5
        #expect(inf.cell.rowSpan > 2)   // the layout row span includes the break between them
        #expect(wednesday.first { $0.cell.entry.subject.shortName == "DEJ" }?.period == 5)
        #expect(wednesday.filter { $0.span == 1 }.count == wednesday.count - 1)
    }

    @Test func rotationWeeksShowTheirOwnLessons() throws {
        let database = SampleScenarios.secondary().database
        func tuesdayPeriod7(_ week: LocalDate) throws -> String? {
            try grid(database, week: week).cells.first { $0.day == 1 && $0.period == 6 }?.cell.entry.subject.shortName
        }
        #expect(try tuesdayPeriod7(today) == "ETV")              // week B
        #expect(try tuesdayPeriod7(date(2026, 10, 19)) == "INF") // week A
    }

    @Test func holidayDaysHaveNoCellsAndNoFreePeriods() throws {
        let grid = try grid(SampleScenarios.secondary().database, week: date(2026, 10, 26))
        let holidays = grid.days.filter { $0.activeBreakID != nil }.map(\.index)
        #expect(holidays == [3, 4])   // Thu 29 and Fri 30 October
        #expect(!grid.cells.contains { holidays.contains($0.day) })
        #expect(!grid.free.contains { holidays.contains($0.day) })
        #expect(grid.cells.contains { $0.day == 0 })
    }

    @Test func lessonsOutsideThePeriodsAreUnplaced() throws {
        let fixture = secondaryWithLunch()
        var database = fixture.database
        let breakPeriod = fixture.lunch
        var evening = database.lessons[0]
        evening.id = Lesson.ID(UUID())
        evening.slot = .time(start: time(19), end: time(19, 45))
        var onBreak = database.lessons[0]
        onBreak.id = Lesson.ID(UUID())
        onBreak.slot = .period(breakPeriod.id, span: 1)
        database.lessons += [evening, onBreak]
        let grid = try grid(database)
        // Both Monday extras are listed below the grid, by time; they never become cells.
        #expect(grid.unplaced.count == 2)
        #expect(grid.unplaced.map(\.date) == [date(2026, 10, 12), date(2026, 10, 12)])
        #expect(grid.unplaced.last?.startTime == time(19))
        let ids = Set(grid.unplaced.map(\.id))
        #expect(!grid.cells.contains { ids.contains($0.cell.entry.id) })
    }

    @Test func freeFormColumnsAreTheWeeksTimeSlotsAndOverlapsAreNotFree() throws {
        let grid = try grid(SampleScenarios.university())
        // 90-minute blocks at 8, 9, 10, 11, 13 and 14 o'clock: one column each, in time order, no spans.
        #expect(grid.periods.map(\.start) == [8, 9, 10, 11, 13, 14].map { time($0) })
        #expect(grid.periods.allSatisfy { $0.periodID == nil })
        #expect(grid.cells.allSatisfy { $0.span == 1 })
        #expect(grid.unplaced.isEmpty)
        // Monday (MA 8:00–9:30, LA 10:00–11:30, PROG 14:00–15:30): 9:00 and 11:00 fall inside a lecture, so only
        // 13:00 is offered as free.
        #expect(grid.free.filter { $0.day == 0 }.map(\.period) == [4])
        // Free-form slots have no period number in VoiceOver: "<date>, 13:00 to 14:30, free".
        let renderer = LocalizedTextRenderer(
            formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: SampleScenarios.timeZone),
            lookup: EnglishCatalog.lookup)
        let label = GridPresentation.freeSlotAccessibilityLabel(column: grid.days[0], row: grid.periods[4], renderer: renderer)
        #expect(!label.contains("period"))
        #expect(label.hasSuffix("13:00 to 14:30, free"))
    }

    @Test func currentPeriodOnlyWhenTodayIsShown() throws {
        let grid = try grid(SampleScenarios.secondary().database)
        let third = grid.periods[2]
        let minute = third.start.minuteOfDay + 5
        #expect(grid.isCurrent(period: 2, today: today, minuteOfDay: minute))
        #expect(!grid.isCurrent(period: 1, today: today, minuteOfDay: minute))
        #expect(!grid.isCurrent(period: 2, today: date(2026, 10, 20), minuteOfDay: minute))
        #expect(!grid.isCurrent(period: 99, today: today, minuteOfDay: minute))
    }

    @Test func widthsShareFitScrollAndExport() {
        // 7 periods share a 375 pt / 440 pt portrait phone next to a 36 pt day column.
        #expect(GridMode.periodColumnWidth(count: 7, availableWidth: 359, dayColumnWidth: 36) == (323.0 / 7, false))
        #expect(GridMode.periodColumnWidth(count: 7, availableWidth: 424, dayColumnWidth: 36).scrolls == false)
        // 13 periods (the aSc reference) scroll in portrait at the minimum width, fit in landscape.
        #expect(GridMode.periodColumnWidth(count: 13, availableWidth: 424, dayColumnWidth: 36) == (GridMode.minimumPeriodColumnWidth, true))
        #expect(GridMode.periodColumnWidth(count: 13, availableWidth: 900, dayColumnWidth: 36).scrolls == false)
        // Export: always all columns, no scroll.
        #expect(GridMode.periodColumnWidth(count: 13, availableWidth: 424, dayColumnWidth: 36, fitAll: true) == (388.0 / 13, false))
        #expect(GridMode.periodColumnWidth(count: 0, availableWidth: 424, dayColumnWidth: 36).scrolls == false)
        // Larger text: a wider minimum scrolls earlier.
        #expect(GridMode.periodColumnWidth(count: 7, availableWidth: 359, dayColumnWidth: 36, minimumWidth: 60).scrolls)
    }

    @Test func modeAndRowHeights() {
        #expect(GridMode.minimumPeriodColumnWidth >= TapTarget.minimum)
        #expect(GridMode.choose(isAccessibilitySize: false, availableWidth: 36 + 3 * GridMode.minimumPeriodColumnWidth,
                                dayColumnWidth: 36) == .grid)
        #expect(GridMode.choose(isAccessibilitySize: false, availableWidth: 35 + 3 * GridMode.minimumPeriodColumnWidth,
                                dayColumnWidth: 36) == .list)
        #expect(GridMode.choose(isAccessibilitySize: false, availableWidth: 359, dayColumnWidth: 36) == .grid)
        #expect(GridMode.choose(isAccessibilitySize: true, availableWidth: 900, dayColumnWidth: 36) == .list)
        #expect(GridMode.choose(isAccessibilitySize: false, availableWidth: 160, dayColumnWidth: 36) == .list)
        // Rows share the height between their minimum and maximum.
        #expect(GridMode.dayRowHeight(count: 5, available: 400, minimum: 50, maximum: 96) == 80)
        #expect(GridMode.dayRowHeight(count: 5, available: 900, minimum: 50, maximum: 96) == 96)
        #expect(GridMode.dayRowHeight(count: 7, available: 250, minimum: 50, maximum: 96) == 50)
        #expect(GridMode.dayRowHeight(count: 0, available: 250, minimum: 50, maximum: 96) == 50)
    }
}
