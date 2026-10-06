// Minimal watchOS app. XcodeGen/CI path ONLY — xtool cannot build or sign watchOS apps
// (its Darwin SDK defines only iOS/macOS triples and its packer only emits iPhoneOS bundles).
// Embedded in the iOS app (TabulaApp.app/Watch/TabulaWatch.app) by project.yml. UNCOMPILED.
// Target: Apple Watch Series 7 = S7 = arm64_32 → keep WATCHOS_DEPLOYMENT_TARGET 26.x and do not override
// ARCHS (CI asserts `lipo -archs` contains arm64_32). No macros used here.
// APIs (docs checked): SwiftUI.App, WindowGroup, List, Text(verbatim:).
import SwiftUI
import TimetableCore
import TimetableUI

@main
struct TabulaWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchProbeView()
        }
    }
}

struct WatchProbeView: View {
    var body: some View {
        List {
            ProbeRow("Tabula watch probe", value: "Phase 0")
            ProbeRow("Core schema", value: "v\(TimetableCoreInfo.schemaVersion)")
            ProbeRow("UI module", value: TimetableUIInfo.moduleName)
            ProbeRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "nil")
        }
    }
}
