// Regression tests of the 2026-11 QA bug fix pass (branch wip/bugfix-2026-11).
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Bug fix pass 2026-11")
struct BugfixPass202611Tests {
    /// Fix 2: "Change for This Day" on a cancelled lesson must not preselect it (saving a change would undo the cancel).
    @Test func cancelledTappedLessonIsNotPreselected() {
        let tapped = Lesson.ID(UUID()), other = Lesson.ID(UUID())
        #expect(DayChangeDraft.preselectedLesson(tapped, available: [other, tapped]) == tapped)
        #expect(DayChangeDraft.preselectedLesson(tapped, available: [other]) == nil, "cancelled that day")
        #expect(DayChangeDraft.preselectedLesson(nil, available: [other, tapped]) == other)
        #expect(DayChangeDraft.preselectedLesson(nil, available: []) == nil)
    }

    /// Fix 4: editing a lesson while the timetable has no week cycle keeps its stored A/B restriction.
    @Test func editingWithoutWeekCycleKeepsCycleWeeks() throws {
        let scenario = SampleScenarios.secondary()
        let today = LocalDate(year: 2027, month: 2, day: 10)!
        var lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        lesson.occurrence = LessonOccurrenceRule(day: lesson.occurrence.day, cycleWeeks: [2])
        var timetable = scenario.timetable
        timetable.rotation = .none
        var draft = LessonDraft(lesson: lesson, timetable: timetable, today: today)
        draft.room = "301"
        let kept = try #require(draft.makeLesson(in: timetable))
        #expect(kept.occurrence.cycleWeeks == [2])
        // With a week cycle the editor's choice still wins (all weeks = no restriction).
        timetable.rotation = .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: today, cycleWeek: 1)))
        draft.cycleWeeks = [1, 2]
        let everyWeek = try #require(draft.makeLesson(in: timetable))
        #expect(everyWeek.occurrence.cycleWeeks == nil)
    }
}
