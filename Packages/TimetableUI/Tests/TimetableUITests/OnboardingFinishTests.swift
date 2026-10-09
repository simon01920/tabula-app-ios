import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let today = LocalDate(year: 2026, month: 10, day: 13)!
private let names = OnboardingNames(timetable: "School", bellSchedule: "Bells", term: "Semester")
private let reference = Date(timeIntervalSince1970: 1_791_879_600)

@Suite("Onboarding finish never loses data")
struct OnboardingFinishTests {
    private func finish(_ draft: OnboardingDraft, on existing: TabulaDatabase?) throws -> TabulaDatabase {
        let mutation = draft.finishMutation(existing: existing, names: names, localeFirstWeekday: .monday,
                                            localize: { $0.key }, now: reference)
        var clock = HybridLogicalClock(node: 0xC0DE)
        if let existing { clock.receive(existing.latestTimestamp, now: reference) }
        return try mutation.apply(to: existing ?? DatabaseMutation.emptyBase, clock: &clock, now: reference)
    }

    @Test func emptyDatabaseIsReplaced() throws {
        #expect(!DatabaseMutation.emptyBase.hasLiveContent && DatabaseMutation.emptyBase.hasNoEntities)
        let draft = OnboardingDraft(today: today, profile: .secondary)
        let result = try finish(draft, on: nil)
        #expect(result.timetables.count == 1)
        #expect(result.settings.onboardingCompletedAt != nil)
        let replaced = try finish(draft, on: DatabaseMutation.emptyBase)
        #expect(replaced.timetables.count == 1)
    }

    @Test func existingTasksExamsAndTimetablesSurvive() throws {
        var existing = SampleScenarios.secondary().database
        var clock = HybridLogicalClock(node: 0xD)
        clock.receive(existing.latestTimestamp, now: reference)
        // the user deleted the timetable; tasks and exams remain
        for id in existing.timetables.map(\.id) {
            existing = try DatabaseMutation.delete(id).apply(to: existing, clock: &clock, now: reference)
        }
        #expect(existing.hasLiveContent)
        var draft = OnboardingDraft(today: today, profile: .university)
        draft.start = .sample
        let result = try finish(draft, on: existing)

        #expect(Set(existing.tasks.map(\.id)).isSubset(of: Set(result.tasks.map(\.id))))
        #expect(Set(existing.exams.map(\.id)).isSubset(of: Set(result.exams.map(\.id))))
        #expect(Set(existing.timetables.map(\.id)).isSubset(of: Set(result.timetables.map(\.id))))
        #expect(result.tasks.count == existing.tasks.count + 1)
        #expect(result.timetables.filter { !$0.isDeleted }.count == 1)
        #expect(result.settings.activeTimetableID == result.timetables.first { !$0.isDeleted }?.id)
        #expect(result.settings.onboardingCompletedAt == reference)
        #expect(result.settings.profile == .university)
        #expect(result.validate().filter { $0.severity == .error }.isEmpty)
    }

    @Test func secondTimetableIsAppendedAndSampleIdsAreFresh() throws {
        let existing = SampleScenarios.secondary().database
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.start = .sample
        let result = try finish(draft, on: existing)
        #expect(result.timetables.count == existing.timetables.count + 1)
        let added = result.timetables.first { t in !existing.timetables.contains { $0.id == t.id } }
        #expect((added?.sortIndex ?? 0) > existing.timetables.map(\.sortIndex).max() ?? 0)
        #expect(result.lessons.count > existing.lessons.count)
        #expect(Set(existing.lessons.map(\.id)).isSubset(of: Set(result.lessons.map(\.id))))
        // existing reminder rules are not duplicated
        #expect(result.reminderRules.count == existing.reminderRules.count)
    }
}
