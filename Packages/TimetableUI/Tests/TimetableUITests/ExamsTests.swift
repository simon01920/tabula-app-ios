import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day)! }
private func t(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private let zone = TimeZone(identifier: "Europe/Bratislava")!
private let monday = CalendarContext(timeZone: zone, firstWeekday: .monday)
private let sunday = CalendarContext(timeZone: zone, firstWeekday: .sunday)
// 2026-10-14 is a Wednesday.
private let today = d(2026, 10, 14)

private func exam(_ title: String, _ date: LocalDate, start: LocalTime? = nil, end: LocalTime? = nil,
                  completed: Bool = false, timetable: Timetable.ID? = nil) -> Exam {
    Exam(id: Exam.ID(UUID()), meta: EditorEntities.placeholderMeta, timetableID: timetable, title: title, date: date,
         start: start, end: end, completedAt: completed ? Date(timeIntervalSince1970: 0) : nil)
}

private func database(_ exams: [Exam], breaks: [CalendarBreak] = [], profile: UserProfile = .secondary) -> TabulaDatabase {
    var db = DatabaseMutation.emptyBase
    db.exams = exams
    db.breaks = breaks
    db.settings.profile = profile
    return db
}

private func examPeriod(_ name: String, _ start: LocalDate, _ end: LocalDate, timetable: Timetable.ID? = nil) -> CalendarBreak {
    CalendarBreak(id: CalendarBreak.ID(UUID()), meta: EditorEntities.placeholderMeta, timetableID: timetable, name: name,
                  range: LocalDateRange(start: start, end: end), kind: .examPeriod)
}

@Suite("Exam list model")
struct ExamListModelTests {
    @Test func emptyDatabaseIsEmpty() {
        let model = ExamListModel.make(database: database([]), today: today, context: monday)
        #expect(model.isEmpty)
        #expect(!model.hasUpcoming)
    }

    @Test func nextExamIsTheEarliestUpcomingAndNotRepeated() {
        let later = exam("Later", d(2026, 10, 30))
        let soon = exam("Soon", d(2026, 10, 15), start: t(9))
        let todayLate = exam("TodayLate", today, start: t(14))
        let todayEarly = exam("TodayEarly", today, start: t(8))
        let model = ExamListModel.make(database: database([later, soon, todayLate, todayEarly]), today: today, context: monday)
        #expect(model.next?.exam.title == "TodayEarly")
        let listed = model.weeks.flatMap(\.rows).map(\.exam.title)
        #expect(listed == ["TodayLate", "Soon", "Later"])
    }

    @Test func pastAndCompletedGoToHistoryNewestFirst() {
        let past = exam("Past", d(2026, 10, 1))
        let doneFuture = exam("DoneFuture", d(2026, 10, 20), completed: true)
        let yesterday = exam("Yesterday", d(2026, 10, 13))
        let open = exam("Open", d(2026, 10, 16))
        let model = ExamListModel.make(database: database([past, doneFuture, yesterday, open]), today: today, context: monday)
        #expect(model.history.map(\.exam.title) == ["DoneFuture", "Yesterday", "Past"])
        #expect(model.history.allSatisfy { $0.urgency == .past || $0.exam.isCompleted })
        #expect(model.next?.exam.title == "Open")
    }

    @Test func deletedExamsAreIgnored() {
        var gone = exam("Gone", d(2026, 10, 15))
        gone.meta.isDeleted = true
        let model = ExamListModel.make(database: database([gone]), today: today, context: monday)
        #expect(model.isEmpty)
    }

    @Test func weeksHonourFirstWeekday() {
        // Sunday 2026-10-18: with Monday-first it belongs to the current week (Mon 12 - Sun 18), with Sunday-first to the next.
        let first = exam("A", today)
        let sundayExam = exam("B", d(2026, 10, 18))
        let m = ExamListModel.make(database: database([first, sundayExam]), today: today, context: monday)
        #expect(m.weeks.count == 1)
        #expect(m.weeks[0].label == .thisWeek)
        let s = ExamListModel.make(database: database([first, sundayExam]), today: today, context: sunday)
        #expect(s.weeks.count == 1)
        #expect(s.weeks[0].label == .nextWeek)
    }

    @Test func weekLabels() {
        let a = exam("A", today)
        let b = exam("B", d(2026, 10, 21))
        let c = exam("C", d(2026, 11, 4))
        let model = ExamListModel.make(database: database([a, b, c]), today: today, context: monday)
        #expect(model.weeks.map(\.label) == [.nextWeek, .weekOf(d(2026, 11, 2))])
    }

    @Test func examPeriodGroupsExamsAndExcludesFeatured() {
        let period = examPeriod("Winter exams", d(2026, 11, 2), d(2026, 11, 13))
        let before = exam("Before", d(2026, 10, 16))
        let inside1 = exam("Inside1", d(2026, 11, 3))
        let inside2 = exam("Inside2", d(2026, 11, 10))
        let model = ExamListModel.make(database: database([before, inside1, inside2], breaks: [period]), today: today, context: monday)
        #expect(model.next?.exam.title == "Before")
        #expect(model.periods.count == 1)
        #expect(model.periods[0].name == "Winter exams")
        #expect(model.periods[0].examCount == 2)
        #expect(model.periods[0].rows.map(\.exam.title) == ["Inside1", "Inside2"])
        #expect(model.weeks.isEmpty)
        #expect(model.next?.periodName == nil)
    }

    @Test func featuredExamInsideAPeriodNamesIt() {
        let period = examPeriod("Finals", d(2026, 10, 14), d(2026, 10, 30))
        let model = ExamListModel.make(database: database([exam("A", d(2026, 10, 15)), exam("B", d(2026, 10, 20))], breaks: [period]),
                                       today: today, context: monday)
        #expect(model.next?.periodName == "Finals")
        #expect(model.periods[0].isCurrent)
        #expect(model.periods[0].examCount == 2)
        #expect(model.periods[0].rows.count == 1)
    }

    @Test func periodOfAnotherTimetableDoesNotClaimTheExam() {
        let other = Timetable.ID(UUID())
        let mine = Timetable.ID(UUID())
        let period = examPeriod("Other", d(2026, 11, 2), d(2026, 11, 13), timetable: other)
        let e = exam("E", d(2026, 11, 3), timetable: mine)
        let model = ExamListModel.make(database: database([exam("N", today), e], breaks: [period]), today: today, context: monday)
        #expect(model.periods[0].examCount == 0)
        #expect(model.weeks.flatMap(\.rows).map(\.exam.title) == ["E"])
    }

    @Test func pastExamPeriodIsNotShown() {
        let period = examPeriod("Old", d(2026, 9, 1), d(2026, 9, 12))
        let model = ExamListModel.make(database: database([exam("N", today)], breaks: [period]), today: today, context: monday)
        #expect(model.periods.isEmpty)
    }

    @Test func universityWithoutBreaksDerivesAPeriod() {
        let model = ExamListModel.make(database: database([exam("A", d(2026, 10, 20)), exam("B", d(2026, 11, 3)), exam("C", d(2026, 11, 5))],
                                                          profile: .university), today: today, context: monday)
        #expect(model.periods.count == 1)
        #expect(model.periods[0].isDerived)
        #expect(model.periods[0].range == LocalDateRange(start: d(2026, 10, 20), end: d(2026, 11, 5)))
        #expect(model.periods[0].rows.count == 2)
        let secondary = ExamListModel.make(database: database([exam("A", d(2026, 10, 20)), exam("B", d(2026, 11, 3))]),
                                           today: today, context: monday)
        #expect(secondary.periods.isEmpty)
    }

    @Test func urgencyEscalates() {
        #expect(ExamUrgency(daysUntil: 0) == .today)
        #expect(ExamUrgency(daysUntil: 1) == .tomorrow)
        #expect(ExamUrgency(daysUntil: 3) == .soon)
        #expect(ExamUrgency(daysUntil: 7) == .thisWeek)
        #expect(ExamUrgency(daysUntil: 8) == .later)
        #expect(ExamUrgency(daysUntil: -1) == .past)
        #expect(ExamWhen(daysUntil: 5) == .inDays(5))
        #expect(ExamWhen(daysUntil: -3) == .daysAgo(3))
        #expect(ExamWhen(daysUntil: -1) == .yesterday)
    }
}

@Suite("Exam facts and texts")
struct ExamTextTests {
    private let renderer = LocalizedTextRenderer(
        formatter: TimetableFormatter(locale: Locale(identifier: "en_US"), hourCycle: .h24, timeZone: zone),
        lookup: EnglishCatalog.lookup)

    @Test func hiddenFieldsAreAbsentAndEmptyOnesToo() {
        var e = exam("Test", today)
        e.room = "A214"
        e.building = "  "
        e.notes = "Bring calculator"
        e.topics = ["limits", " ", "series"]
        let all = ExamFacts(exam: e, visibility: .all)
        #expect(all.room == "A214" && all.building == nil && all.notes == "Bring calculator")
        #expect(all.topics == ["limits", "series"])
        let none = ExamFacts(exam: e, visibility: FieldVisibility([]))
        #expect(none.room == nil && none.notes == nil && none.location == nil)
        #expect(all.location == "A214")
    }

    @Test func timeShowsStartOrRangeAndIgnoresLoneEnd() {
        let texts = ExamTexts(renderer: renderer)
        #expect(texts.time(exam("a", today)) == nil)
        #expect(texts.time(exam("b", today, start: t(8))) == "08:00")
        #expect(texts.time(exam("c", today, start: t(8), end: t(9, 30)))?.contains("09:30") == true)
        var loneEnd = exam("d", today)
        loneEnd.end = t(9)
        #expect(texts.time(loneEnd) == nil)
    }

    @Test func whenAndKindTexts() {
        let texts = ExamTexts(renderer: renderer)
        #expect(texts.when(.today) == "Today")
        #expect(texts.when(.inDays(5)) == "in 5 days")
        #expect(texts.kind(.midterm) == "Midterm")
        #expect(texts.kind(ExamKind(rawValue: "viva")) == "viva")
    }

    @Test func accessibilityLabelNamesCountdownAndOmitsAbsentFields() {
        let texts = ExamTexts(renderer: renderer)
        var e = exam("Algebra", d(2026, 10, 15), start: t(9))
        e.room = "B1"
        let row = ExamRow(exam: e, subject: nil, today: today)
        let label = texts.accessibilityLabel(row, facts: ExamFacts(exam: e, visibility: .all))
        #expect(label.contains("Algebra") && label.contains("Tomorrow") && label.contains("Room B1"))
        #expect(!label.contains("Building"))
        #expect(!label.contains("Completed"))
    }

    @Test func topicsPreviewTruncates() {
        let texts = ExamTexts(renderer: renderer)
        #expect(texts.topicsPreview([]) == nil)
        #expect(texts.topicsPreview(["a", "b"]) == "a and b")
        #expect(texts.topicsPreview(["a", "b", "c", "d"])?.hasSuffix("…") == true)
    }
}

@Suite("Exam draft")
struct ExamDraftTests {
    @Test func newDraftNeedsATitleAndDefaultsToNextWeek() {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        #expect(draft.date == d(2026, 10, 21))
        #expect(draft.issues == [.noTitle])
        #expect(!draft.canSave && draft.makeExam() == nil)
        draft.title = "  Chemistry  "
        #expect(draft.makeExam()?.title == "Chemistry")
    }

    @Test func endMustBeAfterStartAndNeedsStart() {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        draft.title = "X"
        draft.setHasEnd(true)
        #expect(!draft.hasEnd)  // no start yet
        draft.setHasStart(true)
        draft.start = t(10)
        draft.setHasEnd(true)
        #expect(draft.end > draft.start)
        draft.end = t(9)
        #expect(draft.issues == [.endNotAfterStart])
        draft.end = t(11)
        let saved = draft.makeExam()
        #expect(saved?.start == t(10) && saved?.end == t(11))
        draft.setHasStart(false)
        let cleared = draft.makeExam()
        #expect(cleared?.start == nil && cleared?.end == nil)
    }

    @Test func blankOptionalsAreAbsentAndEveryFieldIsEditable() {
        var original = exam("Orig", today)
        original.room = "A1"
        original.building = "Main"
        original.notes = "N"
        original.completedAt = Date(timeIntervalSince1970: 5)
        var draft = ExamDraft(exam: original)
        draft.room = ""
        draft.building = ""
        draft.notes = ""
        let hidden = draft.makeExam()!
        // D10 (U2-15): field visibility only shapes summaries, so blank room, building and notes are saved as absent.
        #expect(hidden.room == nil && hidden.building == nil && hidden.notes == nil)
        #expect(hidden.completedAt == Date(timeIntervalSince1970: 5))
        #expect(hidden.id == original.id && hidden.meta == original.meta)
    }

    @Test func topicsAddRemoveMoveAndClean() {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        draft.title = "T"
        for text in ["a", "b", "c", ""] {
            draft.addTopic()
            draft.topics[draft.topics.count - 1].text = text
        }
        draft.moveTopics(from: IndexSet(integer: 0), to: 3)
        #expect(draft.topics.map(\.text) == ["b", "c", "a", ""])
        draft.moveTopics(from: IndexSet(integer: 3), to: 0)
        #expect(draft.topics.map(\.text) == ["", "b", "c", "a"])
        draft.removeTopics(at: IndexSet(integer: 1))
        #expect(draft.makeExam()?.topics == ["c", "a"])
    }

    @Test func dirtyComparisonIgnoresTopicIdsAndCounter() {
        let base = ExamDraft(newOn: today, timetableID: nil)
        var edited = base
        edited.addTopic()
        edited.removeTopics(at: IndexSet(integer: 0))
        #expect(edited == base)
        edited.title = "x"
        #expect(edited != base)
    }

    @Test func customKindIsOfferedAndPreserved() {
        var e = exam("Viva", today)
        e.kind = ExamKind(rawValue: "viva")
        let draft = ExamDraft(exam: e)
        #expect(draft.kindChoices.last?.rawValue == "viva")
        #expect(draft.makeExam()?.kind.rawValue == "viva")
    }

    @Test func overrideIsKept() {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        draft.title = "R"
        draft.reminderOverride = ReminderOverride(isEnabled: false)
        #expect(draft.makeExam()?.reminderOverride?.isEnabled == false)
    }

    @Test func completeExamMutationMarksDone() throws {
        let e = exam("Done soon", today)
        var db = database([e])
        var clock = HybridLogicalClock(node: 0xB2)
        db = try DatabaseMutation.completeExam(e.id, at: Date(timeIntervalSince1970: 100))
            .apply(to: db, clock: &clock, now: Date(timeIntervalSince1970: 100))
        #expect(db.exams[0].isCompleted)
    }
}
