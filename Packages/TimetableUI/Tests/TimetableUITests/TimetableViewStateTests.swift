import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Stage B2: pure view state of the Today and Timetable tabs (week strip, selection, Today timeline, grid list
// fallback, quick add, lesson detail, labels), checked against the deterministic sample scenarios.

private let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(day, time(h, m)) }
private func makeResolver(_ database: TabulaDatabase) throws -> ScheduleResolver {
    try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id, context: context))
}
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: SampleScenarios.timeZone),
    lookup: EnglishCatalog.lookup)
private let today = SampleScenarios.today   // Tue 2026-10-13, ISO week 42 = week B in the secondary scenario

@Suite("Timetable navigation")
struct TimetableNavigationTests {
    @Test func initialSelectionOnASchoolDayAndAtTheWeekend() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        #expect(TimetableSelection.initial(today: today, resolver: resolver)
                == TimetableSelection(weekStart: date(2026, 10, 12), selectedDate: today))
        // Saturday: this week's school days are over → next week, its first school day.
        #expect(TimetableSelection.initial(today: date(2026, 10, 17), resolver: resolver)
                == TimetableSelection(weekStart: date(2026, 10, 19), selectedDate: date(2026, 10, 19)))
    }

    @Test func weekShiftKeepsTheWeekdayAndCycleJumpFindsWeekA() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let start = TimetableSelection.initial(today: today, resolver: resolver)
        #expect(start.shifted(byWeeks: 1, resolver: resolver)
                == TimetableSelection(weekStart: date(2026, 10, 19), selectedDate: date(2026, 10, 20)))
        #expect(start.shifted(byWeeks: -2, resolver: resolver).weekStart == date(2026, 9, 28))
        let weekA = try #require(TimetableSelection.week(withCycleWeek: 1, onOrAfter: today, today: today, resolver: resolver))
        #expect(weekA.weekStart == date(2026, 10, 19))
        #expect(TimetableSelection.week(withCycleWeek: 2, onOrAfter: today, today: today, resolver: resolver)?.weekStart
                == date(2026, 10, 12))
        #expect(TimetableSelection.week(withCycleWeek: 3, onOrAfter: today, today: today, resolver: resolver) == nil)
        // No rotation → no cycle jump.
        let elementary = try makeResolver(SampleScenarios.elementary())
        #expect(TimetableSelection.week(withCycleWeek: 1, onOrAfter: today, today: today, resolver: elementary) == nil)
    }

    @Test func viewChoiceAndLabels() {
        #expect(TimetableViewChoice.resolve(.tiles) == .tiles)
        #expect(TimetableViewChoice.resolve(.agenda) == .day)
        #expect(TimetableViewChoice.resolve(TimetableViewKind(rawValue: "fromTheFuture")) == .grid)
        #expect(TimetableViewChoice.nameKey(.timeBlocks) == "timetable.view.timeBlocks")
        #expect(TimetableViewChoice.offered.allSatisfy { EnglishCatalog.values[TimetableViewChoice.nameKey($0)] != nil })
        #expect(TimetableViewChoice.isDayBased(.tiles) && !TimetableViewChoice.isDayBased(.grid))

        let ab = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        let four = RotationScheme.weekCycle(WeekCycle(length: 4, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        #expect(CycleLabel.week(2, scheme: ab, userLabel: nil) == .namedWeek("B"))
        #expect(CycleLabel.week(2, scheme: ab, userLabel: " Odd ") == .namedWeek("Odd"))
        #expect(CycleLabel.week(3, scheme: four, userLabel: nil) == .numberedWeek(3))
        #expect(CycleLabel.week(1, scheme: .none, userLabel: "A") == nil)
        #expect(CycleLabel.day(.cycleDay(2), userLabel: "B") == .namedDay("B"))
        #expect(CycleLabel.day(.weekday(.monday), userLabel: nil) == nil)
        #expect(CycleLabel.namedWeek("A").text(renderer: renderer) == "Week A")
        #expect(CycleLabel.numberedWeek(3).text(renderer: renderer) == "Week 3")
        #expect(CycleLabel.numberedDay(4).text(renderer: renderer) == "Day 4")
    }
}

@Suite("Week strip")
struct WeekStripTests {
    @Test func secondaryWeekHasChangeDotsAndCycleLabel() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let strip = WeekStripModel.make(selection: TimetableSelection.initial(today: today, resolver: resolver),
                                        today: today, resolver: resolver)
        #expect(strip.days.map(\.date) == (12...16).map { date(2026, 10, $0) })
        #expect(strip.days.map(\.isToday) == [false, true, false, false, false])
        #expect(strip.days.map(\.isSelected) == [false, true, false, false, false])
        #expect(strip.days.map(\.hasChanges) == [false, false, false, true, false])   // Thursday: short day + changes
        #expect(strip.cycleWeek == .namedWeek("B"))
        #expect(strip.containsToday)
        let tuesday = strip.days[1]
        #expect(WeekStripModel.accessibilityLabel(tuesday, renderer: renderer)
                == renderer.formatter.date(today, style: .full) + ", today, 7 lessons")
        let thursday = WeekStripModel.accessibilityLabel(strip.days[3], renderer: renderer)
        #expect(thursday.contains("changes") || thursday.contains("change"))
    }

    @Test func holidayWeek() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let holidayWeek = TimetableSelection(weekStart: date(2026, 10, 26), selectedDate: date(2026, 10, 29))
        let strip = WeekStripModel.make(selection: holidayWeek, today: today, resolver: resolver)
        #expect(strip.days.map(\.isInBreak) == [false, false, false, true, true])
        #expect(strip.days[3].lessonCount == 0 && !strip.days[3].isSchoolDay)
        #expect(!strip.containsToday)
        #expect(WeekStripModel.accessibilityLabel(strip.days[3], renderer: renderer).hasSuffix("holiday"))
    }
}

@Suite("Today state")
struct TodayStateTests {
    @Test func inLessonWithTimelineAndGaps() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let state = TodayState.make(now: SampleScenarios.referenceNow, resolver: resolver, database: scenario.database)
        guard case let .current(current, next) = state.header else {
            Issue.record("expected a current lesson, got \(state.header)")
            return
        }
        #expect(current.start <= SampleScenarios.referenceNow && SampleScenarios.referenceNow < current.end)
        #expect(next.map { $0.start >= current.end } == true)
        let lessons = state.items.compactMap { item -> TodayItem.Timing? in
            if case let .lesson(_, _, timing) = item { return timing }
            return nil
        }
        #expect(lessons.count == 7)
        #expect(lessons.filter { $0 == .current }.count == 1)
        #expect(lessons.first == .past && lessons.last == .upcoming)
        // Separators only between lessons, never first or last, never zero-length.
        #expect(state.items.first.map { $0.gapMinutes == 0 } == true)
        #expect(state.items.last.map { $0.gapMinutes == 0 } == true)
        #expect(state.items.allSatisfy { item in
            if case .gap = item { return item.gapMinutes > 0 }
            return true
        })
        #expect(state.upcomingDay == nil && state.upcomingItems.isEmpty)
    }

    @Test func beforeFirstLessonAndAfterTheLast() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let early = TodayState.make(now: instant(today, 6, 30), resolver: resolver, database: scenario.database)
        guard case let .upcoming(first, isFirst) = early.header else {
            Issue.record("expected upcoming, got \(early.header)")
            return
        }
        #expect(isFirst && first.date == today)
        let evening = TodayState.make(now: instant(today, 20), resolver: resolver, database: scenario.database)
        guard case let .dayOver(next) = evening.header else {
            Issue.record("expected dayOver, got \(evening.header)")
            return
        }
        #expect(next?.date == date(2026, 10, 14))
        #expect(evening.upcomingDay?.date == date(2026, 10, 14))
        #expect(!evening.upcomingItems.isEmpty)
        #expect(evening.items.allSatisfy { item in
            if case let .lesson(_, _, timing) = item { return timing == .past }
            return true
        })
    }

    @Test func weekendHolidayAndCancelledDay() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let saturday = TodayState.make(now: instant(date(2026, 10, 17), 11), resolver: resolver, database: scenario.database)
        guard case let .free(next) = saturday.header else {
            Issue.record("expected free, got \(saturday.header)")
            return
        }
        #expect(next?.date == date(2026, 10, 19) && saturday.items.isEmpty)
        #expect(saturday.upcomingDay?.date == date(2026, 10, 19))

        let holiday = TodayState.make(now: instant(date(2026, 10, 29), 9), resolver: resolver, database: scenario.database)
        #expect(holiday.header == .holiday(name: "Jesenné prázdniny", next: holiday.header.next))
        #expect(holiday.header.next?.date == date(2026, 11, 2))

        var database = SampleScenarios.elementary()
        let timetable = database.timetables[0]
        database.overrides.append(ScheduleOverride(id: ScheduleOverride.ID(UUID()), meta: .created(at: .zero),
                                                   timetableID: timetable.id, date: date(2026, 10, 14),
                                                   change: .cancelDay(note: "  Výlet  ")))
        let cancelled = TodayState.make(now: instant(date(2026, 10, 14), 9), resolver: try makeResolver(database),
                                        database: database)
        guard case let .dayCancelled(note, _) = cancelled.header else {
            Issue.record("expected dayCancelled, got \(cancelled.header)")
            return
        }
        #expect(note == "Výlet")
    }

    @Test func gapKindsFromTheBellSchedule() throws {
        let database = SampleScenarios.secondary().database
        let bell = try #require(database.bellSchedules.first)
        let lessons = bell.lessonPeriods
        // Between two consecutive lessons: a break.
        #expect(TodayState.gapKind(from: lessons[0].end, to: lessons[1].start, bell: bell) == .breakTime)
        // Lesson 2 skipped: a free period.
        #expect(TodayState.gapKind(from: lessons[0].end, to: lessons[2].start, bell: bell) == .freePeriod)
        #expect(TodayState.gapKind(from: time(9), to: time(10), bell: nil) == .breakTime)
    }

    @Test func freeFormUniversityDay() throws {
        let database = SampleScenarios.university()
        let state = TodayState.make(now: SampleScenarios.referenceNow, resolver: try makeResolver(database), database: database)
        guard case let .current(current, _) = state.header else {
            Issue.record("expected current, got \(state.header)")
            return
        }
        #expect(current.subject.shortName == "DBS")
    }
}

@Suite("Grid presentation")
struct GridPresentationTests {
    @Test func modeSwitchesToListAtAccessibilitySizesAndWhenTooNarrow() {
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 5, availableWidth: 402, periodColumnWidth: 44) == .grid)
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 7, availableWidth: 375, periodColumnWidth: 44) == .grid)
        #expect(GridMode.choose(isAccessibilitySize: true, columnCount: 5, availableWidth: 440, periodColumnWidth: 44) == .list)
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 7, availableWidth: 300, periodColumnWidth: 44) == .list)
        // Day columns are at least 44 pt wide (tap target): a 7-day week fits the grid on 375/393 pt phones, not below.
        #expect(GridMode.minimumColumnWidth >= 44)
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 7, availableWidth: 359, periodColumnWidth: 46) == .grid)
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 7, availableWidth: 340, periodColumnWidth: 46) == .list)
        #expect(GridMode.choose(isAccessibilitySize: false, columnCount: 7, availableWidth: 360, periodColumnWidth: 60) == .list)
        #expect(TapTarget.hitArea(drawn: 22) == (44, 11))
        #expect(TapTarget.hitArea(drawn: 80) == (80, 0))
    }

    @Test func listSectionsKeepOrderSpansAndInnerBreaksOnly() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let layout = GridLayout.week(containing: today, resolver: resolver)
        let sections = GridPresentation.listSections(layout)
        #expect(sections.count == 5)
        for section in sections {
            if case .breakRow? = section.items.first { Issue.record("leading break in \(section.column.date)") }
            if case .breakRow? = section.items.last { Issue.record("trailing break in \(section.column.date)") }
            let lessonCells = section.items.filter { if case .lesson = $0 { return true } else { return false } }
            #expect(lessonCells.count == layout.cells.filter { $0.column == section.column.index }.count)
        }
        let tuesday = sections[1].items.compactMap { item -> String? in
            if case let .lesson(cell, _) = item { return cell.entry.subject.shortName }
            return nil
        }
        #expect(tuesday == resolver.day(today).entries.map(\.subject.shortName))
        // Free slots of the layout all appear in the list.
        let free = sections.flatMap(\.items).filter { if case .free = $0 { return true } else { return false } }
        #expect(free.count == layout.emptySlots.count)
    }

    @Test func cellTextsAndVoiceOver() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let layout = GridLayout.week(containing: today, resolver: resolver)
        let cell = try #require(layout.cells.first { $0.column == 1 })
        #expect(GridPresentation.cellTitle(cell.entry.subject) == cell.entry.subject.shortName)
        #expect(GridPresentation.emoji(cell.entry.subject) != nil)
        let label = GridPresentation.cellAccessibilityLabel(cell, reasons: [], visibility: resolver.timetable.fieldVisibility,
                                                            renderer: renderer)
        #expect(label.hasPrefix(renderer.formatter.date(today, style: .full) + ": \(cell.entry.subject.name), period 1, "))
        let row = layout.rows[try #require(layout.rows.firstIndex { $0.isLessonRow })]
        let free = GridPresentation.freeSlotAccessibilityLabel(column: layout.columns[0], row: row, renderer: renderer)
        #expect(free.hasPrefix(renderer.formatter.date(date(2026, 10, 12), style: .full) + ", period 1, "))
        #expect(free.hasSuffix("free"))
        #expect(GridPresentation.rowLabel(row) == "1")
    }

    @Test func nowMarkerOnlyInTodaysColumnInsideTheRange() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let layout = TimeBlockLayout.week(containing: today, resolver: resolver)
        let marker = try #require(GridPresentation.nowMarker(layout, today: today, minuteOfDay: 10 * 60 + 20))
        #expect(marker.column == 1)
        #expect(marker.position > 0 && marker.position < 1)
        #expect(GridPresentation.nowMarker(layout, today: today, minuteOfDay: 2 * 60) == nil)
        #expect(GridPresentation.nowMarker(layout, today: date(2026, 10, 17), minuteOfDay: 600) == nil)
    }
}

@Suite("Quick add")
struct QuickAddTests {
    @Test func emptySlotBecomesALessonInThatCycleWeekOnly() throws {
        let scenario = SampleScenarios.secondary()
        var database = scenario.database
        let resolver = try makeResolver(database)
        let layout = GridLayout.week(containing: today, resolver: resolver)
        let slot = try #require(layout.emptySlots.first)
        let target = try #require(QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row,
                                                      timetable: resolver.timetable))
        #expect(target.cycleWeek == 2)
        #expect(target.periodID != nil)
        let subject = try #require(QuickAddSubjects.list(database, timetableID: resolver.timetable.id,
                                                         locale: Locale(identifier: "sk_SK")).first)
        var clock = HybridLogicalClock(node: 7)
        let lesson = target.makeLesson(id: Lesson.ID(UUID()), subjectID: subject.id)
        #expect(lesson.occurrence == LessonOccurrenceRule(day: .weekday(target.date.weekday), cycleWeeks: [2]))
        database = try DatabaseMutation.upsert(lesson).apply(to: database, clock: &clock, now: SampleScenarios.referenceNow)
        #expect(database.validate().filter { $0.severity == .error }.isEmpty)
        let updated = try makeResolver(database)
        let after = GridLayout.week(containing: today, resolver: updated)
        #expect(!after.emptySlots.contains(slot))
        #expect(after.cells.contains { $0.column == slot.column && $0.row == slot.row && $0.entry.subject.id == subject.id })
        // The other cycle week keeps its slot free.
        let nextWeek = GridLayout.week(containing: today.adding(days: 7), resolver: updated)
        #expect(!nextWeek.cells.contains { $0.entry.source == .lesson(lesson.id) })
    }

    @Test func noRotationGivesEveryWeekAndFreeFormUsesTimes() throws {
        let elementary = SampleScenarios.elementary()
        let resolver = try makeResolver(elementary)
        let layout = GridLayout.week(containing: today, resolver: resolver)
        let slot = try #require(layout.emptySlots.first)
        let target = try #require(QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row,
                                                      timetable: resolver.timetable))
        #expect(target.occurrence.cycleWeeks == nil)
        if case .period(_, let span) = target.slot { #expect(span == 1) } else { Issue.record("expected a period slot") }

        let freeForm = QuickAddTarget(timetableID: resolver.timetable.id, date: today, dayKey: .weekday(.tuesday),
                                      cycleWeek: nil, periodID: nil, lessonNumber: 1, start: time(9), end: time(10, 30))
        #expect(freeForm.slot == .time(start: time(9), end: time(10, 30)))
        // A break row is not a target.
        if let breakRow = layout.rows.first(where: { !$0.isLessonRow }) {
            #expect(QuickAddTarget.make(layout: layout, column: 0, row: breakRow.index, timetable: resolver.timetable) == nil)
        }
    }
}

@Suite("Lesson detail and field lines")
struct LessonDetailTests {
    @Test func modifiedLessonShowsUsualValues() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let thursday = scenario.overrideDate
        let math = try #require(resolver.day(thursday).entries.first { $0.subject.shortName == "MAT" && $0.status == .modified })
        let detail = try #require(LessonDetailModel.make(occurrenceID: math.id, date: thursday, resolver: resolver,
                                                         database: scenario.database, formatter: renderer.formatter))
        #expect(detail.lessonID != nil)
        let room = try #require(detail.changes.first { $0.reason == .roomChanged })
        #expect(room.usualValue == "214")
        #expect(detail.fields.first == .room("Aula"))
        #expect(detail.changes.contains { $0.reason == .timeChanged && $0.usualValue != nil })
        #expect(LessonDetailModel.make(occurrenceID: OccurrenceID(rawValue: "lesson:nope"), date: thursday,
                                       resolver: resolver, database: scenario.database, formatter: renderer.formatter) == nil)
    }

    @Test func oneOffLessonHasNoRecurringLesson() throws {
        let scenario = SampleScenarios.secondary()
        let resolver = try makeResolver(scenario.database)
        let added = try #require(resolver.day(scenario.overrideDate).entries.first { $0.status == .added })
        let detail = try #require(LessonDetailModel.make(occurrenceID: added.id, date: scenario.overrideDate,
                                                         resolver: resolver, database: scenario.database,
                                                         formatter: renderer.formatter))
        #expect(detail.lessonID == nil && detail.cycleWeeks.isEmpty)
    }

    @Test func fieldLinesFollowTheFieldRule() {
        let subject = SubjectSummary(id: Subject.ID(UUID()), name: "Fyzika", color: PalettePack.classic.colors[0].value)
        let lesson = ResolvedLesson(id: OccurrenceID(rawValue: "x"), source: .lesson(Lesson.ID(UUID())),
                                    timetableID: Timetable.ID(UUID()), date: today, subject: subject, startTime: time(8),
                                    endTime: time(8, 45), start: Date(), end: Date(), room: "Lab", building: " ",
                                    teacher: "RNDr. Tóth", lessonType: .lab, notes: nil, bringList: ["kalkulačka", ""])
        let all = LessonFieldLines.make(lesson: lesson, visibility: .all)
        #expect(all == [.room("Lab"), .teacher("RNDr. Tóth"), .lessonType(.lab), .bring(["kalkulačka"])])
        #expect(LessonFieldLines.make(lesson: lesson, visibility: FieldVisibility([.room])) == [.room("Lab")])
        #expect(LessonFieldLines.make(lesson: lesson, visibility: .all, only: [.teacher, .notes]) == [.teacher("RNDr. Tóth")])
        #expect(LessonFieldLine.lessonType(.lab).text(renderer: renderer) == "Lab")
        #expect(LessonFieldLine.bring(["a", "b"]).text(renderer: renderer) == "a and b")
        #expect(LessonFieldLines.make(lesson: lesson, visibility: FieldVisibility()).isEmpty)
    }

    @Test func editorContextIsAValue() {
        let id = Timetable.ID(UUID())
        let context = EditorContext(timetableID: id, target: .newSubject)
        #expect(context == EditorContext(timetableID: id, target: .newSubject))
        #expect(EditorContext.RouteID.dayChange == "editor.day-change")
    }
}
