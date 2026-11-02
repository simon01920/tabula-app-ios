import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func apply(_ mutation: DatabaseMutation, to database: TabulaDatabase) throws -> TabulaDatabase {
    var clock = HybridLogicalClock(node: 0x19)
    return try mutation.apply(to: database, clock: &clock, now: now)
}

private func cell(_ text: String, _ row: Int, _ column: Int, span: Int = 1, confidence: Double = 0.95) -> RecognizedCell {
    RecognizedCell(text: text, row: row, column: column, columnSpan: span, confidence: confidence)
}

/// Po: "MAT 2O4" (look-alike), "Bio" (known subject Biológia); Ut: the same "MAT 2O4" again, "SAL" over two periods.
private func review() -> ImportReview {
    let table = RecognizedTable(languages: ["sk"], cells: [
        cell("1\n8:00-8:45", 0, 1), cell("2\n8:55-9:40", 0, 2), cell("3\n9:50-10:35", 0, 3),
        cell("Po", 1, 0), cell("MAT\n2O4", 1, 1, confidence: 0.5), cell("Bio\n105", 1, 2),
        cell("Ut", 2, 0), cell("MAT\n2O4", 2, 1, confidence: 0.5), cell("SAL\n3S1", 2, 2, span: 2),
    ])
    let candidate = TimetableImportParser.parse(table, options: ImportParserOptions(knownSubjects: ["Biológia"]))
    return ImportReview(candidate: candidate, timetableName: "Rozvrh 3.A")
}

@Suite("Import review model")
struct ImportReviewTests {
    @Test func countsAndQuestions() {
        let model = review()
        #expect(model.counts == ImportReviewCounts(lessons: 4, needsReview: 2, questions: 2, subjects: 3, days: 2, periods: 3))
        let questions = model.questions
        #expect(questions.map(\.kind) == [.ocrReading, .abbreviation])
        // Identical cells share one question.
        #expect(questions[0].lessonIDs == [0, 2])
        #expect(questions[0].options == ["204", "2O4"])
        #expect(questions[0].prompt == LocalizedText(key: ImportL10n.questionOCRReading,
                                                     args: [.text(LocalizedText(key: "import.field.room")), .string("204"), .string("2O4")]))
        #expect(questions[1].prompt == LocalizedText(key: ImportL10n.questionAbbreviation, args: [.string("Bio"), .string("Biológia")]))
    }

    @Test func answeringAppliesToEveryListedLessonAndClearsTheFlag() {
        var model = review()
        let question = model.questions[0]
        model.answer(question.id, with: "2O4")
        #expect(model.lessons.filter { [0, 2].contains($0.id) }.allSatisfy { $0.room == "2O4" && !$0.needsReview && $0.reasons.isEmpty })
        #expect(model.questions.map(\.kind) == [.abbreviation])
        model.answer(model.questions[0].id, with: "Biológia")
        #expect(model.lesson(1)?.subject == "Biológia")
        #expect(model.questions.isEmpty && model.counts.needsReview == 0)
        model.answer("no such question", with: "x") // ignored
        model.answer(question.id, with: "not an option")
        #expect(model.lesson(0)?.room == "2O4")
    }

    @Test func dismissKeepsTheCurrentValue() {
        var model = review()
        model.dismiss(model.questions[0].id)
        #expect(model.lesson(0)?.room == "204" && model.lesson(2)?.room == "204")
        #expect(model.questions.count == 1)
    }

    @Test func editWithApplyToIdenticalCells() {
        var model = review()
        #expect(model.identicalLessonIDs(to: 0) == [0, 2])
        model.setValue("Matematika", field: .subject, lesson: 0, applyToIdentical: true)
        #expect(model.lesson(0)?.subject == "Matematika" && model.lesson(2)?.subject == "Matematika")
        model.setValue("Sálová", field: .subject, lesson: 3)
        #expect(model.lesson(3)?.subject == "Sálová")
        model.setValue("  ", field: .room, lesson: 3) // blank clears the field
        #expect(model.lesson(3)?.room == nil)
        model.removeLesson(0, applyToIdentical: true)
        #expect(model.lessons.map(\.id) == [1, 3])
    }

    @Test func confirmMoveAndPeriodTimes() {
        var model = review()
        model.confirm(lesson: 0, applyToIdentical: true)
        #expect(model.counts.needsReview == 0)
        #expect(model.questions.map(\.kind) == [.abbreviation])
        model.move(lesson: 3, day: .friday, period: 2, span: 2)
        #expect(model.lesson(3)?.day == .friday && model.lesson(3)?.period == 2 && model.lesson(3)?.span == 2)
        model.move(lesson: 3, day: .friday, period: 3, span: 2) // past the last period: ignored
        #expect(model.lesson(3)?.period == 2)
        model.setPeriodTimes(2, start: LocalTime("08:50")!, end: LocalTime("09:35")!)
        #expect(model.periods[1].start == LocalTime("08:50"))
        model.setPeriodTimes(2, start: LocalTime("08:30")!, end: LocalTime("09:35")!) // overlaps period 1: ignored
        #expect(model.periods[1].start == LocalTime("08:50"))
    }

    @Test func approveCreatesANewTimetableThroughTheSharePath() throws {
        var model = review()
        model.answer(model.questions[1].id, with: "Biológia")
        let payload = try model.approve(bellScheduleName: "Zvonenie")
        let before = SampleScenarios.secondary().database
        let after = try apply(.importShared(payload), to: before)
        let added = try #require(after.timetables.first { $0.name == "Rozvrh 3.A" })
        #expect(after.timetables.count == before.timetables.count + 1)
        #expect(after.settings.activeTimetableID == added.id)
        let lessons = after.lessons.filter { $0.timetableID == added.id }
        #expect(lessons.count == 4)
        let subjects = after.subjects.filter { $0.timetableID == added.id }.map(\.name).sorted()
        #expect(subjects == ["Biológia", "MAT", "SAL"])
        // Replace keeps the backup decision in the app: here only that the old one is gone and the new one is in.
        let replaced = try apply(.importShared(payload, replacing: added.id), to: after)
        #expect(replaced.timetables.filter { $0.name == "Rozvrh 3.A" && !$0.isDeleted }.count == 1)
    }

    @Test func approveRejectsInvalidNames() {
        var model = review()
        model.timetableName = String(repeating: "x", count: 500)
        #expect(throws: ShareError.self) { try model.approve(bellScheduleName: "Zvonenie") }
    }
}
