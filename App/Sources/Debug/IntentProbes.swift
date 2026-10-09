// Phase 0 App Intents probe. COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629).
// Questions it answers on device:
//   1. Does an AppIntent + AppShortcutsProvider compile and link on this build path?
//   2. Does the shortcut appear in the Shortcuts app / Spotlight? That needs
//      Metadata.appintents (extract.actionsdata), produced by Apple's macOS-only
//      `appintentsmetadataprocessor`. xtool PR #217 (pure-Swift generator) was closed unmerged,
//      so on the xtool path we EXPECT "compiles, but not listed in Shortcuts"; on the XcodeGen/CI
//      path it should be listed. Record the result in docs/ENVIRONMENT.md.
// APIs (docs checked): AppIntent, title, description (IntentDescription?), perform(),
//   IntentResult.result(dialog:), ProvidesDialog, IntentDialog, AppShortcutsProvider.appShortcuts,
//   AppShortcut.init(intent:phrases:shortTitle:systemImageName:) (iOS 17+, non-deprecated overload),
//   AppShortcutPhrase with \(.applicationName). `openAppWhenRun` is deprecated in iOS 26: not used.
// Compiled only in DEBUG builds (PHASE2_PLAN §0.2): Release archives/TestFlight contain no probe code.
#if DEBUG
import AppIntents
import Foundation
import TimetableCore
import TimetableUI

struct Phase0ProbeIntent: AppIntent {
    // Computed (not stored) static properties: avoids Swift 6 global-state diagnostics while staying
    // literal so Xcode's metadata extraction can read them.
    static var title: LocalizedStringResource { "probe.intent.title" }
    static var description: IntentDescription? { IntentDescription("probe.intent.description") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Self.recordRun()
        return .result(dialog: "probe.intent.dialog")
    }

    /// Side effect shared with the in-app button: stores the run time in the App Group so the
    /// debug screen can show runs triggered from the Shortcuts app as well.
    static func recordRun() {
        let group = AppGroup.identifier(forBundleIdentifier: Bundle.main.bundleIdentifier)
        UserDefaults(suiteName: group)?.set(Date.now.timeIntervalSince1970, forKey: Phase0ProbeKeys.intentRun)
    }
}

struct Phase0AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: Phase0ProbeIntent(),
            phrases: ["Run \(.applicationName) probe"],
            shortTitle: "probe.intent.shortTitle",
            systemImageName: "checkmark.seal"
        )
    }
}

/// Runs the intent's `perform()` in-process, off the main actor, so the opaque result value never
/// crosses an isolation boundary (keeps Swift 6 strict concurrency happy).
enum IntentProbe {
    static func performInProcess() async -> Result<Void, Error> {
        let task = Task.detached { () async throws -> Void in
            _ = try await Phase0ProbeIntent().perform()
        }
        do {
            try await task.value
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
#endif // DEBUG
