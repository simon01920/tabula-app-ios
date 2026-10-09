import Foundation
import Testing
@testable import TimetableUI

@Suite("LaunchOptions")
struct LaunchOptionsTests {
    private func parse(_ args: [String], debug: Bool = true) -> LaunchOptions {
        LaunchOptions(arguments: LaunchArguments(["app"] + args), allowsDeveloperOverrides: debug)
    }

    @Test func noArgumentsMeansRealStoreAndLiveDefaults() {
        let options = parse([])
        #expect(options == LaunchOptions())
    }

    @Test func seedNowZoneAndScreen() throws {
        let options = parse(["-TabulaScreen", "today", "-TabulaSeed", "secondary",
                             "-TabulaNow", "2026-10-13T10:20:00+02:00", "-TabulaTimeZone", "Europe/Bratislava"])
        #expect(options.screen == "today")
        #expect(options.seed == .secondary)
        #expect(options.clock == .fixed(Date(timeIntervalSince1970: 1_791_879_600)))
        #expect(options.timeZone?.identifier == "Europe/Bratislava")
        #expect(options.problems.isEmpty)
    }

    @Test(arguments: SeedKind.allCases)
    func everySeedParses(kind: SeedKind) {
        #expect(parse(["-TabulaSeed", kind.rawValue]).seed == kind)
    }

    @Test func instantFormats() {
        #expect(LaunchOptions.parseInstant("2026-10-13T08:20:00Z") == Date(timeIntervalSince1970: 1_791_879_600))
        #expect(LaunchOptions.parseInstant("2026-10-13T08:20:00.500Z") == Date(timeIntervalSince1970: 1_791_879_600.5))
        // Without an offset the instant would depend on the machine's zone: rejected.
        #expect(LaunchOptions.parseInstant("2026-10-13T10:20:00") == nil)
        #expect(LaunchOptions.parseInstant("13.10.2026") == nil)
    }

    @Test func liveClockAndProblems() {
        #expect(parse(["-TabulaSeed", "blank", "-TabulaNow", "live"]).clock == .live)
        let bad = parse(["-TabulaSeed", "college", "-TabulaNow", "tomorrow", "-TabulaTimeZone", "Mars/Olympus"])
        #expect(bad.seed == nil && bad.clock == nil && bad.timeZone == nil)
        #expect(bad.problems.count == 3)
        #expect(bad.problems[0].contains("college"))
    }

    @Test func clockAndZoneNeedTheInMemorySeed() {
        // Never with the real file store: fixed times would be stamped into persisted data and the HLC.
        let options = parse(["-TabulaNow", "2026-10-13T08:20:00Z", "-TabulaTimeZone", "Asia/Tokyo"])
        #expect(options.seed == nil && options.clock == nil && options.timeZone == nil)
        #expect(options.problems == ["-TabulaNow ignored without -TabulaSeed (only the in-memory seed store may use it)",
                                     "-TabulaTimeZone ignored without -TabulaSeed (only the in-memory seed store may use it)"])
    }

    @Test func releaseIgnoresDeveloperOverridesButKeepsTheScreen() {
        let options = parse(["-TabulaScreen", "today", "-TabulaSeed", "secondary", "-TabulaNow", "2026-10-13T08:20:00Z"],
                            debug: false)
        #expect(options.screen == "today")
        #expect(options.seed == nil)
        #expect(options.clock == nil)
        #expect(options.problems == ["-TabulaSeed ignored in Release builds", "-TabulaNow ignored in Release builds"])
    }
}

@Suite("RouteTable")
struct RouteTableTests {
    @Test func validIDs() {
        for id in ["today", "timetable.week", "editor.lesson", "debug-platform", "onboarding.step2", "a.b-c"] {
            #expect(RouteTable.isValidID(id), "\(id)")
        }
        for id in ["", "Today", "timetable..week", ".today", "today.", "2fa", "time table", "tímetable", "a_b"] {
            #expect(!RouteTable.isValidID(id), "\(id)")
        }
    }

    @Test func resolution() {
        let table = RouteTable(ids: ["today", "timetable.grid", "debug"])
        #expect(table.problems.isEmpty)
        #expect(table.resolve(nil) == .none)
        #expect(table.resolve("timetable.grid") == .matched(id: "timetable.grid", position: 1))
        #expect(table.resolve("timetable.gird") == .unknown(id: "timetable.gird"))
        #expect(RouteTable.summary(table.resolve("nope")) == "UNKNOWN \"nope\" → app shell")
    }

    @Test func duplicatesAndInvalidIDsAreReported() {
        let table = RouteTable(ids: ["today", "Today", "today", "settings", "today"])
        #expect(table.problems == [.invalidID(id: "Today", position: 1), .duplicate(id: "today", positions: [2, 4])])
        // The first registration wins.
        #expect(table.resolve("today") == .matched(id: "today", position: 0))
    }
}
