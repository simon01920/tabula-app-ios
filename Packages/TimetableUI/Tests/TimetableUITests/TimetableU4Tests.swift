import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4U stage U4 (Timetable): the badge-priority rule, the rotation phrases (never "Week " + a word), the now-line
// rules, the quick-add header, the subtitle, the Add Lesson slot and the contrast of the local marker colours.

private let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: SampleScenarios.timeZone),
    lookup: EnglishCatalog.lookup)
private let today = SampleScenarios.today   // Tue 2026-10-13, ISO week 42
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func makeResolver(_ database: TabulaDatabase) throws -> ScheduleResolver {
    try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id, context: context))
}
private func lesson(status: ResolvedLesson.Status = .scheduled, on day: LocalDate = today,
                    from start: LocalTime = time(10), to end: LocalTime = time(10, 45)) -> ResolvedLesson {
    let subject = SubjectSummary(id: Subject.ID(UUID()), name: "Matematika", shortName: "MAT",
                                 color: PalettePack.classic.colors[0].value)
    return ResolvedLesson(id: OccurrenceID(rawValue: "x"), source: .lesson(Lesson.ID(UUID())), timetableID: Timetable.ID(UUID()),
                          date: day, subject: subject, startTime: start, endTime: end, start: Date(), end: Date(),
                          periodNumber: 3, room: "214", building: nil, teacher: nil, lessonType: nil, notes: nil,
                          bringList: [], status: status)
}

@Suite("U4 cell badge")
struct CellBadgeTests {
    @Test func priorityIsCancelledThenExamThenTasksThenChange() {
        let both = LessonBadges(openTasks: 2, hasExam: true)
        let tasks = LessonBadges(openTasks: 2, hasExam: false)
        #expect(LessonCellBadge.make(status: .cancelled, reasons: [], badges: both) == .cancelled)
        #expect(LessonCellBadge.make(status: .modified, reasons: [.roomChanged], badges: both) == .exam)
        #expect(LessonCellBadge.make(status: .modified, reasons: [.roomChanged], badges: tasks) == .tasks(2))
        #expect(LessonCellBadge.make(status: .modified, reasons: [.roomChanged], badges: nil)
                == .change(symbolName: LessonChangeSymbol.roomChanged))
        #expect(LessonCellBadge.make(status: .added, reasons: [], badges: LessonBadges(openTasks: 0, hasExam: false))
                == .change(symbolName: LessonChangeSymbol.added))
        #expect(LessonCellBadge.make(status: .scheduled, reasons: [], badges: nil) == nil)
        #expect(LessonCellBadge.cancelled.symbolName == "xmark.circle.fill")
        #expect(LessonCellBadge.exam.isChange == false && LessonCellBadge.cancelled.isChange)
    }

    @Test func distinctChangeSymbolsWithMostImportantReasonFirst() {
        let symbols = [LessonChangeSymbol.timeChanged, LessonChangeSymbol.roomChanged, LessonChangeSymbol.substitute,
                       LessonChangeSymbol.added, LessonChangeSymbol.cancelled]
        #expect(Set(symbols).count == symbols.count)
        #expect(!symbols.contains("arrow.triangle.2.circlepath"))   // means sync / repeat elsewhere
        #expect(LessonChangeSymbol.symbol(forReasons: [.teacherChanged, .timeChanged]) == "clock.badge.exclamationmark")
        #expect(LessonChangeSymbol.symbol(forReasons: [.teacherChanged]) == "person.2.badge.gearshape")
        #expect(LessonChangeSymbol.symbol(forReasons: [.buildingChanged]) == "arrow.right.square")
        #expect(LessonChangeSymbol.symbol(forReasons: []) == LessonChangeSymbol.detailsChanged)
        #expect(Set(LessonChangeSymbol.priority) == Set(ModificationReason.allCases))
        // The same symbol reaches every surface through the badge model (grid, detail, Today, widgets).
        #expect(LessonStatusBadgeModel.make(status: .modified, reasons: [.timeChanged])?.symbolName
                == LessonChangeSymbol.timeChanged)
        #expect(LessonStatusBadgeModel.make(status: .cancelled, reasons: [])?.symbolName == LessonChangeSymbol.cancelled)
    }

    @Test func roomUsesTheMapPin() {
        #expect(LessonFieldLine.room("214").symbolName == "mappin.and.ellipse")
    }
}

@Suite("U4 rotation phrases")
struct RotationPhraseTests {
    private let strict = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0)))

    @Test func parityWeeksUseFullPhrasesAndHonourTheOffset() {
        #expect(CycleLabel.week(1, scheme: strict, userLabel: nil) == .parityWeek(isOdd: true))
        #expect(CycleLabel.week(2, scheme: strict, userLabel: nil) == .parityWeek(isOdd: false))
        let swapped = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 1)))
        #expect(CycleLabel.week(1, scheme: swapped, userLabel: nil) == .parityWeek(isOdd: false))
        let hostile = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: Int.min)))
        #expect(CycleLabel.week(1, scheme: hostile, userLabel: nil) == .parityWeek(isOdd: true))   // Int.min is even
        // A continuous count can disagree with the printed week number: it keeps A/B.
        let continuous = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .continuous, offset: 0)))
        #expect(CycleLabel.week(2, scheme: continuous, userLabel: nil) == .namedWeek("B"))
        let reference = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: today, cycleWeek: 1)))
        #expect(CycleLabel.week(1, scheme: reference, userLabel: nil) == .namedWeek("A"))
        #expect(CycleLabel.parityWeek(isOdd: true).text(renderer: renderer) == "Odd week")
        #expect(CycleLabel.parityWeek(isOdd: false).text(renderer: renderer) == "Even week")
    }

    @Test func wordLabelsAreNeverPrefixedWithWeek() {
        for word in ["Párny", "Nepárny", "Odd", "Blue week", "Lichý"] {
            let label = CycleLabel.week(1, scheme: strict, userLabel: word)
            #expect(label == .customWeek(word))
            let text = label?.text(renderer: renderer) ?? ""
            #expect(text == word)
            #expect(!text.hasPrefix("Week "))
        }
        for token in ["A", "B", "II", "12"] {
            #expect(CycleLabel.week(1, scheme: strict, userLabel: token)?.text(renderer: renderer) == "Week \(token)")
        }
        #expect(CycleLabel.day(.cycleDay(1), userLabel: "Monday-ish") == .customDay("Monday-ish"))
        #expect(CycleLabel.day(.cycleDay(1), userLabel: "B")?.text(renderer: renderer) == "Day B")
        #expect(CycleLabel.allCatalogKeys.allSatisfy { EnglishCatalog.values[$0] != nil })
    }

    @Test func universitySampleShowsOddAndEvenWeeks() throws {
        let resolver = try makeResolver(SampleScenarios.university())
        let thisWeek = WeekStripModel.make(selection: TimetableSelection(weekStart: date(2026, 10, 12), selectedDate: today),
                                           today: today, resolver: resolver)
        #expect(thisWeek.cycleWeek?.text(renderer: renderer) == "Even week")   // ISO week 42
        let nextWeek = WeekStripModel.make(selection: TimetableSelection(weekStart: date(2026, 10, 19),
                                                                          selectedDate: date(2026, 10, 19)),
                                           today: today, resolver: resolver)
        #expect(nextWeek.cycleWeek?.text(renderer: renderer) == "Odd week")
    }
}

@Suite("U4 now line")
struct NowLineTests {
    @Test func currentLessonIsStartInclusiveEndExclusiveAndNeverCancelled() {
        #expect(NowLinePresentation.isCurrent(lesson(), today: today, minuteOfDay: 600))
        #expect(NowLinePresentation.isCurrent(lesson(), today: today, minuteOfDay: 644))
        #expect(!NowLinePresentation.isCurrent(lesson(), today: today, minuteOfDay: 645))
        #expect(!NowLinePresentation.isCurrent(lesson(), today: today, minuteOfDay: 599))
        #expect(!NowLinePresentation.isCurrent(lesson(status: .cancelled), today: today, minuteOfDay: 620))
        #expect(!NowLinePresentation.isCurrent(lesson(on: date(2026, 10, 14)), today: today, minuteOfDay: 620))
    }

    @Test func gutterHourLabelsNearTheNowLabelAreHidden() {
        let marks = [480, 540, 600, 660]
        #expect(NowLinePresentation.hiddenHourMarks(marks, nowMinute: 620, clearanceMinutes: 12) == [])
        #expect(NowLinePresentation.hiddenHourMarks(marks, nowMinute: 605, clearanceMinutes: 12) == [600])
        #expect(NowLinePresentation.hiddenHourMarks(marks, nowMinute: 652, clearanceMinutes: 12) == [660])
        #expect(NowLinePresentation.hiddenHourMarks(marks, nowMinute: nil, clearanceMinutes: 12) == [])
        #expect(NowLinePresentation.clearanceMinutes(labelHeight: 16, hourHeight: 93.6) == 11)
        #expect(NowLinePresentation.clearanceMinutes(labelHeight: 16, hourHeight: 0) == 0)
    }

    @Test func markerOnlyOnTodaysColumnInsideTheRange() throws {
        let resolver = try makeResolver(SampleScenarios.secondary().database)
        let layout = TimeBlockLayout.week(containing: date(2026, 10, 12), resolver: resolver)
        #expect(GridPresentation.nowMarker(layout, today: today, minuteOfDay: 620)?.column == 1)
        #expect(GridPresentation.nowMarker(layout, today: today, minuteOfDay: 2) == nil)
        #expect(GridPresentation.nowMarker(layout, today: date(2026, 10, 24), minuteOfDay: 620) == nil)
    }
}

@Suite("U4 quick add and subtitle")
struct QuickAddScopeTests {
    @Test func headerNamesTheWeeklyScope() throws {
        let database = SampleScenarios.secondary().database
        let resolver = try makeResolver(database)
        let timetable = database.timetables[0]
        let layout = GridLayout.week(containing: date(2026, 10, 12), resolver: resolver)
        let slot = try #require(layout.emptySlots.first { layout.rows[$0.row].lessonNumber == 7 && $0.column == 0 })
        let target = try #require(QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row, timetable: timetable))
        let week = CycleLabel.week(target.cycleWeek, scheme: timetable.rotation,
                                   userLabel: target.cycleWeek.flatMap(resolver.rotation.label(forCycleWeek:)))
        let range = renderer.formatter.timeRange(target.start, target.end)
        #expect(QuickAddScope.text(target, cycleWeek: week, userDayLabel: nil, renderer: renderer)
                == "Every Monday · Week B · Period 7 (\(range))")
        #expect(QuickAddScope.text(target, cycleWeek: nil, userDayLabel: nil, renderer: renderer)
                == "Every Monday · Period 7 (\(range))")
        var freeForm = target
        freeForm.periodID = nil
        #expect(QuickAddScope.slot(freeForm, renderer: renderer) == range)
        #expect(QuickAddScope.every(.cycleDay(3), userDayLabel: nil, renderer: renderer) == "Every Day 3")
        #expect(QuickAddScope.allCatalogKeys.allSatisfy { EnglishCatalog.values[$0] != nil })
    }

    @Test func subtitleJoinsRangeAndRotation() {
        #expect(TimetableSubtitle.text(first: "12 Oct", last: "16 Oct", cycle: .parityWeek(isOdd: false), renderer: renderer)
                == "12 Oct – 16 Oct · Even week")
        #expect(TimetableSubtitle.text(first: "12 Oct", last: "16 Oct", cycle: nil, renderer: renderer) == "12 Oct – 16 Oct")
    }

    @Test func addLessonPrefersAFreePeriodOfTheShownDay() throws {
        let database = SampleScenarios.secondary().database
        let resolver = try makeResolver(database)
        let timetable = database.timetables[0]
        let layout = GridLayout.week(containing: date(2026, 10, 12), resolver: resolver)
        // Friday has free periods 6–8 in the sample week: the first one is picked.
        let friday = try #require(AddLessonSlot.pick(layout: layout, preferredDate: date(2026, 10, 16), timetable: timetable))
        #expect(friday.date == date(2026, 10, 16))
        let fridayColumn = try #require(layout.columns.first { $0.date == date(2026, 10, 16) })
        let firstFree = layout.emptySlots.filter { $0.column == fridayColumn.index }.map(\.row).min()
        #expect(firstFree.map { layout.rows[$0].start } == friday.start)
        // A date outside the week falls back to the week's first school day with a free period.
        #expect(AddLessonSlot.pick(layout: layout, preferredDate: date(2027, 1, 1), timetable: timetable) != nil)
    }
}

@Suite("U4 marker colour contrast")
struct MarkerColourContrastTests {
    @Test func everyTokenPairMeetsItsMinimum() {
        typealias C = TimetableMarkerColors
        // Text pairs ≥ 4.5:1.
        #expect(C.onInkLight.contrastRatio(with: C.inkLight) >= 4.5)
        #expect(C.onInkLight.contrastRatio(with: C.inkIncreasedContrast) >= 7)
        #expect(C.onInkDark.contrastRatio(with: C.inkDark) >= 4.5)
        #expect(C.onCorrectionLight.contrastRatio(with: C.correctionLight) >= 4.5)
        #expect(C.onCorrectionDark.contrastRatio(with: C.correctionDark) >= 4.5)
        #expect(C.onHighlighter.contrastRatio(with: C.highlighter) >= 12)
        #expect(C.changeTextLight.contrastRatio(with: C.lightCell) >= 4.5)
        #expect(C.changeTextDark.contrastRatio(with: C.darkCell) >= 4.5)
        // The now line (non-text, ≥ 3:1) against both page backgrounds.
        #expect(C.correctionLight.contrastRatio(with: .white) >= 3)
        #expect(C.correctionDark.contrastRatio(with: .black) >= 3)
        // The highlighter outline's black edge vs the highlighter band (visible on any subject colour).
        #expect(ColorValue.black.contrastRatio(with: C.highlighter) >= 3)
    }
}
