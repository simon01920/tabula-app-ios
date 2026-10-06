// Phase 0 debug screen: composes the probe sections owned by different agents.
// UNCOMPILED. Developer-facing only; strings are verbatim on purpose.
// NOTE: in Phase 0 this screen IS the app, so it also ships in Release archives/TestFlight builds.
// Phase 2 task: gate it behind `#if DEBUG` or a hidden toggle (docs/ENVIRONMENT.md §11).
//   PlatformProbesSection  -> Debug/PlatformProbes.swift  (env-ci-engineer)
//   ImportProbesSection    -> Debug/ImportProbes.swift    (import-ml-engineer)
//   AlarmProbesSection     -> Debug/AlarmProbes.swift     (notifications-engineer)
import SwiftUI

struct DebugScreen: View {
    var body: some View {
        List {
            PlatformProbesSection()
            ImportProbesSection()
            AlarmProbesSection()
        }
        .navigationTitle(Text(verbatim: "Tabula · Phase 0 probes"))
        // Environment probe: PlatformProbesSection reads this value back. In the macro variant
        // (TABULA_MACRO_PROBES) the key is declared with @Entry, so the injected string proves the macro
        // expanded; in the base variant it is a plain EnvironmentKey (no macro).
        .environment(\.phase0ProbeToken, PlatformProbeConstants.injectedEntryToken)
    }
}
