import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Apply warnings")
struct ApplyWarningsTests {
    private func issue(_ severity: ValidationIssue.Severity, _ code: ValidationIssue.Code, _ type: EntityType = .lesson,
                       value: String? = nil) -> ValidationIssue {
        ValidationIssue(severity: severity, code: code, entityType: type, entityID: UUID(), value: value)
    }

    @Test func periodLessonsInFreeFormFoldIntoOneCountedLine() {
        let lines = ApplyWarnings.lines(from: [
            issue(.warning, .invalidValue, value: "freeForm"), issue(.warning, .invalidValue, value: "freeForm"),
            issue(.info, .emptyScheduleDay, .timetable),
        ])
        #expect(lines.count == 1)
        #expect(lines[0].messageKey == ApplyWarnings.periodInFreeFormKey)
        #expect(lines[0].count == 2 && lines[0].takesCount && lines[0].entityKey == nil)
    }

    @Test func otherWarningsUseTheValidationMessageAndEntityName() {
        let lines = ApplyWarnings.lines(from: [issue(.warning, .overlappingPeriods, .bellSchedule),
                                               issue(.warning, .invalidValue, value: "7")])
        #expect(lines.map(\.messageKey) == ["validation.overlappingPeriods", "validation.invalidValue"])
        #expect(lines.allSatisfy { $0.entityKey != nil && !$0.takesCount })
        #expect(ApplyWarnings.lines(from: []).isEmpty)
    }

    @Test func switchingPeriodLessonsToFreeFormWarnsInTheRealValidator() throws {
        let scenario = SampleScenarios.secondary()
        var timetable = scenario.timetable
        timetable.timeStructure = .freeForm(defaultDurationMinutes: 50)
        var clock = HybridLogicalClock(node: 0xB6)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        clock.receive(scenario.database.latestTimestamp, now: now)
        let database = try DatabaseMutation.upsert(timetable).apply(to: scenario.database, clock: &clock, now: now)
        let lines = ApplyWarnings.lines(from: database.validate())
        let line = try #require(lines.first { $0.messageKey == ApplyWarnings.periodInFreeFormKey })
        // Also counts period-based extra lessons / overrides (same warning), so at least the regular lessons.
        #expect(line.count >= TimetableDraft.periodLessonCount(lessons: database.lessons, timetableID: timetable.id))
    }
}
