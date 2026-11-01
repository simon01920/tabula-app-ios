import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

/// Phase 8 E2: range resolution, pages, file names and the catalog-backed export labels.
@Suite("ExportPlan")
struct ExportPlanTests {
    private let context = CalendarContext(timeZone: TimeZone(identifier: "Europe/Bratislava")!, firstWeekday: .monday)
    private let renderer = LocalizedTextRenderer(
        formatter: TimetableFormatter(locale: Locale(identifier: "en_US"), hourCycle: .h24,
                                      timeZone: TimeZone(identifier: "Europe/Bratislava")!),
        lookup: EnglishCatalog.lookup)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }

    private func term(_ name: String, _ start: LocalDate, _ end: LocalDate) -> Term {
        Term(id: Term.ID(UUID()), meta: EntityMeta(createdAt: .zero, updatedAt: .zero), timetableID: Timetable.ID(UUID()),
             name: name, range: LocalDateRange(start: start, end: end))
    }

    // 2026-10-14 is a Wednesday.
    private var today: LocalDate { date(2026, 10, 14) }
    private var none: LocalDateRange { LocalDateRange(day: today) }

    @Test func thisWeekIsMondayToSunday() {
        let range = ExportPlan.range(.thisWeek, custom: none, today: today, context: context, terms: [])
        #expect(range.start == date(2026, 10, 12) && range.end == date(2026, 10, 18))
    }

    @Test func thisWeekHonoursFirstWeekday() {
        let sunday = CalendarContext(timeZone: context.timeZone, firstWeekday: .sunday)
        let range = ExportPlan.range(.thisWeek, custom: none, today: today, context: sunday, terms: [])
        #expect(range.start == date(2026, 10, 11) && range.end == date(2026, 10, 17))
    }

    @Test func termContainingTodayWins() {
        let terms = [term("Old", date(2026, 2, 1), date(2026, 6, 30)), term("Winter", date(2026, 9, 1), date(2027, 1, 31))]
        let range = ExportPlan.range(.term, custom: none, today: today, context: context, terms: terms)
        #expect(range == LocalDateRange(start: date(2026, 9, 1), end: date(2027, 1, 31)))
        #expect(ExportPlan.currentTerm(terms, today: today)?.name == "Winter")
    }

    @Test func noTermMeansNextFourWeeks() {
        let range = ExportPlan.range(.term, custom: none, today: today, context: context,
                                     terms: [term("Old", date(2026, 2, 1), date(2026, 6, 30))])
        #expect(range.start == today && range.dayCount == 28)
        #expect(ExportPlan.currentTerm([], today: today) == nil)
    }

    @Test func customIsCappedAndNeverEmptyAtTheEnd() {
        let backwards = LocalDateRange(start: date(2026, 10, 20), end: date(2026, 10, 10))
        let fixed = ExportPlan.range(.custom, custom: backwards, today: today, context: context, terms: [])
        #expect(fixed.dayCount == 1 && fixed.start == date(2026, 10, 20))
        let huge = LocalDateRange(start: date(2026, 1, 1), end: date(2030, 1, 1))
        #expect(ExportPlan.range(.custom, custom: huge, today: today, context: context, terms: []).dayCount == 366)
    }

    @Test func pagesPerWeekAndPerEnabledDay() {
        let week = LocalDateRange(start: date(2026, 10, 14), end: date(2026, 10, 27))   // Wed to Tue: 3 weeks touched
        let weeks = ExportPlan.pages(view: .grid, range: week, context: context, enabledDays: Weekday.workweek)
        #expect(weeks == [date(2026, 10, 12), date(2026, 10, 19), date(2026, 10, 26)])
        let days = ExportPlan.pages(view: .day, range: week, context: context, enabledDays: Weekday.workweek)
        #expect(days.count == 10 && days.allSatisfy { Weekday.workweek.contains($0.weekday) })
        #expect(ExportPlan.pages(view: .week, range: LocalDateRange(start: today, end: date(2026, 10, 1)), context: context,
                                 enabledDays: []).isEmpty)
    }

    private var fb: String { renderer.string(forKey: "export.file.fallback") }

    @Test func longTermIsCappedLikeCustom() {
        let long = [term("Forever", date(2020, 1, 1), date(2040, 1, 1))]
        let range = ExportPlan.range(.term, custom: none, today: today, context: context, terms: long)
        #expect(range.start == date(2020, 1, 1) && range.dayCount == ExportPlan.maximumDays)
    }

    /// The date picker value (start of day in the timetable's zone) maps back to the same calendar day.
    @Test func pickedDateRoundTripsInAnyZone() {
        for id in ["Pacific/Kiritimati", "America/Los_Angeles", "Europe/Bratislava", "Pacific/Pago_Pago"] {
            let zone = CalendarContext(timeZone: TimeZone(identifier: id)!, firstWeekday: .monday)
            #expect(zone.localDate(of: zone.startOfDay(today)) == today, "zone \(id)")
        }
    }

    @Test func fileNamesAreSanitised() {
        #expect(ExportPlan.fileName(timetable: "Timetable 2.B", suffix: "week 42", ext: "pdf", fallback: fb) == "Timetable 2.B – week 42.pdf")
        let evil = ExportPlan.fileName(timetable: "../../a/b:c*?\"<>|\n", suffix: "", ext: "csv", fallback: fb)
        #expect(evil == "a b c.csv")
        #expect(!evil.contains("/") && !evil.contains(".."))
        #expect(ExportPlan.fileName(timetable: "   ", suffix: "", ext: "ics", fallback: fb) == "Timetable.ics")
        #expect(ExportPlan.fileName(timetable: ".hidden", suffix: "", ext: "csv", fallback: fb) == "hidden.csv")
        let long = ExportPlan.fileName(timetable: String(repeating: "x", count: 300), suffix: "", ext: "png", fallback: fb)
        #expect(long.count == 84)
    }

    @Test func fileSuffixesComeFromTheCatalog() {
        let week = ExportPlan.range(.thisWeek, custom: none, today: today, context: context, terms: [])
        #expect(ExportPlan.fileSuffix(.thisWeek, range: week, termName: nil, renderer: renderer) == "week 42")
        #expect(ExportPlan.fileSuffix(.term, range: week, termName: "Winter", renderer: renderer) == "Winter")
        #expect(ExportPlan.fileSuffix(.term, range: week, termName: nil, renderer: renderer) == "next 4 weeks")
        #expect(ExportPlan.fileSuffix(.custom, range: week, termName: nil, renderer: renderer)
                == "2026-10-12 to 2026-10-18")
    }

    @Test func labelsComeFromTheCatalog() {
        let labels = ExportPlan.labels(renderer: renderer)
        #expect([labels.date, labels.start, labels.end, labels.subject, labels.room, labels.teacher, labels.change]
                == ["Date", "Start", "End", "Subject", "Room", "Teacher", "Change"])
        func row(_ status: ResolvedLesson.Status, _ reasons: [ModificationReason]) -> ExportRow {
            ExportRow(occurrenceID: OccurrenceID(rawValue: "x"), sourceID: UUID(), date: today,
                      start: LocalTime(hour: 8, minute: 0)!, end: LocalTime(hour: 8, minute: 45)!, subject: "Math",
                      status: status, reasons: reasons)
        }
        #expect(labels.changeText(row(.scheduled, [])) == "")
        #expect(labels.changeText(row(.cancelled, [])) == "Canceled")
        #expect(labels.changeText(row(.added, [])) == "Extra lesson")
        #expect(labels.changeText(row(.modified, [.roomChanged])) == "Room changed")
        #expect(labels.changeText(row(.modified, [])) == "Changed")
        #expect(labels.changeText(row(.modified, [.timeChanged, .roomChanged])) == "Time changed and Room changed")
    }

    @Test func everyExportKeyIsInTheCatalog() {
        let keys = ExportKind.allCases.map(\.nameKey) + ExportView.allCases.map(\.nameKey)
            + ExportRangeChoice.allCases.map(\.nameKey)
            + ["export.file.fallback", "export.menu", "export.title", "export.action", "export.range.span", "export.file.week",
               "export.pro.footer", "export.image.footer", "export.range.term.footer", "export.failed.title"]
        for key in keys { #expect(!renderer.isMissing(key), "missing catalog key \(key)") }
    }
}
