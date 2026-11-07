import Foundation
import Testing
@testable import TimetableCore

/// Phase 10 C8 (overrides sorted once in `init`) and C5 (`DayResolution.reasons(for:)` as a lookup): output-
/// identical to the former per-date sort and linear search, kept here as references.
@Suite("ScheduleResolver — Phase 10 equivalence")
struct ScheduleResolverPhase10Tests {
    static let dates = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"].map(Fixture.date)
    static let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// The pre-Phase-10 order, computed per resolved date.
    static func referenceOrder(_ overrides: [ScheduleOverride]) -> [ScheduleOverride] {
        overrides.sorted { ($0.meta.updatedAt, $0.id) < ($1.meta.updatedAt, $1.id) }
    }

    /// The pre-Phase-10 `reasons(for:)`.
    static func referenceReasons(_ resolution: DayResolution, _ id: OccurrenceID) -> [ModificationReason] {
        resolution.changes.first { $0.occurrenceID == id }?.reasons ?? []
    }

    /// A week with three lessons and 4…24 random overrides of every kind; `updatedAt` takes only three values,
    /// so ties are decided by the ID, and one override is a tombstone.
    static func randomWorld(_ rng: inout TestRNG) -> ScheduleWorld {
        var world = ScheduleWorld()
        let targets = [world.lesson(world.math, .monday, period: 1), world.lesson(world.english, .tuesday, period: 2),
                       world.lesson(world.physics, .wednesday, period: 3), world.lesson(world.math, .friday, period: 2)]
        for index in 0..<Int.random(in: 4...24, using: &rng) {
            let date = dates.randomElement(using: &rng)!
            let millis = ScheduleWorld.baseMillis + Int64.random(in: 0...2, using: &rng)
            let target = targets.randomElement(using: &rng)!
            let change: OverrideChange
            switch Int.random(in: 0..<6, using: &rng) {
            case 0: change = .followDay(.weekday(weekdays.randomElement(using: &rng)!), cycleWeek: nil)
            case 1: change = .useBellSchedule(Bool.random(using: &rng) ? world.normalID : world.shortID)
            case 2: change = .cancelDay(note: nil)
            case 3: change = .cancelLesson(target)
            case 4: change = .modifyLesson(target, LessonPatch(room: "R\(index % 3)"))
            default: change = .addLesson(OneOffLesson(subjectID: world.physics, slot: .period(world.p[index % 6], span: 1)))
            }
            world.override(date.isoString, change, updatedAt: millis)
        }
        let tombstoneID: ScheduleOverride.ID = world.ids.next()
        world.overrides.append(ScheduleOverride(
            id: tombstoneID,
            meta: EntityMeta(createdAt: ScheduleWorld.meta().createdAt, updatedAt: ScheduleWorld.meta().updatedAt,
                             isDeleted: true),
            timetableID: world.timetable.id, date: dates[0], change: .cancelDay(note: nil)))
        return world
    }

    @Test func overridesAreSortedOnceInPrecedenceOrder() {
        var rng = TestRNG(seed: 0xC8)
        for _ in 0..<60 {
            let world = Self.randomWorld(&rng)
            let resolver = world.resolver
            for date in Self.dates {
                let live = world.overrides.filter { !$0.isDeleted && $0.timetableID == world.timetable.id && $0.date == date }
                #expect((resolver.overridesByDate[date] ?? []).map(\.id) == Self.referenceOrder(live).map(\.id))
            }
        }
    }

    @Test func resolutionsDoNotDependOnInputOrder() {
        var rng = TestRNG(seed: 0xC80)
        for _ in 0..<40 {
            let world = Self.randomWorld(&rng)
            let resolver = world.resolver
            let shuffled = ScheduleResolver(timetable: world.timetable, subjects: world.subjects,
                                            bellSchedules: world.bellSchedules, lessons: world.lessons, terms: world.terms,
                                            breaks: world.breaks, overrides: world.overrides.shuffled(using: &rng),
                                            context: world.context)
            for date in Self.dates {
                #expect(resolver.resolution(for: date) == shuffled.resolution(for: date))
            }
        }
    }

    @Test func reasonsLookupEqualsLinearSearch() {
        var rng = TestRNG(seed: 0xC5)
        var withReasons = 0
        for _ in 0..<60 {
            let world = Self.randomWorld(&rng)
            for date in Self.dates {
                let resolution = world.resolver.resolution(for: date)
                let ids = resolution.schedule.entries.map(\.id) + resolution.changes.map(\.occurrenceID)
                    + [OccurrenceID.lesson(world.lessons[0].id, on: date.adding(days: 30))]
                for id in ids {
                    #expect(resolution.reasons(for: id) == Self.referenceReasons(resolution, id))
                    if !resolution.reasons(for: id).isEmpty { withReasons += 1 }
                }
            }
        }
        #expect(withReasons > 0)
    }

    @Test func reasonsIndexFollowsMutationsAndKeepsTheFirstRecord() throws {
        let world = ScheduleWorld()
        let date = Self.dates[0]
        var ids = SequentialIDGenerator(namespace: 0xC5)
        let lessonA: Lesson.ID = ids.next()
        let lessonB: Lesson.ID = ids.next()
        let a = OccurrenceID.lesson(lessonA, on: date)
        let b = OccurrenceID.lesson(lessonB, on: date)
        var resolution = DayResolution(schedule: world.day(date.isoString),
                                       changes: [OccurrenceChanges(occurrenceID: a, reasons: [.roomChanged]),
                                                 OccurrenceChanges(occurrenceID: a, reasons: [.timeChanged])])
        #expect(resolution.reasons(for: a) == [.roomChanged] && resolution.reasons(for: b) == [])
        resolution.changes.append(OccurrenceChanges(occurrenceID: b, reasons: [.teacherChanged]))
        #expect(resolution.reasons(for: b) == [.teacherChanged])
        resolution.changes[0].reasons = [.notesChanged]
        #expect(resolution.reasons(for: a) == [.notesChanged])
        resolution.changes = []
        #expect(resolution.reasons(for: a) == [] && resolution.reasons(for: b) == [])

        // Equality, hashing and coding see the stored fields only, as the synthesised conformances did.
        let original = DayResolution(schedule: world.day(date.isoString), naturalDayKey: .weekday(.monday),
                                     changes: [OccurrenceChanges(occurrenceID: a, reasons: [.roomChanged])])
        var rebuilt = DayResolution(schedule: world.day(date.isoString), naturalDayKey: .weekday(.monday))
        rebuilt.changes = original.changes
        #expect(rebuilt == original && rebuilt.hashValue == original.hashValue)
        let decoded = try Fixture.roundTrip(original)
        #expect(decoded == original && decoded.reasons(for: a) == [.roomChanged])
        let json = try Fixture.json(original)
        #expect(!json.contains("reasonsByOccurrence") && json.contains("\"changes\"") && json.contains("\"naturalDayKey\""))
        #expect(!json.contains("\"followDayOverrideID\""), "nil optionals stay absent, as with synthesised coding")
    }
}
