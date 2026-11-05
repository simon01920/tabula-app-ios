import Foundation
import Testing
@testable import TimetableCore

/// Phase 10 P13: `validate()` sorts with keys built once per issue. The order must equal the former sort, whose
/// comparator built both seven-string keys on every comparison (kept here as the reference).
@Suite("Validation — issue order")
struct ValidationOrderTests {
    static func referenceKey(_ issue: ValidationIssue) -> [String] {
        [issue.entityType.rawValue, issue.entityID.uuidString, issue.field ?? "", issue.code.rawValue,
         issue.childID?.uuidString ?? "", issue.relatedID?.uuidString ?? "", issue.value ?? ""]
    }

    static func referenceOrder(_ issues: [ValidationIssue]) -> [ValidationIssue] {
        issues.sorted { referenceKey($0).lexicographicallyPrecedes(referenceKey($1)) }
    }

    /// Issues drawn from small pools so that keys collide often (ties keep their relative order in both sorts;
    /// severity is not part of the key, so tied issues can still differ).
    static func randomIssues(_ rng: inout TestRNG, count: Int) -> [ValidationIssue] {
        var ids = SequentialIDGenerator(namespace: 0x913)
        let pool = (0..<4).map { _ in ids.nextUUID() }
        let fields: [String?] = [nil, "slot", "subjectID", ""]
        let values: [String?] = [nil, "x", "\u{E9}", "e\u{301}", "10", "9"]
        return (0..<count).map { _ in
            ValidationIssue(severity: ValidationIssue.Severity.allCases.randomElement(using: &rng)!,
                            code: [ValidationIssue.Code.duplicateID, .danglingReference, .invalidValue].randomElement(using: &rng)!,
                            entityType: [EntityType.lesson, .subject, .timetable].randomElement(using: &rng)!,
                            entityID: pool.randomElement(using: &rng)!,
                            childID: Bool.random(using: &rng) ? pool.randomElement(using: &rng)! : nil,
                            field: fields.randomElement(using: &rng)!,
                            relatedID: Bool.random(using: &rng) ? pool.randomElement(using: &rng)! : nil,
                            value: values.randomElement(using: &rng)!)
        }
    }

    @Test func canonicalOrderEqualsComparatorSort() {
        var rng = TestRNG(seed: 0x13)
        for trial in 0..<40 {
            let issues = Self.randomIssues(&rng, count: trial * 7)
            #expect(ValidationIssue.canonicallyOrdered(issues) == Self.referenceOrder(issues), "trial \(trial)")
        }
    }

    @Test func validateIsSortedByTheKey() {
        // A database with several issues of different entities: the result is in reference order.
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1)
        let ghost: Subject.ID = world.ids.next()
        world.lesson(ghost, .tuesday, period: 1)
        world.lesson(ghost, .wednesday, period: 6)
        let db = TabulaDatabase(settings: AppSettings(meta: Fixture.meta()), timetables: [world.timetable],
                                subjects: world.subjects, bellSchedules: world.bellSchedules, lessons: world.lessons)
        let issues = db.validate()
        #expect(!issues.isEmpty)
        #expect(issues == Self.referenceOrder(issues))
    }
}
