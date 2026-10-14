import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("SampleScenarios")
struct SampleScenarioTests {
    @Test(arguments: SeedKind.allCases)
    func deterministicAndValid(kind: SeedKind) throws {
        let first = SampleScenarios.make(kind)
        let second = SampleScenarios.make(kind)
        #expect(first.referenceNow == Date(timeIntervalSince1970: 1_791_879_600))   // Tue 2026-10-13 10:20 CEST
        #expect(first.timeZone.identifier == "Europe/Bratislava")
        guard let database = first.database else {
            #expect(kind == .empty)
            return
        }
        // Byte-identical across builds (screenshots and the engine report are reproducible).
        #expect(try database.encoded() == second.database?.encoded())
        // No validation errors; the app would refuse to edit otherwise.
        let errors = database.validate().filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        #expect(database.settings.onboardingCompletedAt != nil)
        #expect(ActiveTimetable.resolve(database) != nil)
    }

    @Test func secondaryMatchesTheEngineDemoShape() {
        let scenario = SampleScenarios.secondary()
        #expect(scenario.database.subjects.count == 12)
        #expect(scenario.database.lessons.count == 32)
        #expect(scenario.database.overrides.count == 4)
        #expect(scenario.database.tasks.count == 8)   // 4 original + 4 Phase 3 C1 scenarios
        #expect(scenario.database.exams.count == 3)   // + the past History test (C1)
        #expect(scenario.context == CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday))
        // The reference day (docs/checklists/PHASE2_DEVICE.md A5): ISO week 42 = week B → Etická výchova in period 7.
        let resolver = ScheduleResolver(database: scenario.database, timetableID: scenario.timetable.id,
                                        context: scenario.context)
        let day = resolver?.day(SampleScenarios.today)
        #expect(day?.entries.map { $0.subject.shortName ?? "" } == ["MAT", "CHE", "SJL", "BIO", "NEJ", "GEO", "ETV"])
    }

    @Test func elementaryReferenceDayHasChangedLessons() throws {
        let database = SampleScenarios.elementary()
        let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
        let resolver = try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id,
                                                     context: context))
        let day = resolver.day(SampleScenarios.today)
        #expect(day.entries.map(\.status) == [.scheduled, .scheduled, .scheduled, .modified, .cancelled])
        let nowNext = resolver.nowAndNext(at: SampleScenarios.referenceNow)
        #expect(nowNext.state == .inLesson)   // 10:20 is in the 3rd lesson (10:00–10:45)
    }

    @Test func universityUsesFreeFormTimesAndBuildings() throws {
        let database = SampleScenarios.university()
        #expect(database.bellSchedules.isEmpty)
        #expect(database.subjects.allSatisfy { $0.defaultBuilding == "FIIT" })
        let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
        let resolver = try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id,
                                                     context: context))
        let nowNext = resolver.nowAndNext(at: SampleScenarios.referenceNow)
        #expect(nowNext.current?.subject.shortName == "DBS")   // Tue 09:00–10:30 lecture
        #expect(nowNext.next?.subject.shortName == "PS")
    }

    @Test func blankHasATimetableButNoSubjects() {
        let database = SampleScenarios.blank()
        #expect(database.timetables.count == 1)
        #expect(database.subjects.isEmpty && database.lessons.isEmpty)
    }
}
