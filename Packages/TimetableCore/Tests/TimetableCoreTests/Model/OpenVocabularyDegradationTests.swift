import Foundation
import Testing
@testable import TimetableCore

/// Pre-freeze QA: `UserProfile`, `Density`, `DeliveryTier`, `Appearance`, `HourCycle` are open vocabularies and
/// `FollowUp`, `TaskDue`, `LessonValidity` open unions. Unknown values round-trip byte for byte and degrade as
/// documented in DOMAIN_MODEL §5.
@Suite("Open vocabularies: round trip and degradation")
struct OpenVocabularyDegradationTests {
    static let futureFollowUp = JSONValue.object(["kind": .string("atLessonEnd"), "lesson": .integer(2)])
    static let futureDue = JSONValue.object(["kind": .string("week"), "week": .string("2026-W42")])
    static let futureValidity = JSONValue.object(["from": .integer(1), "kind": .string("cycleRange")])

    /// `Fixture.fullDatabase()` with one unknown value per opened type.
    static func futureDatabase() -> (db: TabulaDatabase, lessonID: Lesson.ID, taskID: TaskItem.ID) {
        var db = Fixture.fullDatabase()
        db.settings.profile = UserProfile(rawValue: "teacher")
        db.settings.hourCycle = HourCycle(rawValue: "h10")
        db.settings.appearance = Appearance(rawValue: "highContrast")
        db.timetables[0].density = Density(rawValue: "spacious")
        db.reminderRules[0].tier = DeliveryTier(rawValue: "critical")
        db.reminderRules[0].followUp = .unknown(futureFollowUp)
        let taskIndex = db.tasks.firstIndex { !$0.isCompleted }!
        db.tasks[taskIndex].due = .unknown(futureDue)
        let lessonIndex = db.lessons.firstIndex { $0.validity == .always && $0.timetableID == db.timetables[0].id }!
        db.lessons[lessonIndex].validity = .unknown(futureValidity)
        return (db, db.lessons[lessonIndex].id, db.tasks[taskIndex].id)
    }

    @Test func unknownValuesRoundTripByteForByte() throws {
        let (db, lessonID, taskID) = Self.futureDatabase()
        let bytes = try TabulaJSON.makeEncoder().encode(db)
        let decoded = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: bytes)
        #expect(try TabulaJSON.makeEncoder().encode(decoded) == bytes)
        #expect(decoded == db.canonicalized())
        let text = String(decoding: bytes, as: UTF8.self)
        for raw in [#""profile":"teacher""#, #""hourCycle":"h10""#, #""appearance":"highContrast""#,
                    #""density":"spacious""#, #""tier":"critical""#, #""followUp":{"kind":"atLessonEnd","lesson":2}"#,
                    #""due":{"kind":"week","week":"2026-W42"}"#, #""validity":{"from":1,"kind":"cycleRange"}"#] {
            #expect(text.contains(raw), "\(raw)")
        }
        #expect(decoded.lessons.first { $0.id == lessonID }?.validity.isKnown == false)
        #expect(decoded.tasks.first { $0.id == taskID }?.due?.date == nil)
        // A known kind with a malformed payload stays a decoding error (never silently "unknown").
        #expect(throws: DecodingError.self) { try Fixture.decode(TaskDue.self, #"{"kind":"date"}"#) }
        #expect(throws: DecodingError.self) { try Fixture.decode(LessonValidity.self, #"{"kind":"range"}"#) }
        #expect(try Fixture.decode(LessonValidity.self, "[1]") == .unknown(.array([.integer(1)])))
        #expect(try Fixture.decode(TaskDue.self, #"{"date":"2026-10-08"}"#) == .unknown(.object(["date": .string("2026-10-08")])))
    }

    @Test func validationReportsEveryUnknownValue() {
        let (db, lessonID, taskID) = Self.futureDatabase()
        let unknown = db.validate().filter { $0.code == .unknownValue }
        func issue(_ type: EntityType, _ field: String) -> ValidationIssue? {
            unknown.first { $0.entityType == type && $0.field == field }
        }
        for field in ["profile", "hourCycle", "appearance"] { #expect(issue(.settings, field)?.severity == .info, "\(field)") }
        #expect(issue(.timetable, "density")?.value == "spacious")
        #expect(issue(.reminderRule, "tier")?.value == "critical")
        #expect(issue(.reminderRule, "followUp")?.value == "atLessonEnd")
        #expect(issue(.task, "due")?.entityID == taskID.uuid)
        // Hiding a lesson is worth a warning, not just an info.
        #expect(issue(.lesson, "validity")?.severity == .warning)
        #expect(issue(.lesson, "validity")?.entityID == lessonID.uuid)
        #expect(db.isValid, "unknown values are never errors")
    }

    @Test func effectiveValuesFallBackToSafeDefaults() {
        #expect(UserProfile(rawValue: "teacher").effective == .other)
        #expect(ProfilePreset.for(UserProfile(rawValue: "teacher")) == .other)
        #expect(UserProfile.university.effective == .university)
        #expect(Density(rawValue: "spacious").effective == .comfortable && Density.compact.effective == .compact)
        #expect(Appearance(rawValue: "highContrast").effective == .auto && Appearance.dark.effective == .dark)
        #expect(HourCycle(rawValue: "h10").effective == .auto && HourCycle.h12.effective == .h12)
        let critical = DeliveryTier(rawValue: "critical")
        #expect(critical.effective == .standard && !critical.isKnown)
        // Order: by the effective rank, ties by raw value — total and consistent with ==.
        #expect(DeliveryTier.standard < .timeSensitive && DeliveryTier.timeSensitive < .alarm)
        #expect(critical < .timeSensitive && critical < .standard && !(critical < critical), "rank 0, then \"c\" < \"s\"")
        #expect([DeliveryTier.alarm, .standard, critical, .timeSensitive].sorted() == [critical, .standard, .timeSensitive, .alarm])
    }

    @Test func plannerTreatsUnknownTierAsStandardAndSkipsUnknownFollowUpsAndDueDates() {
        typealias F = PlannerFixture
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], tier: DeliveryTier(rawValue: "critical"),
                          followUp: .unknown(Self.futureFollowUp))
        let dated = F.task(1, due: .date(F.d("2026-10-08")))
        let undated = F.task(2, due: .unknown(Self.futureDue))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [dated, undated]))
        #expect(plan.notifications.count == 1)
        let only = plan.notifications.first
        #expect(only?.source == .task(dated.id) && only?.isFollowUp == false)
        // The raw value is kept; the degradation is an explained tier change.
        #expect(only?.requestedTier == DeliveryTier(rawValue: "critical") && only?.effectiveTier == .standard)
        #expect(only?.tierChanges == [.unknownTier])
        #expect(plan.alarms.isEmpty)
        // The unknown follow-up is reported once, as coming from a newer version; the undated task plans nothing.
        #expect(plan.dropped.map(\.reason) == [.unsupportedOffset])
        #expect(plan.dropped.first?.isFollowUp == true)
        #expect(!plan.dropped.contains { $0.source == .task(undated.id) })

        // An override tier from a newer version also degrades to standard (never to an alarm).
        let override = ReminderOverride(offsets: [.minutesBefore(30)], tier: DeliveryTier(rawValue: "siren"))
        let timed = F.task(3, due: .dateTime(F.d("2026-10-08"), F.t("09:00")), override: override)
        let overridden = ReminderPlanner.plan(F.input(rules: [], tasks: [timed]))
        #expect(overridden.notifications.map(\.effectiveTier) == [.standard])
        #expect(overridden.notifications.map(\.requestedTier) == [DeliveryTier(rawValue: "siren")])
        #expect(overridden.notifications.map(\.tierChanges) == [[.unknownTier]])
    }

    @Test func lessonWithUnknownValidityIsNeverShown() {
        var world = ScheduleWorld()
        let visible = world.lesson(world.math, .monday, period: 1)
        let hidden = world.lesson(world.physics, .monday, period: 2, validity: .unknown(Self.futureValidity))
        for options in [ResolutionOptions.actual, .regular, .allLessons] {
            let ids = world.day("2026-10-12", options: options).entries.map(\.source)
            #expect(ids == [.lesson(visible)], "\(options)")
            #expect(!ids.contains(.lesson(hidden)))
        }
        #expect(!ConflictDetector.validitiesMeet(.unknown(Self.futureValidity), .always, terms: [:]))
    }

    @Test func shareExportDropsWhatV1CannotExpress() throws {
        var (db, lessonID, taskID) = Self.futureDatabase()
        db.reminderRules[0].tier = .standard // not shared anyway
        let result = try ShareExport.makePayload(from: db, timetableID: db.timetables[0].id, includeTasks: true)
        let liveLessons = db.lessons.filter { $0.timetableID == db.timetables[0].id && !$0.isDeleted }
        #expect(result.payload.lessons.count == liveLessons.count - 1, "the lesson with an unknown validity is left out")
        let task = try #require(db.tasks.first { $0.id == taskID })
        let shared = try #require(result.payload.tasks.first { $0.title == task.title })
        #expect(shared.due == nil, "an unknown due kind is shared as 'no due date'")
        // The unknown density is a valid vocabulary string: kept, and reported by the recipient's validation.
        #expect(result.payload.timetable.density == Density(rawValue: "spacious"))
        #expect(result.warnings.contains { if case .valuesDropped(let count) = $0 { return count >= 2 } else { return false } })
        #expect(try result.payload.validate().contains(.unknownValue(field: "density", value: "spacious")))
        _ = lessonID
    }
}

/// Pre-freeze delta: `ISOWeekParityPolicy` is open; an unknown policy round-trips and is applied as `.strict`.
@Suite("Open vocabularies: ISO week parity policy")
struct ParityPolicyOpenVocabularyTests {
    @Test func unknownPolicyRoundTripsAndDegradesToStrict() throws {
        let json = #"{"kind":"isoWeekParity","offset":1,"policy":"schoolTerm"}"#
        let anchor = try Fixture.decode(WeekCycleAnchor.self, json)
        #expect(anchor == .isoWeekParity(policy: ISOWeekParityPolicy(rawValue: "schoolTerm"), offset: 1))
        #expect(try Fixture.json(anchor) == json)
        let unknown = ISOWeekParityPolicy(rawValue: "schoolTerm")
        #expect(!unknown.isKnown && unknown.effective == .strict && ISOWeekParityPolicy.continuous.effective == .continuous)
        var date = Fixture.date("2026-08-01")
        while date < Fixture.date("2028-01-01") {
            let week = date.isoWeek
            for length in 2...6 {
                #expect(WeekParity.cycleWeek(for: week, policy: unknown, offset: 1, length: length)
                        == WeekParity.cycleWeek(for: week, policy: .strict, offset: 1, length: length), "\(week) \(length)")
            }
            date = date.adding(days: 7)
        }
    }

    @Test func validationAndShareReportTheUnknownPolicy() throws {
        var db = Fixture.fullDatabase()
        let policy = ISOWeekParityPolicy(rawValue: "schoolTerm")
        db.timetables[0].rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: policy, offset: 0),
                                                         labels: ["A", "B"]))
        let issue = db.validate().first { $0.code == .unknownValue && $0.field == "rotation.anchor.policy" }
        #expect(issue?.severity == .info && issue?.value == "schoolTerm")
        #expect(db.isValid)
        let payload = try ShareExport.makePayload(from: db, timetableID: db.timetables[0].id, includeTasks: false).payload
        let decoded = try ShareCodec.decode(ShareCodec.encode(payload).text)
        #expect(decoded.timetable.rotation == db.timetables[0].rotation)
        #expect(try decoded.validate().contains(.unknownValue(field: "parityPolicy", value: "schoolTerm")))
    }
}
