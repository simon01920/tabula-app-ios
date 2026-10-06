// Launch-argument screen router: `-TabulaScreen <id>` picks the first screen, so the CI iOS Simulator job
// (.github/workflows/ui-screenshots.yml) can screenshot any screen without UI tests, and so can a human via
// `xcrun simctl launch booted sk.simondev.tabula -TabulaScreen <id>` or Xcode scheme arguments.
// Parsing (LaunchArguments / ScreenRoute) is pure Swift in TimetableUI and unit-tested on Linux.
//
// HOW PHASE 2 SCREENS REGISTER (one place, two lines):
//   1. add a case with a stable kebab-case id:          case timetableWeek = "timetable-week"
//   2. map it in `AppRootView.body`:                    case .timetableWeek: TimetableWeekScreen(store: …)
//   3. add the id to the `screens` input/default of ui-screenshots.yml so CI captures it.
//   Screens needing data must render from a deterministic fixture (e.g. a demo timetable from TimetableCore)
//   when launched this way, never from whatever happens to be on the simulator.
// No macros here (base variant, CLAUDE.md rule 5): the route is a `let`, not @State.
import Foundation
import SwiftUI
import TimetableUI

/// Every screen that can be opened directly with `-TabulaScreen <rawValue>`.
enum AppScreen: String, CaseIterable, Sendable {
    /// Phase 0 probe screen with every section (also the default until Phase 2 adds the real root screen).
    case debug
    // One probe area per screen: `simctl` cannot scroll, so CI screenshots each area separately.
    case debugPlatform = "debug-platform"
    case debugLocalization = "debug-localization"
    case debugMacros = "debug-macros"
    case debugImport = "debug-import"
    case debugAlarms = "debug-alarms"
}

extension ScreenRoute where Screen == AppScreen {
    /// Route for this process, read once at launch.
    static func forCurrentProcess() -> ScreenRoute<AppScreen> {
        ScreenRoute(arguments: LaunchArguments(ProcessInfo.processInfo.arguments), fallback: .debug)
    }
}

struct AppRootView: View {
    let route: ScreenRoute<AppScreen>

    var body: some View {
        NavigationStack {
            switch route.screen {
            case .debug, .debugPlatform, .debugLocalization, .debugMacros, .debugImport, .debugAlarms:
                DebugScreen(launchRoute: route)
            }
        }
    }
}
