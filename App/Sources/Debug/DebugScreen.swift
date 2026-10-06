// Phase 0 debug screen: composes the probe sections owned by different agents.
// Developer-facing only; strings are verbatim on purpose.
// NOTE: in Phase 0 this screen IS the app, so it also ships in Release archives/TestFlight builds.
// Phase 2 task: gate it behind `#if DEBUG` or a hidden toggle (docs/ENVIRONMENT.md §11).
//   PlatformProbesSection  -> Debug/PlatformProbes.swift  (env-ci-engineer)
//   ImportProbesSection    -> Debug/ImportProbes.swift    (import-ml-engineer)
//   AlarmProbesSection     -> Debug/AlarmProbes.swift     (notifications-engineer)
// `-TabulaScreen debug-<area>` shows a single area so CI simulator screenshots can cover every probe
// (simctl cannot scroll a List); `-TabulaScreen debug` (default) shows everything.
import SwiftUI
import TimetableUI

struct DebugScreen: View {
    /// How this screen was reached (`-TabulaScreen`); shown first so CI screenshots prove the router works.
    let launchRoute: ScreenRoute<AppScreen>

    private var platformParts: Set<PlatformProbePart> {
        switch launchRoute.screen {
        case .debug: Set(PlatformProbePart.allCases)
        case .debugPlatform: [.platform, .appGroup]
        case .debugLocalization: [.localization]
        case .debugMacros: [.macros]
        case .debugImport, .debugAlarms: []
        }
    }

    private var showsImport: Bool { [.debug, .debugImport].contains(launchRoute.screen) }
    private var showsAlarms: Bool { [.debug, .debugAlarms].contains(launchRoute.screen) }

    var body: some View {
        List {
            Section {
                ProbeRow(
                    "Launch route (-TabulaScreen)",
                    value: launchRoute.summary,
                    status: launchRoute.isUnknown ? .fail : .info
                )
            } header: {
                Text(verbatim: "Launch")
            }
            if !platformParts.isEmpty {
                PlatformProbesSection(parts: platformParts)
            }
            if showsImport {
                ImportProbesSection()
            }
            if showsAlarms {
                AlarmProbesSection()
            }
        }
        .navigationTitle(Text(verbatim: "Tabula · Phase 0 probes"))
        // Environment probe: PlatformProbesSection reads this value back. In the macro variant
        // (TABULA_MACRO_PROBES) the key is declared with @Entry, so the injected string proves the macro
        // expanded; in the base variant it is a plain EnvironmentKey (no macro).
        .environment(\.phase0ProbeToken, PlatformProbeConstants.injectedEntryToken)
    }
}
