import Foundation
import Testing
@testable import TimetableCore

/// `Timetable.rotationWeekStart` (pre-freeze QA): rotation arithmetic uses the timetable's persisted week start,
/// never the device's/user's current one.
@Suite("Rotation week start")
struct RotationWeekStartTests {
    private static let isoParity = RotationScheme.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0)))

    private func world(_ rotation: RotationScheme, rotationWeekStart: Weekday) -> ScheduleWorld {
        var world = ScheduleWorld(rotation: rotation, enabledDays: Set(Weekday.allCases))
        world.timetable.rotationWeekStart = rotationWeekStart
        return world
    }

    private func context(_ firstWeekday: Weekday) -> CalendarContext {
        CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: firstWeekday)
    }

    /// The QA example: Sunday 2026-10-11 (ISO W41, odd) with ISO-parity weeks gets the same cycle week whether the
    /// device week starts on Monday or Sunday.
    @Test func qaExampleSundayIsIndependentOfTheDeviceWeekStart() {
        let sunday = Fixture.date("2026-10-11")
        #expect(sunday.weekday == .sunday && sunday.isoWeek.week == 41)
        let monday = world(Self.isoParity, rotationWeekStart: .monday)
        let weeks = Weekday.allCases.map { monday.resolver(context: context($0)).day(sunday).cycleWeek }
        #expect(weeks == Array(repeating: 1, count: 7), "W41 is odd → week 1 for every device week start")

        // A Sun–Thu school persists a Sunday rotation week start: that Sunday opens the W42 school week.
        let sundaySchool = world(Self.isoParity, rotationWeekStart: .sunday)
        let sundayWeeks = Weekday.allCases.map { sundaySchool.resolver(context: context($0)).day(sunday).cycleWeek }
        #expect(sundayWeeks == Array(repeating: 2, count: 7))
    }

    @Test(arguments: [Weekday.monday, .sunday, .saturday])
    func everyRotationKindIgnoresTheDeviceWeekStart(rotationWeekStart: Weekday) {
        let schemes: [RotationScheme] = [
            Self.isoParity,
            .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .continuous, offset: 1))),
            .weekCycle(WeekCycle(length: 3, anchor: .referenceWeek(date: Fixture.date("2026-09-01"), cycleWeek: 2))),
        ]
        for scheme in schemes {
            let world = world(scheme, rotationWeekStart: rotationWeekStart)
            let expected = RotationResolver(timetable: world.timetable)
            let rotations = Weekday.allCases.map { world.resolver(context: context($0)).rotation }
            for date in LocalDateRange(start: Fixture.date("2026-08-20"), end: Fixture.date("2027-02-10")).days {
                let byDevice = Set(rotations.map { $0.cycleWeek(on: date) })
                #expect(byDevice == [expected.cycleWeek(on: date)], "\(scheme) \(date)")
            }
        }
    }

    /// The worked example of DOMAIN_MODEL §4.3 (normative): if this fails, the document or the code changed.
    @Test func normativeExampleOfDomainModel() {
        func week(_ year: Int, _ number: Int) -> ISOWeek {
            // The Thursday of an ISO week always lies in its ISO year: start from 4 Jan (always W01).
            let jan4 = LocalDate(year: year, month: 1, day: 4)!
            return jan4.adding(days: 7 * (number - 1)).isoWeek
        }
        func strict(_ w: ISOWeek) -> Int { WeekParity.cycleWeek(for: w, policy: .strict, offset: 0, length: 2) }
        func continuous(_ w: ISOWeek) -> Int { WeekParity.cycleWeek(for: w, policy: .continuous, offset: 0, length: 2) }
        #expect([week(2026, 52), week(2026, 53), week(2027, 1), week(2027, 2)].map(strict) == [2, 1, 1, 2])
        #expect(week(2026, 36).monday == Fixture.date("2026-08-31"))
        #expect([week(2026, 36), week(2026, 53), week(2027, 1), week(2027, 34), week(2027, 35)].map(continuous) == [2, 1, 2, 1, 1])
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: 1, length: 2) == 2, "offset 1 swaps A/B")
        #expect(WeekParity.cycleWeek(for: week(2027, 1), policy: .strict, offset: 0, length: 3) == 1, "restarts at W01")
        for profile in UserProfile.knownValues + [UserProfile(rawValue: "teacher")] {
            for region in ["SK", "CZ", "US", nil] as [String?] {
                #expect(WeekParity.defaultPolicy(for: profile, regionCode: region) == .strict)
            }
        }
    }

    @Test func missingKeyDecodesAsMonday() throws {
        var tree = try JSONValue(encoding: Fixture.fullDatabase())
        let timetables = try #require(SyncJSONPatch.get(tree, [.key("timetables")]))
        guard case .array(let items) = timetables else { Issue.record("timetables"); return }
        for index in items.indices {
            #expect(SyncJSONPatch.get(tree, [.key("timetables"), .index(index), .key("rotationWeekStart")]) == .integer(1))
            guard case .object(var object)? = SyncJSONPatch.get(tree, [.key("timetables"), .index(index)]) else { continue }
            object["rotationWeekStart"] = nil
            tree = SyncJSONPatch.set(tree, [.key("timetables"), .index(index)], .object(object))
        }
        let db = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: TabulaJSON.makeEncoder().encode(tree))
        #expect(db.timetables.allSatisfy { $0.rotationWeekStart == .monday })
        #expect(db.unknownFields.isEmpty)

        var sunday = Fixture.fullDatabase()
        sunday.timetables[0].rotationWeekStart = .sunday
        #expect(try Fixture.roundTrip(sunday).timetables[0].rotationWeekStart == .sunday)
    }

    @Test func onboardingFixesTheWeekStartAtCreation() {
        func timetable(override: Weekday?, locale: Weekday?) -> Timetable {
            var ids = SequentialIDGenerator(namespace: 3)
            var clock = TestClock()
            var answers = OnboardingAnswers(profile: .secondary, timetableName: "S", bellScheduleName: "N",
                                            weekStartOverride: override)
            if let locale { answers.localeFirstWeekday = locale }
            return OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: Fixture.now).timetables[0]
        }
        #expect(timetable(override: nil, locale: nil).rotationWeekStart == .monday)
        #expect(timetable(override: nil, locale: .sunday).rotationWeekStart == .sunday)
        #expect(timetable(override: .saturday, locale: .sunday).rotationWeekStart == .saturday)
    }

    @Test func shareCarriesTheWeekStartAndDefaultsToMonday() throws {
        // Omitted when Monday (the golden v1 payloads stay byte-identical) …
        let minimal = ShareFixture.minimalPayload()
        #expect(!(try ShareFixture.unvalidatedJSON(minimal)).contains("\"ws\""))
        let (importedMonday, mondayID) = try ShareFixture.importIntoEmptyDatabase(minimal)
        #expect(importedMonday.timetables.first { $0.id == mondayID }?.rotationWeekStart == .monday)

        // … written as an ISO weekday otherwise, and materialised on import.
        var db = Fixture.fullDatabase()
        db.timetables[0].rotationWeekStart = .sunday
        let payload = try ShareFixture.payload(db, db.timetables[0].id)
        #expect(payload.timetable.rotationWeekStart == .sunday)
        let json = try ShareFixture.unvalidatedJSON(payload)
        #expect(json.contains("\"ws\":7"))
        let decoded = try ShareCodec.decode(ShareCodec.encode(payload).text)
        #expect(decoded.timetable.rotationWeekStart == .sunday)
        let (imported, id) = try ShareFixture.importIntoEmptyDatabase(decoded)
        #expect(imported.timetables.first { $0.id == id }?.rotationWeekStart == .sunday)

        // An invalid weekday is malformed, not a crash.
        let bad = json.replacingOccurrences(of: "\"ws\":7", with: "\"ws\":9")
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: bad)) != nil)
    }

    @Test func weekGridFollowsTheDisplayWeekAndLabelsItsMiddleDay() {
        let world = world(.weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0), labels: ["A", "B"])),
                          rotationWeekStart: .monday)
        // Device week starts on Sunday: the grid shows Sun 11 … Sat 17 Oct; Sunday is still W41 (A), the rest W42 (B).
        let resolver = world.resolver(context: context(.sunday))
        let grid = GridLayout.week(containing: Fixture.date("2026-10-13"), resolver: resolver)
        #expect(grid.weekStart == Fixture.date("2026-10-11"))
        #expect(grid.cycleWeek == 2 && grid.cycleLabel == "B")
        #expect(grid.columns.first?.date == Fixture.date("2026-10-11") && grid.columns.first?.cycleWeek == 1)
        #expect(grid.columns.dropFirst().allSatisfy { $0.cycleWeek == 2 })
        #expect(GridLayout.displayWeekStart(today: Fixture.date("2026-10-13"), resolver: resolver) == Fixture.date("2026-10-11"))
    }
}
