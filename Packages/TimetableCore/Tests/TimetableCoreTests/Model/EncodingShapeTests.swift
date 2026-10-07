import Foundation
import Testing
@testable import TimetableCore

/// Pins the persisted JSON shape of every tagged union and set-bearing type (DOMAIN_MODEL.md examples).
@Suite("Persisted JSON shapes")
struct EncodingShapeTests {
    private let id = "00000000-0000-4000-8000-000000000001"
    private var periodID: Period.ID { Period.ID(uuidString: id)! }

    @Test func timeStructure() throws {
        let schedule = BellSchedule.ID(uuidString: id)!
        let other = BellSchedule.ID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let value = TimeStructure.bellSchedule(defaultID: schedule, perWeekday: [.friday: other, .monday: schedule])
        #expect(try Fixture.json(value) == #"{"defaultID":"\#(id)","kind":"bellSchedule","perWeekday":{"1":"\#(id)","5":"00000000-0000-4000-8000-000000000002"}}"#)
        #expect(try Fixture.roundTrip(value) == value)
        #expect(try Fixture.json(TimeStructure.freeForm(defaultDurationMinutes: 90)) == #"{"defaultDurationMinutes":90,"kind":"freeForm"}"#)
        #expect(throws: DecodingError.self) {
            try Fixture.decode(TimeStructure.self, #"{"defaultID":"\#(id)","kind":"bellSchedule","perWeekday":{"8":"\#(id)"}}"#)
        }
        #expect(value.bellScheduleID(for: .friday) == other && value.bellScheduleID(for: .tuesday) == schedule)
        #expect(value.referencedBellScheduleIDs == [schedule, schedule, other])
    }

    @Test func slotsValidityAndOccurrence() throws {
        #expect(try Fixture.json(LessonSlot.period(periodID, span: 2)) == #"{"kind":"period","periodID":"\#(id)","span":2}"#)
        #expect(try Fixture.json(LessonSlot.time(start: Fixture.time("08:00"), end: Fixture.time("09:30")))
                == #"{"end":"09:30","kind":"time","start":"08:00"}"#)
        #expect(throws: DecodingError.self) { try Fixture.decode(LessonSlot.self, #"{"kind":"floating"}"#) }

        let t1 = Term.ID(uuidString: "00000000-0000-4000-8000-000000000009")!, t2 = Term.ID(uuidString: id)!
        #expect(try Fixture.json(LessonValidity.terms([t1, t2]))
                == #"{"kind":"terms","termIDs":["\#(id)","00000000-0000-4000-8000-000000000009"]}"#)
        #expect(try Fixture.json(LessonValidity.always) == #"{"kind":"always"}"#)
        #expect(try Fixture.json(LessonValidity.range(LocalDateRange(day: Fixture.date("2026-10-06"))))
                == #"{"kind":"range","range":{"end":"2026-10-06","start":"2026-10-06"}}"#)

        #expect(try Fixture.json(LessonOccurrenceRule(day: .weekday(.monday), cycleWeeks: [3, 1]))
                == #"{"cycleWeeks":[1,3],"day":{"kind":"weekday","weekday":1}}"#)
        #expect(try Fixture.json(LessonOccurrenceRule(day: .cycleDay(4))) == #"{"day":{"index":4,"kind":"cycleDay"}}"#)
        #expect(LessonOccurrenceRule.every(.friday) == LessonOccurrenceRule(day: .weekday(.friday)))
        #expect(DayKey.weekday(.sunday) < DayKey.cycleDay(1) && DayKey.cycleDay(1) < DayKey.cycleDay(2))
    }

    @Test func rotation() throws {
        let weekCycle = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .continuous, offset: 1)))
        #expect(try Fixture.json(weekCycle)
                == #"{"kind":"weekCycle","weekCycle":{"anchor":{"kind":"isoWeekParity","offset":1,"policy":"continuous"},"length":2}}"#)
        let reference = WeekCycleAnchor.referenceWeek(date: Fixture.date("2026-09-01"), cycleWeek: 1)
        #expect(try Fixture.json(reference) == #"{"cycleWeek":1,"date":"2026-09-01","kind":"referenceWeek"}"#)
        let dayCycle = RotationScheme.dayCycle(DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01"), anchorIndex: 2,
                                                        schoolDays: [.friday, .monday, .wednesday], skipsBreaks: false))
        #expect(try Fixture.json(dayCycle)
                == #"{"dayCycle":{"anchorDate":"2026-09-01","anchorIndex":2,"length":6,"schoolDays":[1,3,5],"skipsBreaks":false},"kind":"dayCycle"}"#)
        #expect(try Fixture.json(RotationScheme.none) == #"{"kind":"none"}"#)
        for value in [weekCycle, dayCycle, .none] { #expect(try Fixture.roundTrip(value) == value) }
        // Missing offset decodes as 0.
        #expect(try Fixture.decode(WeekCycleAnchor.self, #"{"kind":"isoWeekParity","policy":"strict"}"#)
                == .isoWeekParity(policy: .strict, offset: 0))
        #expect(throws: DecodingError.self) { try Fixture.decode(RotationScheme.self, #"{"kind":"lunar"}"#) }
    }

    @Test func overrideChanges() throws {
        let lessonID = Lesson.ID(uuidString: id)!
        let cases: [(OverrideChange, String)] = [
            (.cancelLesson(lessonID), #"{"kind":"cancelLesson","lessonID":"\#(id)"}"#),
            (.modifyLesson(lessonID, LessonPatch(room: "204", teacher: "")),
             #"{"kind":"modifyLesson","lessonID":"\#(id)","patch":{"room":"204","teacher":""}}"#),
            (.addLesson(OneOffLesson(subjectID: Subject.ID(uuidString: id)!, slot: .period(periodID, span: 1))),
             #"{"kind":"addLesson","lesson":{"bringList":[],"slot":{"kind":"period","periodID":"\#(id)","span":1},"subjectID":"\#(id)"}}"#),
            (.cancelDay(note: "Trip"), #"{"kind":"cancelDay","note":"Trip"}"#),
            (.cancelDay(note: nil), #"{"kind":"cancelDay"}"#),
            (.useBellSchedule(BellSchedule.ID(uuidString: id)!), #"{"bellScheduleID":"\#(id)","kind":"useBellSchedule"}"#),
            (.followDay(.weekday(.friday), cycleWeek: 2), #"{"cycleWeek":2,"day":{"kind":"weekday","weekday":5},"kind":"followDay"}"#),
            (.followDay(.cycleDay(3), cycleWeek: nil), #"{"day":{"index":3,"kind":"cycleDay"},"kind":"followDay"}"#),
        ]
        for (value, json) in cases {
            #expect(try Fixture.json(value) == json)
            #expect(try Fixture.decode(OverrideChange.self, json) == value)
        }
        #expect(LessonPatch().isEmpty && !LessonPatch(room: "").isEmpty)
    }

    @Test func unknownOverrideChangesArePreserved() throws {
        for json in [#"{"kind":"swapRooms","with":"B2","x":[1,2.5,true,null]}"#, #"{"note":"no kind"}"#, #""legacy""#, "42"] {
            let value = try Fixture.decode(OverrideChange.self, json)
            #expect(value.isUnknown, "\(json)")
            #expect(try Fixture.json(value) == json)
        }
        // A known kind with a broken payload is an error, not silently "unknown".
        #expect(throws: DecodingError.self) { try Fixture.decode(OverrideChange.self, #"{"kind":"cancelLesson"}"#) }
    }

    @Test func remindersAndTasks() throws {
        #expect(try Fixture.json(ReminderOffset.minutesBefore(15)) == #"{"kind":"minutesBefore","minutes":15}"#)
        #expect(try Fixture.json(ReminderOffset.daysBefore(1, at: Fixture.time("19:00"))) == #"{"at":"19:00","days":1,"kind":"daysBefore"}"#)
        let unknownOffset = try Fixture.decode(ReminderOffset.self, #"{"kind":"weekdayBefore","weekday":3}"#)
        #expect(unknownOffset == .unknown(.object(["kind": .string("weekdayBefore"), "weekday": .integer(3)])))
        #expect(try Fixture.json(unknownOffset) == #"{"kind":"weekdayBefore","weekday":3}"#)
        #expect(try Fixture.json(FollowUp.afterMinutes(120)) == #"{"kind":"afterMinutes","minutes":120}"#)
        #expect(try Fixture.json(FollowUp.nextMorning(at: Fixture.time("07:00"))) == #"{"at":"07:00","kind":"nextMorning"}"#)
        #expect(try Fixture.json(FollowUpOverride.inherit) == #"{"kind":"inherit"}"#)
        #expect(try Fixture.json(FollowUpOverride.none) == #"{"kind":"none"}"#)
        #expect(try Fixture.json(FollowUpOverride.custom(.afterMinutes(5))) == #"{"followUp":{"kind":"afterMinutes","minutes":5},"kind":"custom"}"#)
        #expect(try Fixture.json(ReminderOverride()) == #"{"followUp":{"kind":"inherit"},"isEnabled":true}"#)
        #expect(try Fixture.json(QuietHours(start: Fixture.time("22:00"), end: Fixture.time("07:00"))) == #"{"end":"07:00","start":"22:00"}"#)
        // Open union since the pre-freeze QA: an unknown kind round-trips; a known kind with a bad payload throws.
        let unknownFollowUp = try Fixture.decode(FollowUp.self, #"{"after":"lesson","kind":"never"}"#)
        #expect(unknownFollowUp == .unknown(.object(["after": .string("lesson"), "kind": .string("never")])))
        #expect(try Fixture.json(unknownFollowUp) == #"{"after":"lesson","kind":"never"}"#)
        #expect(throws: DecodingError.self) { try Fixture.decode(FollowUp.self, #"{"kind":"afterMinutes"}"#) }

        #expect(try Fixture.json(TaskDue.date(Fixture.date("2026-10-08"))) == #"{"date":"2026-10-08","kind":"date"}"#)
        #expect(try Fixture.json(TaskDue.dateTime(Fixture.date("2026-10-08"), Fixture.time("08:00")))
                == #"{"date":"2026-10-08","kind":"dateTime","time":"08:00"}"#)
        #expect(TaskDue.dateTime(Fixture.date("2026-10-08"), Fixture.time("08:00")).time == Fixture.time("08:00"))
        #expect(TaskDue.date(Fixture.date("2026-10-08")).time == nil)
        #expect(try Fixture.json(RepeatRule(frequency: .weekly, weekdays: [.friday, .monday]))
                == #"{"frequency":"weekly","interval":1,"weekdays":[1,5]}"#)
        #expect(try Fixture.json(LessonLink(lessonID: Lesson.ID(uuidString: id)!, date: Fixture.date("2026-10-07")))
                == #"{"date":"2026-10-07","lessonID":"\#(id)"}"#)
    }

    @Test func quietHoursContainment() {
        let overnight = QuietHours(start: Fixture.time("22:00"), end: Fixture.time("07:00"))
        #expect(overnight.spansMidnight)
        #expect(overnight.contains(Fixture.time("23:30")) && overnight.contains(Fixture.time("00:00")) && overnight.contains(Fixture.time("06:59")))
        #expect(!overnight.contains(Fixture.time("07:00")) && !overnight.contains(Fixture.time("21:59")))
        let daytime = QuietHours(start: Fixture.time("12:00"), end: Fixture.time("13:00"))
        #expect(daytime.contains(Fixture.time("12:00")) && !daytime.contains(Fixture.time("13:00")))
        #expect(!QuietHours(start: Fixture.time("12:00"), end: Fixture.time("12:00")).contains(Fixture.time("12:00")))
    }

    @Test func subjectAndTimetableFields() throws {
        #expect(try Fixture.json(SubjectSymbol.emoji("📐")) == #"{"kind":"emoji","value":"📐"}"#)
        #expect(try Fixture.json(SubjectSymbol.systemImage("function")) == #"{"kind":"systemImage","value":"function"}"#)
        #expect(try Fixture.json(FieldVisibility([.teacher, .room, LessonField(rawValue: "onlineLink")])) == #"["onlineLink","room","teacher"]"#)
        #expect(FieldVisibility.all.visibleFields.count == LessonField.knownValues.count)
        #expect(FieldVisibility([.room]).isVisible(.room) && !FieldVisibility([.room]).isVisible(.notes))
        // Sets inside entities are encoded sorted regardless of bucket layout.
        var days = Set<Weekday>(minimumCapacity: 64)
        for day in [Weekday.sunday, .wednesday, .monday] { days.insert(day) }
        let timetable = Timetable(id: Timetable.ID(uuidString: id)!, meta: Fixture.meta(), name: "T", enabledDays: days,
                                  timeStructure: .freeForm(defaultDurationMinutes: 45))
        #expect(try Fixture.json(timetable).contains(#""enabledDays":[1,3,7]"#))
        #expect(try Fixture.roundTrip(timetable) == timetable)
    }
}
