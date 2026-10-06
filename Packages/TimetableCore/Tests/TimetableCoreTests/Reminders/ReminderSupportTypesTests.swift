import Foundation
import Testing
@testable import TimetableCore

/// Hashing, identifiers, sources, actions, categories, l10n keys and Codable round trips.
@Suite("Reminder support types")
struct ReminderSupportTypesTests {
    typealias F = PlannerFixture

    @Test func fnv1a64KnownVectors() {
        #expect(StableHash.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
        #expect(StableHash.fnv1a64("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(StableHash.fnv1a64("foobar") == 0x8594_4171_F739_67E8)
        #expect(StableHash.hex(0xAF63_DC4C_8601_EC8C) == "af63dc4c8601ec8c")
        #expect(StableHash.hex(1) == "0000000000000001")
    }

    @Test func derivedUUIDIsDeterministicVersion8() {
        let a = StableHash.uuid("r1|exam/X|rule|m30|2026-10-08T08:00")
        #expect(a == StableHash.uuid("r1|exam/X|rule|m30|2026-10-08T08:00"))
        #expect(a != StableHash.uuid("r1|exam/X|rule|m31|2026-10-08T08:00"))
        let bytes = withUnsafeBytes(of: a.uuid) { Array($0) }
        #expect(bytes[6] >> 4 == 8)
        #expect(bytes[8] >> 6 == 0b10)
    }

    @Test func reminderIDFormat() {
        let id = ReminderID.make(key: "x")
        #expect(id.rawValue == "rem." + StableHash.hex(StableHash.fnv1a64("x")))
        #expect(id.description == id.rawValue)
        #expect(ReminderID.isPlannerID(id.rawValue))
        for bad in ["rem.", "rem.0123456789ABCDEF", "rem.0123456789abcde", "rem.0123456789abcdefa", "x.0123456789abcdef",
                    "rem.0123456789abcdeg"] {
            #expect(!ReminderID.isPlannerID(bad), "\(bad)")
        }
        #expect(ReminderID(rawValue: "rem.1") < ReminderID(rawValue: "rem.2"))
    }

    @Test func reminderSourceRawValueRoundTrips() throws {
        let sources: [ReminderSource] = [.task(F.taskID(1)), .exam(F.examID(2)),
                                         .lesson(.lesson(F.id(3, ns: F.lessonNS), on: F.d("2026-10-07"))),
                                         .lesson(.oneOff(F.id(4, ns: 0x2C07))), .packTonight(F.d("2026-10-07"))]
        for source in sources {
            #expect(ReminderSource(rawValue: source.rawValue) == source)
            #expect(try Fixture.roundTrip(source) == source)
        }
        #expect(sources[0].rawValue == "task/00002C02-0000-4000-8000-000000000001")
        #expect(sources[2].rawValue == "lesson/lesson:00002C05-0000-4000-8000-000000000003:2026-10-07")
        #expect(sources[4].rawValue == "packTonight/2026-10-07")
        #expect(sources.map(\.isCompletable) == [true, true, false, false, false])
        for bad in ["", "task", "task/nope", "exam/", "lesson/", "packTonight/2026-13-01", "other/x"] {
            #expect(ReminderSource(rawValue: bad) == nil, "\(bad)")
        }
        #expect(throws: DecodingError.self) { try Fixture.decode(ReminderSource.self, "\"task/nope\"") }
    }

    @Test func actionsAndCategories() {
        #expect(ReminderCategory.task.actions == [.markDone, .snoozeOneHour, .snoozeTomorrow])
        #expect(ReminderCategory.exam.actions == [.markDone, .snoozeOneHour, .snoozeTomorrow])
        #expect(ReminderCategory.lesson.actions.isEmpty)
        #expect(ReminderCategory.packTonight.actions == [.snoozeOneHour])
        #expect(ReminderAction.markDone.l10nKey == "reminder.action.markDone")
        #expect(ReminderAction.snoozeTomorrow.rawValue == "tabula.action.snoozeTomorrow")
        #expect(ReminderCategory.task.rawValue == "tabula.reminder.task")
    }

    @Test func snoozeDates() {
        let now = Fixture.utc("2026-10-24", "21:30") // 23:30 CEST, the night before fall-back
        #expect(ReminderAction.markDone.snoozeDate(now: now, context: F.bratislava) == nil)
        #expect(ReminderAction.snoozeOneHour.snoozeDate(now: now, context: F.bratislava) == now.addingTimeInterval(3600))
        #expect(ReminderAction.snoozeTomorrow.snoozeDate(now: now, context: F.bratislava) == Fixture.utc("2026-10-25", "06:00"),
                "07:00 CET")
        #expect(ReminderAction.snoozeTomorrow.snoozeDate(now: now, context: F.bratislava, tomorrowAt: F.t("09:15"))
                == Fixture.utc("2026-10-25", "08:15"))
    }

    @Test func l10nKeysAreUniqueAndCoverEverythingEmitted() {
        let keys = ReminderL10n.allKeys
        #expect(Set(keys).count == keys.count)
        #expect(keys.count == 42)
        #expect(keys.allSatisfy { $0.hasPrefix("reminder.") })
        let maths = F.subject(1, "Math")
        let lessons = [F.lesson(1, date: "2026-10-08", start: "08:00", end: "08:45", subject: maths, room: "1", bring: ["x"]),
                       F.lesson(2, date: "2026-10-12", start: "08:00", end: "08:45", subject: maths, bring: ["y"])]
        let offsets: [ReminderOffset] = [.daysBefore(4, at: F.t("18:00")), .daysBefore(1, at: F.t("18:00")), .minutesBefore(10)]
        let rules = [F.rule(1, .homework, offsets, followUp: .afterMinutes(5)), F.rule(2, .exam, offsets, followUp: .afterMinutes(5)),
                     F.rule(3, .lesson, offsets), F.rule(4, .packTonight, offsets)]
        let plan = ReminderPlanner.plan(F.input(
            rules: rules,
            tasks: [F.task(1, due: .dateTime(F.d("2026-10-12"), F.t("12:00"))), F.task(2, due: .date(F.d("2026-10-12")))],
            exams: [F.exam(1, date: "2026-10-12", start: "12:00", room: "A"), F.exam(2, date: "2026-10-12")],
            lessons: lessons, packTonight: PackTonightDay.days(from: lessons)))
        let emitted = plan.plannerContentKeys
        #expect(emitted.isSubset(of: Set(keys)), "\(emitted.subtracting(keys))")
        #expect(emitted.count >= 20)
    }

    @Test func planRoundTripsThroughCanonicalJSON() throws {
        let rules = [F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(30)),
                     F.rule(2, .exam, [.minutesBefore(60)], tier: .alarm), F.rule(3, .exam, [.minutesBefore(-1)])]
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: rules,
                                                tasks: [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))],
                                                exams: [F.exam(1, date: "2026-10-09", start: "09:00")], alarmSoftLimit: 0))
        #expect(!plan.notifications.isEmpty && !plan.dropped.isEmpty && !plan.alarmOverflow.isEmpty)
        #expect(try Fixture.roundTrip(plan) == plan)
        let json = try Fixture.json(plan.notifications[0])
        #expect(json.contains("\"id\":\"rem."))
        #expect(json.contains("\"source\":\"task/"))
    }

    @Test func tierAndDropReasonKeys() {
        #expect(TierChangeReason.leadTimeTooLong.l10nKey == "reminder.tierChange.leadTimeTooLong")
        #expect(DropReason.quietHoursAfterDue.l10nKey == "reminder.dropped.quietHoursAfterDue")
        #expect(TierChangeReason.allCases.count == 7)
        #expect(DropReason.allCases.count == 6)
    }
}
