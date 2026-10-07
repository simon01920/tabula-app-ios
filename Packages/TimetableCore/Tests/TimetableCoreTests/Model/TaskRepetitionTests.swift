import Foundation
import Testing
@testable import TimetableCore

/// `RepeatRule.nextDate(after:)` and `TaskItem.nextOccurrence(createdAt:)` (DOMAIN_MODEL §3.9 "Repetition").
@Suite("Task repetition")
struct TaskRepetitionTests {
    private func d(_ string: String) -> LocalDate { Fixture.date(string) }

    private func next(_ frequency: RepeatFrequency, every interval: Int = 1, on weekdays: Set<Weekday> = [],
                      until: String? = nil, after date: String) -> LocalDate? {
        RepeatRule(frequency: frequency, interval: interval, weekdays: weekdays, until: until.map(d)).nextDate(after: d(date))
    }

    @Test func daily() {
        #expect(next(.daily, after: "2026-10-08") == d("2026-10-09"))
        #expect(next(.daily, every: 3, after: "2026-12-30") == d("2027-01-02"))
        #expect(next(.daily, after: "2028-02-28") == d("2028-02-29"))
        #expect(next(.daily, on: [.monday], after: "2026-10-08") == d("2026-10-09"), "weekdays are ignored for daily")
    }

    @Test func weekly() {
        // 2026-10-05 is a Monday.
        #expect(next(.weekly, after: "2026-10-08") == d("2026-10-15"), "empty weekdays = the due date's weekday")
        #expect(next(.weekly, on: [.monday, .wednesday], after: "2026-10-05") == d("2026-10-07"))
        #expect(next(.weekly, on: [.monday, .wednesday], after: "2026-10-07") == d("2026-10-12"))
        #expect(next(.weekly, every: 2, on: [.monday, .wednesday], after: "2026-10-07") == d("2026-10-19"), "every 2nd ISO week")
        #expect(next(.weekly, every: 2, on: [.monday, .wednesday], after: "2026-10-05") == d("2026-10-07"), "same week first")
        #expect(next(.weekly, on: [.monday, .wednesday], after: "2026-10-06") == d("2026-10-07"), "due day not in the set")
        // Weeks are ISO (Monday–Sunday) whatever the user's week start: Sunday closes its week.
        #expect(next(.weekly, every: 2, on: [.monday], after: "2026-10-11") == d("2026-10-19"))
        #expect(next(.weekly, every: 2, on: [.sunday], after: "2026-10-11") == d("2026-10-25"))
        // Across the 53-week ISO year 2026 and a year boundary.
        #expect(next(.weekly, after: "2026-12-31") == d("2027-01-07"))
    }

    @Test func monthlySkipsMonthsWithoutTheDay() {
        #expect(next(.monthly, after: "2026-10-08") == d("2026-11-08"))
        #expect(next(.monthly, after: "2027-01-31") == d("2027-03-31"), "February has no 31st: skipped, no clamping")
        #expect(next(.monthly, after: "2027-03-31") == d("2027-05-31"), "no drift after a skip")
        #expect(next(.monthly, every: 3, after: "2026-11-30") == d("2027-05-30"), "Feb 30 skipped")
        #expect(next(.monthly, every: 12, after: "2028-02-29") == d("2032-02-29"), "next leap year")
        #expect(next(.monthly, every: 12, after: "2096-02-29") == d("2104-02-29"), "2100 is not a leap year")
        #expect(next(.monthly, after: "2026-12-15") == d("2027-01-15"))
    }

    @Test func endsAndHostileValues() {
        #expect(next(.daily, until: "2026-10-09", after: "2026-10-08") == d("2026-10-09"), "until is inclusive")
        #expect(next(.daily, until: "2026-10-08", after: "2026-10-08") == nil)
        #expect(next(RepeatFrequency(rawValue: "yearly"), after: "2026-10-08") == nil, "unknown frequency")
        #expect(next(.daily, every: 0, after: "2026-10-08") == nil)
        #expect(next(.weekly, every: -1, after: "2026-10-08") == nil)
        for frequency in RepeatFrequency.knownValues {
            #expect(next(frequency, every: .max, after: "2026-10-08") == nil, "\(frequency)")
            #expect(next(frequency, every: .max, on: [.monday, .sunday], after: "9999-12-31") == nil, "\(frequency)")
            #expect(next(frequency, every: 1, after: "9999-12-31") == nil, "\(frequency)")
        }
    }

    /// Property-style: the closed forms equal day-by-day / month-by-month oracles.
    @Test func matchesBruteForceOracles() {
        var rng = TestRNG(seed: 0x5EED)
        let start = d("2024-01-01")
        for _ in 0..<1_500 {
            let date = start.adding(days: Int.random(in: 0...(366 * 6), using: &rng))
            let interval = Int.random(in: 1...5, using: &rng)
            let weekdays = Set(Weekday.allCases.filter { _ in Int.random(in: 0..<3, using: &rng) == 0 })
            let rule = RepeatRule(frequency: .weekly, interval: interval, weekdays: weekdays)
            let days = weekdays.isEmpty ? [date.weekday] : weekdays
            let monday = date.adding(days: 1 - date.weekday.rawValue)
            let oracle = (1...(7 * interval + 7)).lazy.map { date.adding(days: $0) }.first { candidate in
                let weeks = monday.days(to: candidate.adding(days: 1 - candidate.weekday.rawValue)) / 7
                return weeks % interval == 0 && days.contains(candidate.weekday)
            }
            #expect(rule.nextDate(after: date) == oracle, "weekly \(interval) \(weekdays.sorted()) after \(date)")

            let monthly = RepeatRule(frequency: .monthly, interval: interval).nextDate(after: date)
            var monthOracle: LocalDate?
            for step in 1...48 where monthOracle == nil {
                let index = date.year * 12 + date.month - 1 + step * interval
                monthOracle = LocalDate(year: index / 12, month: index % 12 + 1, day: date.day)
            }
            #expect(monthly == monthOracle, "monthly \(interval) after \(date)")
            #expect(RepeatRule(frequency: .daily, interval: interval).nextDate(after: date) == date.adding(days: interval))
        }
    }

    @Test func nextOccurrenceCopiesTheSeriesAndResetsTheOccurrence() throws {
        var task = try #require(Fixture.fullDatabase().tasks.first { $0.repeatRule != nil })
        // Due Thu 2026-10-08 08:00, weekly on Mon + Wed → next Mon 2026-10-12 08:00.
        var deleted = task.subtasks[0]
        deleted.id = Subtask.ID(UUID(uuidString: "000000F1-0000-4000-8000-0000000000DE")!)
        deleted.meta.isDeleted = true
        task.subtasks.append(deleted)
        task.completedAt = Fixture.now
        let stamp = HLCTimestamp(physicalMillis: 1_791_000_000_000, logical: 0, node: 7)
        let next = try #require(task.nextOccurrence(createdAt: stamp))
        #expect(next.id == TaskItem.nextOccurrenceID(after: task.id))
        #expect(next.id != task.id)
        #expect(next.meta == .created(at: stamp))
        #expect(next.due == .dateTime(d("2026-10-12"), Fixture.time("08:00")))
        #expect(next.title == task.title && next.kind == task.kind && next.subjectID == task.subjectID)
        #expect(next.timetableID == task.timetableID && next.priority == task.priority && next.notes == task.notes)
        #expect(next.repeatRule == task.repeatRule && next.reminderOverride == task.reminderOverride)
        #expect(next.completedAt == nil && next.linkedLesson == nil && next.attachments.isEmpty)
        #expect(next.subtasks.count == 2, "tombstoned subtasks are not copied")
        #expect(next.subtasks.allSatisfy { $0.completedAt == nil && $0.meta == .created(at: stamp) })
        #expect(Set(next.subtasks.map(\.title)) == ["Read", "Write"])
        #expect(Set(next.subtasks.map(\.id)).isDisjoint(with: task.subtasks.map(\.id)))
        // Deterministic: the same input gives the same IDs on every device and run.
        let again = try #require(task.nextOccurrence(createdAt: HLCTimestamp(physicalMillis: 1, logical: 0, node: 9)))
        #expect(again.id == next.id && again.subtasks.map(\.id) == next.subtasks.map(\.id))
        // Version-8 name-based UUIDs.
        let string = next.id.uuidString
        #expect(Array(string)[14] == "8" && "89AB".contains(Array(string)[19]))
        // The chain continues from the next occurrence.
        let third = try #require(next.nextOccurrence(createdAt: stamp))
        #expect(third.due == .dateTime(d("2026-10-14"), Fixture.time("08:00")))
        #expect(third.id == TaskItem.nextOccurrenceID(after: next.id) && third.id != next.id)

        var none = task
        none.repeatRule = nil
        #expect(none.nextOccurrence(createdAt: stamp) == nil)
        none.repeatRule = task.repeatRule
        none.due = .unknown(.object(["kind": .string("week")]))
        #expect(none.nextOccurrence(createdAt: stamp) == nil)
        none.due = nil
        #expect(none.nextOccurrence(createdAt: stamp) == nil)
        none.due = .date(d("2027-01-31"))
        #expect(none.nextOccurrence(createdAt: stamp) == nil, "past until (2027-01-31)")
    }

    /// Two devices complete the same occurrence while offline; each creates the next task. After syncing in
    /// either order there is exactly one next task, and both replicas are identical.
    @Test func concurrentCompletionOnTwoDevicesConverges() throws {
        var setupClock = HybridLogicalClock(node: 0x1)
        let draft = TaskItem(id: SyncFixture.taskID(1), meta: Fixture.meta(), title: "Vocabulary",
                             due: .date(d("2026-10-08")), repeatRule: RepeatRule(frequency: .weekly),
                             subtasks: [SyncFixture.subtask(1, "Learn"), SyncFixture.subtask(2, "Test yourself", sortIndex: 1)])
        let task = try MutationStamper.stamp(old: nil, new: draft, clock: &setupClock, now: SyncFixture.at(0))
        let base = TabulaDatabase(settings: .untouchedDefaults, tasks: [task])

        func completeOnDevice(node: UInt64, at millis: Int64) throws -> TabulaDatabase {
            var clock = HybridLogicalClock(node: node, last: setupClock.last)
            var done = task
            done.completedAt = SyncFixture.at(millis)
            done.subtasks = done.subtasks.map { var subtask = $0; subtask.completedAt = SyncFixture.at(millis); return subtask }
            var db = base
            db.tasks = [try MutationStamper.stamp(old: task, new: done, clock: &clock, now: SyncFixture.at(millis))]
            let next = try #require(done.nextOccurrence(createdAt: clock.tick(now: SyncFixture.at(millis))))
            #expect(!db.tasks.contains { $0.id == next.id }, "caller inserts only when the ID is new")
            db.tasks.append(next)
            return db
        }
        let deviceA = try completeOnDevice(node: 0xA, at: 1_000)
        let deviceB = try completeOnDevice(node: 0xB, at: 5_000)
        let ab = try SyncMerge.merge(local: deviceA, remote: deviceB)
        let ba = try SyncMerge.merge(local: deviceB, remote: deviceA)
        #expect(try ab.encoded() == ba.encoded())
        #expect(ab.tasks.count == 2)
        let next = try #require(ab.tasks.first { $0.id == TaskItem.nextOccurrenceID(after: task.id) })
        #expect(next.due == .date(d("2026-10-15")) && next.completedAt == nil && next.subtasks.count == 2)
        #expect(next.subtasks.allSatisfy { $0.completedAt == nil })
        #expect(ab.tasks.first { $0.id == task.id }?.isCompleted == true)
        #expect(ab.isValid, "\(ab.validate())")
        // Merging again changes nothing (idempotent).
        #expect(try SyncMerge.merge(local: ab, remote: deviceA).encoded() == ab.encoded())
    }
}
