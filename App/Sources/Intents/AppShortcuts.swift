// App Shortcuts (Phase 4 B3): "What's next?" and "Add homework". App-target only (the intents behind App Shortcuts
// belong to the main app target; an app has exactly ONE `AppShortcutsProvider`, so the Phase 0 probe's provider was
// removed from App/Sources/Debug/IntentProbes.swift).
//
// Phrases: English in code (each contains `\(.applicationName)`, as App Shortcuts require); the 12 translations are in
// Resources/AppShortcuts.xcstrings (key = the English phrase with `${applicationName}`), the String Catalog an Apple
// Frameworks Engineer names for App Shortcut phrases ("create a String Catalog in your app target called
// `AppShortcuts`", developer.apple.com/forums/thread/803490). It is an app-target resource in project.yml; Xcode's
// metadata step reads phrases and their translations into `Metadata.appintents`. The xtool path has neither the
// metadata step nor a String Catalog compiler for it, so shortcuts are TestFlight-only (ENVIRONMENT §32).
// Titles, descriptions and short titles are keys in Resources/Localizable.xcstrings (`IntentL10nKeys`).
//
// "What's next?": background (`supportedModes = .background`), answers with a dialog: the Now & Next widget's spoken
// sentence for this moment (`WhatsNextAnswer`, the Today header's now/next state), in the app's language.
// "Add homework": foreground (`.foreground(.immediate)`), opens the Tasks tab with the new-task editor.
// APIs (iOS 26/27 SDK interface + docs, checked 2026-10-22): AppShortcutsProvider (iOS 16), AppShortcut
//   init(intent:phrases:shortTitle:systemImageName:) (iOS 17, non-deprecated overload), AppShortcutPhrase with
//   \(.applicationName), AppIntent.supportedModes + IntentModes .background / .foreground(.immediate) (iOS 26; replace
//   the deprecated openAppWhenRun), IntentResult.result(dialog:), ProvidesDialog, IntentDialog(_:).
import AppIntents
import Foundation
import TimetableUI

/// "What's next?": the current or next lesson, spoken / shown by Siri, Shortcuts or Spotlight.
struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource { "intent.whatsNext.title" }
    static var description: IntentDescription? { IntentDescription("intent.whatsNext.description") }
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await Self.answer()
        // An interpolated resource: its key ("%@") is not in the catalog, so the rendered sentence is shown as is.
        return .result(dialog: IntentDialog(LocalizedStringResource("\(answer)")))
    }

    @MainActor
    private static func answer() async -> String {
        // No services (should not happen in the app process): say "Open Tabula" rather than nothing (final QA m4).
        guard let services = await IntentHost.services() else { return String(localized: "widget.open.title") }
        return await services.whatsNextAnswer()
    }
}

/// "Add homework": opens the app on the new-task editor.
struct AddHomeworkIntent: AppIntent {
    static var title: LocalizedStringResource { "intent.addHomework.title" }
    static var description: IntentDescription? { IntentDescription("intent.addHomework.description") }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        await Self.open()
        return .result()
    }

    @MainActor
    private static func open() async {
        await IntentHost.services()?.openNewTask()
    }
}

struct TabulaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: [
                "What's next in \(.applicationName)?",
                "What's my next lesson in \(.applicationName)?",
            ],
            shortTitle: "intent.whatsNext.shortTitle",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: AddHomeworkIntent(),
            phrases: [
                "Add homework in \(.applicationName)",
                "Add a task in \(.applicationName)",
            ],
            shortTitle: "intent.addHomework.shortTitle",
            systemImageName: "plus.circle"
        )
    }
}
