import Testing
@testable import TimetableUI

private enum TestScreen: String, Sendable, Equatable {
    case debug
    case timetableWeek = "timetable-week"
}

@Suite("LaunchArguments")
struct LaunchArgumentsTests {
    @Test func valueAfterFlag() {
        let args = LaunchArguments(["/path/TabulaApp", "-TabulaScreen", "debug"])
        #expect(args.value(for: "TabulaScreen") == "debug")
    }

    @Test func missingFlagIsNil() {
        #expect(LaunchArguments(["/path/TabulaApp"]).value(for: "TabulaScreen") == nil)
    }

    @Test func flagWithoutValueIsNil() {
        #expect(LaunchArguments(["app", "-TabulaScreen"]).value(for: "TabulaScreen") == nil)
        #expect(LaunchArguments(["app", "-TabulaScreen", "-Other", "x"]).value(for: "TabulaScreen") == nil)
    }

    @Test func lastOccurrenceWins() {
        let args = LaunchArguments(["app", "-TabulaScreen", "a", "-TabulaScreen", "b"])
        #expect(args.value(for: "TabulaScreen") == "b")
    }

    @Test func otherFlagsAreIgnored() {
        let args = LaunchArguments(["app", "-AppleLanguages", "(sk)", "-TabulaScreen", "timetable-week"])
        #expect(args.value(for: "TabulaScreen") == "timetable-week")
        #expect(args.value(for: "AppleLanguages") == "(sk)")
    }

    @Test func flagNameMustMatchExactly() {
        #expect(LaunchArguments(["app", "-TabulaScreenX", "debug"]).value(for: "TabulaScreen") == nil)
    }
}

@Suite("ScreenRoute")
struct ScreenRouteTests {
    @Test func knownScreen() {
        let route = ScreenRoute(arguments: LaunchArguments(["app", "-TabulaScreen", "timetable-week"]),
                                fallback: TestScreen.debug)
        #expect(route.screen == .timetableWeek)
        #expect(route.isUnknown == false)
        #expect(route.summary == "requested \"timetable-week\" → timetable-week")
    }

    @Test func noArgumentUsesFallback() {
        let route = ScreenRoute(arguments: LaunchArguments(["app"]), fallback: TestScreen.debug)
        #expect(route.screen == .debug)
        #expect(route.requested == nil)
        #expect(route.isUnknown == false)
        #expect(route.summary == "default → debug")
    }

    @Test func unknownScreenFallsBackVisibly() {
        let route = ScreenRoute(arguments: LaunchArguments(["app", "-TabulaScreen", "nope"]), fallback: TestScreen.debug)
        #expect(route.screen == .debug)
        #expect(route.isUnknown)
        #expect(route.summary == "UNKNOWN \"nope\" → fallback debug")
    }
}
