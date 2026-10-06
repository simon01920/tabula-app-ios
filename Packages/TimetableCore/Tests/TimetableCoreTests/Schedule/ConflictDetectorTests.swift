import Foundation
import Testing
@testable import TimetableCore

@Suite("ConflictDetector")
struct ConflictDetectorTests {
    private let d = Fixture.date
    private let t = Fixture.time

    @Test func overlapsFormConnectedGroupsAndIgnoreCancelled() {
        var world = ScheduleWorld()
        let a = world.lesson(world.math, .weekday(.tuesday), .time(start: t("08:00"), end: t("09:00")))
        let b = world.lesson(world.physics, .weekday(.tuesday), .time(start: t("08:30"), end: t("09:30")))
        let c = world.lesson(world.english, .weekday(.tuesday), .time(start: t("09:15"), end: t("10:00")))
        world.lesson(world.math, .weekday(.tuesday), .time(start: t("10:00"), end: t("10:45"))) // touches c: no overlap
        let cancelled = world.lesson(world.physics, .weekday(.tuesday), .time(start: t("07:00"), end: t("12:00")))
        world.override("2026-10-06", .cancelLesson(cancelled))
        let date = d("2026-10-06")
        let day = world.day("2026-10-06")
        let expected = Conflict(kind: .overlap, date: date, occurrenceIDs: [a, b, c].map { .lesson($0, on: date) })
        #expect(day.conflicts == [expected])
        #expect(day.conflicts[0].message == LocalizedText(key: "conflict.overlap", args: [.integer(3)]))
        #expect(ConflictDetector.overlaps(in: day.entries, on: date) == [expected])
        #expect(ConflictDetector.overlaps(in: [], on: date).isEmpty)
        // Two separate groups.
        world.lesson(world.math, .weekday(.tuesday), .time(start: t("10:30"), end: t("11:00")))
        #expect(world.day("2026-10-06").conflicts.count == 2)
    }

    @Test func onlyTheSameCycleWeekConflicts() {
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0))))
        let weekA = world.lesson(world.math, .monday, period: 1, weeks: [1])
        let weekB = world.lesson(world.physics, .monday, period: 1, weeks: [2])
        #expect(world.day("2026-10-05").conflicts.isEmpty && world.day("2026-10-12").conflicts.isEmpty)
        #expect(ConflictDetector.templateConflicts(in: world.resolver).isEmpty)
        let every = world.lesson(world.english, .monday, period: 1)
        let date = d("2026-10-05")
        #expect(world.day("2026-10-05").conflicts == [Conflict(kind: .overlap, date: date,
                                                               occurrenceIDs: [.lesson(weekA, on: date), .lesson(every, on: date)])])
        #expect(ConflictDetector.templateConflicts(in: world.resolver) == [
            TemplateConflict(dayKey: .weekday(.monday), cycleWeek: 1, lessonIDs: [weekA, every]),
            TemplateConflict(dayKey: .weekday(.monday), cycleWeek: 2, lessonIDs: [weekB, every]),
        ])
    }

    @Test func templateConflictsRespectValidityAndBellSchedules() {
        var world = ScheduleWorld()
        let winter = world.term("2026-09-01", "2027-01-31")
        let summer = world.term("2027-02-01", "2027-06-30")
        let gone = world.term("2026-09-01", "2027-06-30")
        world.terms[2].meta.isDeleted = true
        let w1 = world.lesson(world.math, .monday, period: 1, validity: .terms([winter]))
        world.lesson(world.physics, .monday, period: 1, validity: .terms([summer]))
        world.lesson(world.english, .monday, period: 1, validity: .terms([gone]))
        let r1 = world.lesson(world.math, .monday, period: 1,
                              validity: .range(LocalDateRange(start: d("2026-12-01"), end: d("2027-03-01"))))
        // Friday "Short": P1 ends 08:30, so a 08:35 lesson does not overlap it; on Monday it would.
        world.lesson(world.math, .friday, period: 1)
        world.lesson(world.physics, .weekday(.friday), .time(start: t("08:35"), end: t("09:00")))
        let tuesdayP1 = world.lesson(world.math, .tuesday, period: 1)
        let tuesdayLate = world.lesson(world.physics, .weekday(.tuesday), .time(start: t("08:35"), end: t("09:00")))
        let conflicts = ConflictDetector.templateConflicts(in: world.resolver)
        #expect(conflicts.count == 2, "Monday group + Tuesday pair; the Friday pair fits the short schedule")
        // winter ∩ range and summer ∩ range overlap → all three connected (winter and summer never meet directly);
        // the lesson in a deleted term never runs.
        #expect(conflicts[0].dayKey == .weekday(.monday) && conflicts[0].cycleWeek == nil && conflicts[0].lessonIDs.contains(w1)
                && conflicts[0].lessonIDs.contains(r1) && conflicts[0].lessonIDs.count == 3)
        #expect(conflicts[1] == TemplateConflict(dayKey: .weekday(.tuesday), cycleWeek: nil, lessonIDs: [tuesdayP1, tuesdayLate]))
        #expect(!conflicts.contains { $0.dayKey == .weekday(.friday) })
        #expect(conflicts[0].message.key == "conflict.overlap")
    }

    @Test func validitiesMeet() {
        var world = ScheduleWorld()
        let winter = world.term("2026-09-01", "2027-01-31")
        let summer = world.term("2027-02-01", "2027-06-30")
        let terms = Dictionary(uniqueKeysWithValues: world.terms.map { ($0.id, $0) })
        let october = LessonValidity.range(LocalDateRange(start: d("2026-10-01"), end: d("2026-10-31")))
        let empty = LessonValidity.range(LocalDateRange(start: d("2026-10-31"), end: d("2026-10-01")))
        #expect(ConflictDetector.validitiesMeet(.always, .always, terms: terms))
        #expect(ConflictDetector.validitiesMeet(.always, october, terms: terms))
        #expect(!ConflictDetector.validitiesMeet(.always, empty, terms: terms))
        #expect(ConflictDetector.validitiesMeet(.terms([winter]), october, terms: terms))
        #expect(!ConflictDetector.validitiesMeet(.terms([summer]), october, terms: terms))
        #expect(!ConflictDetector.validitiesMeet(.terms([winter]), .terms([summer]), terms: terms))
        #expect(ConflictDetector.validitiesMeet(.terms([winter, summer]), .terms([summer]), terms: terms))
        #expect(!ConflictDetector.validitiesMeet(.terms([]), .always, terms: terms))
    }
}

@Suite("Layouts")
struct LayoutTests {
    private let d = Fixture.date
    private let t = Fixture.time

    /// Mon P1×2 Math, Mon P4 Physics, Tue P3 English, Wed 12:30–13:00 English, Thu 18:00–19:00 Physics,
    /// Fri P3 Math (short Friday).
    private func gridWorld() -> (world: ScheduleWorld, late: Lesson.ID) {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1, span: 2)
        world.lesson(world.physics, .monday, period: 4)
        world.lesson(world.english, .tuesday, period: 3)
        world.lesson(world.english, .weekday(.wednesday), .time(start: t("12:30"), end: t("13:00")))
        let late = world.lesson(world.physics, .weekday(.thursday), .time(start: t("18:00"), end: t("19:00")))
        world.lesson(world.math, .friday, period: 3)
        return (world, late)
    }

    @Test func weekGridRowsCellsSpansAndEmptySlots() {
        let (world, late) = gridWorld()
        let grid = GridLayout.week(containing: d("2026-10-07"), resolver: world.resolver)
        #expect(grid.weekStart == d("2026-10-05") && grid.cycleWeek == nil && grid.referenceBellScheduleID == world.normalID)
        #expect(grid.columns.map(\.date) == (5...9).map { d("2026-10-0\($0)") })
        #expect(grid.columns.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(grid.rows.map(\.kind) == [.lesson, .breakTime, .lesson, .breakTime, .lesson, .lesson, .lunch, .lesson, .lesson])
        #expect(grid.rows.map(\.lessonNumber) == [1, nil, 2, nil, 3, 4, nil, 5, 6])
        #expect(grid.rows[4].label == "3rd" && grid.rows[0].start == t("08:00") && grid.rows[8].end == t("14:00"))
        let positions = grid.cells.map { [$0.column, $0.row, $0.rowSpan] }
        #expect(positions == [[0, 0, 3], [0, 5, 1], [1, 4, 1], [2, 7, 1], [4, 4, 1]])
        #expect(grid.cells[4].entry.startTime == t("09:20"), "short Friday's P3 sits in row P3")
        #expect(grid.unplaced.map(\.source) == [.lesson(late)])
        #expect(grid.emptySlots.count == 24)
        #expect(grid.emptySlots.filter { $0.column == 0 }.map(\.row) == [4, 7, 8])
        #expect(!grid.cells.contains { $0.isInConflict })

        let compact = GridLayout.week(containing: d("2026-10-07"), resolver: world.resolver, includeBreakRows: false)
        #expect(compact.rows.count == 6 && compact.rows.allSatisfy(\.isLessonRow))
        #expect(compact.cells.map { [$0.column, $0.row, $0.rowSpan] } == [[0, 0, 2], [0, 3, 1], [1, 2, 1], [2, 4, 1], [4, 2, 1]])
        let onlyTwo = GridLayout.week(containing: d("2026-10-07"), resolver: world.resolver, weekdays: [.friday, .monday])
        #expect(onlyTwo.columns.map(\.weekday) == [.monday, .friday])
    }

    @Test func gridShowsTheCycleWeekAndCanJumpToTheOther() {
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0),
                                                                 labels: ["A", "B"])))
        let a = world.lesson(world.math, .monday, period: 1, weeks: [1])
        let b = world.lesson(world.physics, .monday, period: 1, weeks: [2])
        let resolver = world.resolver
        let weekA = GridLayout.week(containing: d("2026-10-07"), resolver: resolver)
        #expect(weekA.cycleWeek == 1 && weekA.cycleLabel == "A" && weekA.cells.map(\.entry.source) == [.lesson(a)])
        let start = resolver.rotation.startOfWeek(withCycleWeek: 2, onOrAfter: d("2026-10-07"))!
        let weekB = GridLayout.week(containing: start, resolver: resolver, options: .regular)
        #expect(weekB.cycleWeek == 2 && weekB.cycleLabel == "B" && weekB.cells.map(\.entry.source) == [.lesson(b)])
        #expect(weekB.columns.allSatisfy { $0.cycleWeek == 2 && $0.cycleLabel == "B" })
    }

    @Test func weekStartAndDefaultWeek() {
        var sundayWorld = ScheduleWorld(enabledDays: [.sunday, .monday, .tuesday, .wednesday, .thursday], firstWeekday: .sunday)
        sundayWorld.lesson(sundayWorld.math, .sunday, period: 1)
        let grid = GridLayout.week(containing: d("2026-10-07"), resolver: sundayWorld.resolver)
        #expect(grid.weekStart == d("2026-10-04") && grid.columns.map(\.weekday) == [.sunday, .monday, .tuesday, .wednesday, .thursday])
        #expect(grid.cells.count == 1 && grid.cells[0].column == 0)
        #expect(GridLayout.displayWeekStart(today: d("2026-10-08"), resolver: sundayWorld.resolver) == d("2026-10-04"))
        #expect(GridLayout.displayWeekStart(today: d("2026-10-09"), resolver: sundayWorld.resolver) == d("2026-10-11"))
        let saturdayWorld = ScheduleWorld(enabledDays: Set(Weekday.allCases), firstWeekday: .saturday)
        #expect(GridLayout.week(containing: d("2026-10-07"), resolver: saturdayWorld.resolver).columns.first?.weekday == .saturday)
        let monday = ScheduleWorld().resolver
        #expect(GridLayout.displayWeekStart(today: d("2026-10-07"), resolver: monday) == d("2026-10-05"))
        #expect(GridLayout.displayWeekStart(today: d("2026-10-09"), resolver: monday) == d("2026-10-05"))
        #expect(GridLayout.displayWeekStart(today: d("2026-10-10"), resolver: monday) == d("2026-10-12"))
        #expect(GridLayout.displayWeekStart(today: d("2026-10-11"), resolver: monday) == d("2026-10-12"))
    }

    @Test func holidaysCancellationsConflictsAndVariantsInTheGrid() {
        var (world, _) = gridWorld()
        let autumn = world.holiday("2026-10-07", "2026-10-07")
        world.override("2026-10-06", .cancelDay(note: nil))
        world.lesson(world.english, .monday, period: 4) // overlaps Physics P4 on Monday
        let v: [Period.ID] = (0..<6).map { _ in world.ids.next() }
        let variant = world.bellSchedule(v.enumerated().map { index, id in
            Period(id: id, start: LocalTime(hour: 7 + index, minute: 0)!, end: LocalTime(hour: 7 + index, minute: 40)!)
        })
        world.override("2026-10-08", .useBellSchedule(variant))
        world.lesson(world.math, .thursday, period: 2)
        let grid = GridLayout.week(containing: d("2026-10-07"), resolver: world.resolver)
        #expect(!grid.columns[1].isSchoolDay && grid.columns[1].cancellingOverrideID != nil)
        #expect(grid.cells.filter { $0.column == 1 }.map(\.entry.status) == [.cancelled])
        #expect(grid.columns[2].activeBreakID == autumn && grid.cells.filter { $0.column == 2 }.isEmpty)
        #expect(!grid.emptySlots.contains { $0.column == 1 || $0.column == 2 })
        let mondayP4 = grid.cells.filter { $0.column == 0 && $0.row == 5 }
        #expect(mondayP4.count == 2)
        #expect(mondayP4.allSatisfy { $0.isInConflict })
        let thursday = grid.cells.first { $0.column == 3 }!
        #expect(thursday.row == 2 && thursday.entry.periodID == v[1] && thursday.entry.startTime == t("08:00"))
        #expect(grid.columns[3].bellScheduleID == variant)
    }

    @Test func freeFormAndDayCycleGrids() {
        var free = ScheduleWorld(freeForm: true)
        free.lesson(free.math, .weekday(.monday), .time(start: t("09:00"), end: t("10:30")))
        free.lesson(free.physics, .weekday(.tuesday), .time(start: t("09:00"), end: t("10:30")))
        free.lesson(free.english, .weekday(.tuesday), .time(start: t("11:00"), end: t("12:30")))
        free.lesson(free.math, .weekday(.wednesday), .time(start: t("08:00"), end: t("09:00")))
        let grid = GridLayout.week(containing: d("2026-10-07"), resolver: free.resolver)
        #expect(grid.referenceBellScheduleID == nil && grid.rows.map(\.start) == [t("08:00"), t("09:00"), t("11:00")])
        #expect(grid.rows.map(\.lessonNumber) == [1, 2, 3] && grid.rows.allSatisfy { $0.periodID == nil })
        #expect(grid.cells.map { [$0.column, $0.row] } == [[0, 1], [1, 1], [1, 2], [2, 0]])
        #expect(grid.emptySlots.count == 11 && grid.unplaced.isEmpty)

        var cycle = ScheduleWorld(rotation: .dayCycle(DayCycle(length: 3, anchorDate: d("2026-09-01"))))
        cycle.lesson(cycle.math, .cycleDay(1), .period(cycle.p[0], span: 1))
        cycle.lesson(cycle.physics, .cycleDay(2), .period(cycle.p[1], span: 1))
        cycle.lesson(cycle.english, .cycleDay(3), .period(cycle.p[2], span: 1))
        cycle.holiday("2026-09-04", "2026-09-04")
        let days = GridLayout.dayCycle(startingOnOrAfter: d("2026-09-02"), resolver: cycle.resolver)!
        // Sep 4 is a holiday (paused), so cycle day 1 next falls on Monday Sep 7.
        #expect(days.columns.map(\.date) == [d("2026-09-07"), d("2026-09-08"), d("2026-09-09")])
        #expect(days.columns.map(\.dayKey) == [.cycleDay(1), .cycleDay(2), .cycleDay(3)])
        #expect(days.cells.map { [$0.column, $0.row] } == [[0, 0], [1, 2], [2, 4]])
        #expect(GridLayout.dayCycle(startingOnOrAfter: d("2026-09-02"), resolver: free.resolver) == nil)
    }

    // MARK: Time blocks

    @Test func timeBlocksUseProportionalWallClockPositions() {
        var world = ScheduleWorld()
        world.lesson(world.math, .tuesday, period: 1)
        world.lesson(world.physics, .tuesday, period: 6)
        world.lesson(world.english, .weekday(.wednesday), .time(start: t("09:10"), end: t("10:20")))
        let layout = TimeBlockLayout.week(containing: d("2026-10-07"), resolver: world.resolver, weekdays: [.tuesday, .wednesday])
        #expect(layout.startMinute == 480 && layout.endMinute == 840 && layout.columns.map(\.date) == [d("2026-10-06"), d("2026-10-07")])
        let tops: [Double] = [0, 315.0 / 360, 70.0 / 360]
        let heights: [Double] = [45.0 / 360, 45.0 / 360, 70.0 / 360]
        #expect(layout.blocks.map(\.top) == tops)
        #expect(layout.blocks.map(\.height) == heights)
        #expect(layout.blocks.allSatisfy { $0.laneCount == 1 && $0.lane == 0 && !$0.isClippedAtStart && !$0.isClippedAtEnd })
        #expect(layout.hourMarks.map(\.minuteOfDay) == [480, 540, 600, 660, 720, 780, 840])
        #expect(layout.hourMarks.first?.position == 0 && layout.hourMarks.last?.position == 1)
        #expect(layout.position(of: t("11:00")) == 0.5 && layout.outOfBounds.isEmpty)
        let exact = TimeBlockLayout.week(containing: d("2026-10-07"), resolver: world.resolver,
                                         bounds: .automatic(snapMinutes: 0, fallbackStart: t("08:00"), fallbackEnd: t("16:00")))
        #expect(exact.startMinute == 480 && exact.endMinute == 840)
        let snapped = TimeBlockLayout.week(containing: d("2026-10-07"), resolver: world.resolver,
                                           bounds: .automatic(snapMinutes: 90, fallbackStart: t("08:00"), fallbackEnd: t("16:00")))
        #expect(snapped.startMinute == 450 && snapped.endMinute == 900)
    }

    @Test func fixedBoundsClipAndExclude() {
        var world = ScheduleWorld()
        let early = world.lesson(world.math, .tuesday, period: 1)
        world.lesson(world.physics, .tuesday, period: 6)
        let layout = TimeBlockLayout.week(containing: d("2026-10-07"), resolver: world.resolver, weekdays: [.tuesday],
                                          bounds: .fixed(start: t("09:00"), end: t("13:30")))
        #expect(layout.startMinute == 540 && layout.endMinute == 810)
        #expect(layout.outOfBounds.map(\.source) == [.lesson(early)] && layout.blocks.count == 1)
        let clipped = layout.blocks[0]
        #expect(clipped.isClippedAtEnd && !clipped.isClippedAtStart && clipped.top == 255.0 / 270 && clipped.height == 15.0 / 270)
        let degenerate = TimeBlockLayout.make(days: [], bounds: .fixed(start: t("10:00"), end: t("10:00")))
        #expect(degenerate.startMinute == 600 && degenerate.endMinute == 660)
        let late = TimeBlockLayout.make(days: [], bounds: .fixed(start: t("23:30"), end: t("23:00")))
        #expect(late.endMinute == 1440 && late.startMinute < late.endMinute)
        let empty = TimeBlockLayout.make(days: [world.day("2026-10-10")])
        #expect(empty.startMinute == 480 && empty.endMinute == 960 && empty.blocks.isEmpty && empty.columns.count == 1)
    }

    @Test func overlappingBlocksGetLanes() {
        var world = ScheduleWorld()
        world.lesson(world.math, .weekday(.tuesday), .time(start: t("08:00"), end: t("09:00")))
        world.lesson(world.physics, .weekday(.tuesday), .time(start: t("08:30"), end: t("09:30")))
        world.lesson(world.english, .weekday(.tuesday), .time(start: t("09:00"), end: t("10:00")))
        let solo = world.lesson(world.math, .weekday(.tuesday), .time(start: t("11:00"), end: t("11:45")))
        let cancelled = world.lesson(world.physics, .weekday(.tuesday), .time(start: t("12:00"), end: t("13:00")))
        world.override("2026-10-06", .cancelLesson(cancelled))
        let layout = TimeBlockLayout.make(days: [world.day("2026-10-06")])
        #expect(layout.blocks.map(\.lane) == [0, 1, 0, 0, 0])
        #expect(layout.blocks.map(\.laneCount) == [2, 2, 2, 1, 1])
        #expect(layout.blocks.map(\.isInConflict) == [true, true, true, false, false])
        #expect(layout.blocks[3].entry.source == .lesson(solo))
        let withoutCancelled = TimeBlockLayout.make(days: [world.day("2026-10-06")], includeCancelled: false)
        #expect(withoutCancelled.blocks.count == 4 && withoutCancelled.endMinute == 720)
    }

    @Test func blockHeightsIgnoreDSTDayLength() {
        var world = ScheduleWorld(enabledDays: Set(Weekday.allCases))
        world.lesson(world.math, .weekday(.sunday), .time(start: t("08:00"), end: t("08:45")))
        let normal = TimeBlockLayout.make(days: [world.day("2026-03-22")])
        let shortDay = TimeBlockLayout.make(days: [world.day("2026-03-29")]) // 23-hour day
        #expect(world.context.secondsInDay(d("2026-03-29")) == 82_800)
        #expect(normal.blocks.map(\.height) == shortDay.blocks.map(\.height) && normal.blocks.map(\.top) == shortDay.blocks.map(\.top))
    }
}
