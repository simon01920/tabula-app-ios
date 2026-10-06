import Foundation
import Testing
@testable import TimetableCore

/// Orchestrator decisions 1 and 2: period lookup by ID, ordinal fallback, omission with a warning; span counts
/// lesson periods only and includes inner breaks.
@Suite("ScheduleResolver — period mapping")
struct PeriodMappingTests {
    private let d = Fixture.date

    @Test func aVariantWithOtherIDsMapsByLessonOrdinal() {
        var world = ScheduleWorld()
        let lesson = world.lesson(world.math, .tuesday, period: 2)
        let v: [Period.ID] = (0..<4).map { _ in world.ids.next() }
        let variant = world.bellSchedule([
            world.period(v[0], "07:30", "08:00"), world.period(world.ids.next(), "08:00", "08:05", kind: .breakTime),
            world.period(v[1], "08:05", "08:35"), world.period(v[2], "08:40", "09:10"), world.period(v[3], "09:15", "09:45"),
        ])
        world.override("2026-10-06", .useBellSchedule(variant))
        let resolution = world.resolution("2026-10-06")
        let entry = resolution.schedule.entries[0]
        #expect("\(entry.startTime)-\(entry.endTime)" == "08:05-08:35" && entry.periodID == v[1] && entry.periodNumber == 2)
        #expect(entry.status == .modified && resolution.reasons(for: entry.id) == [.timeChanged])
        #expect(resolution.warnings == [ResolutionWarning(kind: .periodMappedByOrdinal, date: d("2026-10-06"),
                                                          occurrenceID: .lesson(lesson, on: d("2026-10-06")), lessonID: lesson,
                                                          periodID: world.p[1])])
        #expect(resolution.schedule.conflicts.isEmpty)
    }

    @Test func aShorterVariantOmitsOrTruncates() {
        var world = ScheduleWorld()
        let late = world.lesson(world.math, .tuesday, period: 5)
        let long = world.lesson(world.physics, .tuesday, period: 3, span: 2)
        let variant = world.bellSchedule([world.period(world.ids.next(), "08:00", "08:40"),
                                          world.period(world.ids.next(), "08:45", "09:25"),
                                          world.period(world.ids.next(), "09:30", "10:10")])
        world.override("2026-10-06", .useBellSchedule(variant))
        let resolution = world.resolution("2026-10-06")
        let date = d("2026-10-06")
        #expect(resolution.schedule.entries.map(\.source) == [.lesson(long)])
        #expect(resolution.schedule.scheduleTimes == ["09:30-10:10"] && resolution.schedule.entries[0].periodSpan == 1)
        #expect(resolution.schedule.conflicts == [
            Conflict(kind: .periodNotInSchedule, date: date, occurrenceIDs: [.lesson(late, on: date)]),
            Conflict(kind: .spanExceedsSchedule, date: date, occurrenceIDs: [.lesson(long, on: date)]),
        ])
        #expect(Set(resolution.warnings.map(\.kind)) == [.periodNotInSchedule, .periodMappedByOrdinal, .spanExceedsSchedule])
        #expect(resolution.warnings.first { $0.kind == .periodNotInSchedule }?.lessonID == late)
    }

    @Test func idLookupBeatsTheOrdinal() {
        var world = ScheduleWorld()
        let zero: Period.ID = world.ids.next()
        world.bellSchedules[0].periods.append(world.period(zero, "07:10", "07:55")) // zero hour, default schedule only
        let first = world.lesson(world.math, .tuesday, period: 1)
        let early = world.lesson(world.physics, .weekday(.tuesday), .period(zero, span: 1))
        #expect(world.day("2026-10-06").scheduleTimes == ["07:10-07:55", "08:00-08:45"])
        #expect(world.day("2026-10-06").entry(first)?.periodNumber == 2, "the zero hour is lesson period 1")
        world.override("2026-10-06", .useBellSchedule(world.shortID))
        let resolution = world.resolution("2026-10-06")
        // P1 exists in "Short" by ID → its own slot; the zero hour falls back to the first lesson period.
        #expect(resolution.schedule.entry(first).map { "\($0.startTime)" } == "08:00")
        #expect(resolution.schedule.entry(early).map { "\($0.startTime)" } == "08:00")
        #expect(resolution.warnings.map(\.kind) == [.periodMappedByOrdinal] && resolution.warnings[0].lessonID == early)
        #expect(resolution.schedule.conflicts.map(\.kind) == [.overlap])
    }

    @Test func theWeekdaysNaturalScheduleIsAnOrdinalSource() {
        var world = ScheduleWorld()
        let f: [Period.ID] = (0..<3).map { _ in world.ids.next() }
        let fridayOnly = world.bellSchedule([world.period(f[0], "08:00", "08:40"), world.period(f[1], "08:50", "09:30"),
                                             world.period(f[2], "09:40", "10:20")])
        world.timetable.timeStructure = .bellSchedule(defaultID: world.normalID, perWeekday: [.friday: fridayOnly])
        let lesson = world.lesson(world.math, .weekday(.friday), .period(f[1], span: 1))
        #expect(world.day("2026-10-09").scheduleTimes == ["08:50-09:30"])
        world.override("2026-10-09", .useBellSchedule(world.normalID))
        let resolution = world.resolution("2026-10-09")
        #expect(resolution.schedule.scheduleTimes == ["08:55-09:40"] && resolution.schedule.entries[0].periodID == world.p[1])
        #expect(resolution.warnings.map(\.kind) == [.periodMappedByOrdinal] && resolution.warnings[0].lessonID == lesson)
    }

    @Test func spanCountsLessonPeriodsAndIncludesInnerBreaks() {
        var world = ScheduleWorld()
        world.lesson(world.math, .tuesday, period: 2, span: 2)   // P2 + B2 + P3
        world.lesson(world.physics, .tuesday, period: 4, span: 3) // P4 + lunch + P5 + P6
        world.lesson(world.english, .monday, period: 1, span: 0)  // invalid span → one period
        let tuesday = world.day("2026-10-06")
        #expect(tuesday.scheduleTimes == ["08:55-10:45", "10:55-14:00"] && tuesday.entries.map(\.periodSpan) == [2, 3])
        #expect(world.day("2026-10-05").scheduleTimes == ["08:00-08:45"])
    }

    @Test func lessonsInNonLessonPeriods() {
        var world = ScheduleWorld()
        let club = world.lesson(world.english, .weekday(.tuesday), .period(world.lunch, span: 1))
        let long = world.lesson(world.math, .weekday(.wednesday), .period(world.lunch, span: 2))
        let tuesday = world.day("2026-10-06")
        #expect(tuesday.scheduleTimes == ["11:40-12:20"] && tuesday.entry(club)?.periodNumber == nil)
        #expect(tuesday.entry(club)?.periodID == world.lunch && tuesday.entry(club)?.periodSpan == 1)
        #expect(world.day("2026-10-07").entry(long).map { "\($0.startTime)-\($0.endTime)" } == "11:40-13:05")
        // "Short" has no lunch period: no ordinal match → omitted.
        world.override("2026-10-06", .useBellSchedule(world.shortID))
        let resolution = world.resolution("2026-10-06")
        #expect(resolution.schedule.entries.isEmpty && resolution.warnings.map(\.kind) == [.periodNotInSchedule])
    }

    @Test func slotPlacementUnit() throws {
        let world = ScheduleWorld()
        let normal = BellScheduleIndex(world.bellSchedules[0])
        let short = BellScheduleIndex(world.bellSchedules[1])
        #expect(normal.periods.map(\.start) == normal.periods.map(\.start).sorted(), "periods are sorted by start")
        #expect(normal.lessonPositions.count == 6)
        #expect(normal.ordinal(of: world.lunch)?.kind == .lunch && normal.ordinal(of: world.lunch)?.ordinal == 0)
        #expect(normal.ordinal(of: world.p[3])?.kind == .lesson && normal.ordinal(of: world.p[3])?.ordinal == 3)
        let placed = try SlotPlacement.place(.period(world.p[5], span: 1), in: short, ordinalSources: [normal]).get()
        #expect(placed.startTime == Fixture.time("11:20") && placed.periodNumber == 6 && !placed.mappedByOrdinal)
        let failure = SlotPlacement.place(.period(world.p[0], span: 1), in: nil, ordinalSources: [normal])
        #expect(failure == .failure(.noBellSchedule))
        let backwards = SlotPlacement.place(.time(start: Fixture.time("09:00"), end: Fixture.time("09:00")), in: nil, ordinalSources: [])
        #expect(backwards == .failure(.invalidTimeRange))
        let unknown: Period.ID = EntityID(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!)
        #expect(SlotPlacement.place(.period(unknown, span: 1), in: short, ordinalSources: [normal]) == .failure(.periodNotInSchedule))
    }
}
