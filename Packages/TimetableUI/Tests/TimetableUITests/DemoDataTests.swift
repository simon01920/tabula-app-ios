import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("DemoData")
struct DemoDataTests {
    /// Every `"yyyy-MM-dd"` string in the encoded database (LocalDate values; instants encode as numbers).
    private func localDates(_ database: TabulaDatabase) throws -> [String] {
        let json = String(decoding: try database.encoded(), as: UTF8.self)
        let regex = try NSRegularExpression(pattern: "\"(\\d{4}-\\d{2}-\\d{2})\"")
        return regex.matches(in: json, range: NSRange(json.startIndex..., in: json))
            .map { String(json[Range($0.range(at: 1), in: json)!]) }
    }

    @Test func roundsToTheNearestWeek() {
        let tuesday = SampleScenarios.today   // Tue 2026-10-13
        #expect(DemoData.weeks(from: tuesday, to: tuesday.adding(days: 3)) == 0)
        #expect(DemoData.weeks(from: tuesday, to: tuesday.adding(days: 4)) == 1)
        #expect(DemoData.weeks(from: tuesday, to: tuesday.adding(days: -4)) == -1)
        #expect(DemoData.weeks(from: tuesday, to: LocalDate(year: 2026, month: 11, day: 1)!) == 3)   // Sun → Tue 3 Nov
    }

    @Test(arguments: [SeedKind.elementary, .secondary, .university])
    func movesEveryStoredDate(kind: SeedKind) throws {
        let original = try #require(SampleScenarios.make(kind).database)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let today = SampleScenarios.today.adding(days: 7 * 5 + 1)
        let demo = try #require(DemoData.database(kind, today: today, now: now))
        // Every LocalDate anywhere in the schema moved by exactly 5 weeks (catches a field the shift forgot).
        let expected = try localDates(original).map { LocalDate($0)!.adding(days: 35).description }
        #expect(try localDates(demo) == expected)
        #expect(!expected.isEmpty)
        #expect(demo.settings.onboardingCompletedAt == now)
        #expect(demo.settings.activeTimetableID == ActiveTimetable.resolve(original)?.id)
        #expect(demo.validate().filter { $0.severity == .error }.isEmpty)
        // Completion instants moved by the same days, keeping their local time across the DST change.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SampleScenarios.timeZone
        for (before, after) in zip(original.tasks, demo.tasks) {
            #expect(after.completedAt == before.completedAt.flatMap { calendar.date(byAdding: .day, value: 35, to: $0) })
        }
    }
}
