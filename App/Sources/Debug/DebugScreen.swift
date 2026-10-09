// Phase 0 probe screen: composes the probe sections owned by different agents.
// Developer-facing only; strings are verbatim on purpose (DEBUG builds only, not shipped).
//   PlatformProbesSection  -> Debug/PlatformProbes.swift  (env-ci-engineer)
//   ImportProbesSection    -> Debug/ImportProbes.swift    (import-ml-engineer)
//   AlarmProbesSection     -> Debug/AlarmProbes.swift     (notifications-engineer)
// `-TabulaScreen debug-<area>` shows a single area so CI simulator screenshots can cover every probe
// (simctl cannot scroll a List); `-TabulaScreen debug` shows everything. Routes: Debug/DebugRoutes.swift.
// Compiled only in DEBUG builds (PHASE2_PLAN §0.2); reachable from Settings → Developer.
#if DEBUG
import SwiftUI
import TimetableUI

/// Which probe areas a debug route shows.
enum DebugArea: String, CaseIterable, Sendable {
    case all = "debug"
    case platform = "debug-platform"
    case localization = "debug-localization"
    case macros = "debug-macros"
    case importing = "debug-import"
    case alarms = "debug-alarms"
}

struct DebugScreen: View {
    let area: DebugArea

    private var platformParts: Set<PlatformProbePart> {
        switch area {
        case .all: Set(PlatformProbePart.allCases)
        case .platform: [.platform, .appGroup]
        case .localization: [.localization]
        case .macros: [.macros]
        case .importing, .alarms: []
        }
    }

    private var showsImport: Bool { [.all, .importing].contains(area) }
    private var showsAlarms: Bool { [.all, .alarms].contains(area) }

    var body: some View {
        List {
            Section {
                let resolution = RouteRegistry.resolve(LaunchContext.options.screen).resolution
                let isUnknown: Bool = { if case .unknown = resolution { return true } else { return false } }()
                ProbeRow("Launch route (-TabulaScreen)", value: RouteTable.summary(resolution),
                         status: isUnknown ? .fail : .info)
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
#endif // DEBUG
