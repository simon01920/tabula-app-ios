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

    /// Fix 5: a free-form timetable is not offered "Shortened lessons" (its bell editor would convert it).
    @Test func shortDayOnlyForBellScheduleTimetables() {
        var timetable = SampleScenarios.secondary().timetable
        #expect(DayChangeDraft.offersShortDay(in: timetable))
        timetable.timeStructure = .freeForm(defaultDurationMinutes: 90)
        #expect(!DayChangeDraft.offersShortDay(in: timetable))
    }

    /// Fix 6: a backup that contains a validation error can be restored (replace and merge); a new error still blocks.
    @Test func restoreAcceptsTheBackupsOwnErrors() throws {
        let now = Date(timeIntervalSince1970: 1_791_879_600)
        let current = SampleScenarios.secondary().database   // restoring an older copy of the same data
        var backup = current
        backup.lessons[0].subjectID = Subject.ID(UUID())   // dangling reference inside the backup
        #expect(backup.validate().contains { $0.severity == .error })
        for mode in [BackupRestore.Mode.replace, .merge] {
            let mutation = DatabaseMutation.restore(backup, mode: mode)
            var clock = HybridLogicalClock(node: 0xA11)
            clock.receive(current.latestTimestamp, now: now)
            let restored = try mutation.apply(to: current, clock: &clock, now: now)
            let after = restored.validate()
            if mode == .replace, case .accepted = MutationValidation.verdict(before: current.validate(), after: after) {
                Issue.record("the old rule should reject the replace")
            }
            guard case .accepted = MutationValidation.verdict(for: mutation, before: current.validate(), after: after) else {
                Issue.record("restore rejected (\(mode))"); continue
            }
        }
        // An error neither side had still blocks.
        let fresh = ValidationIssue(severity: .error, code: .invalidTimeRange, entityType: .lesson, entityID: UUID())
        let mutation = DatabaseMutation.restore(backup, mode: .merge)
        guard case .rejected(let errors) = MutationValidation.verdict(for: mutation, before: [],
                                                                      after: backup.validate() + [fresh]) else {
            Issue.record("a new error must still reject"); return
        }
        #expect(errors == [fresh])
    }
}
