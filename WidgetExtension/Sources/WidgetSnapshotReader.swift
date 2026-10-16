// Reads the app's widget snapshot from the App Group container (Phase 4 A). The group ID comes from the extension's
// own bundle ID (`AppGroup.identifier`: xtool re-signs both as XTL-<ID>…, ENVIRONMENT §2.1), the path and format from
// `WidgetSnapshotStore` (shared with the app's writer). No container (free team) or no / bad file → `nil` snapshot.
//
// Diagnostics: after each timeline the extension writes one line to the App Group defaults
// (`Phase0ProbeKeys.widgetSaw`), which Settings → Developer → Platform probes shows as "Widget read-back" — the
// on-device proof that the extension ran and what it saw (device checklist A1).
// APIs: FileManager.containerURL(forSecurityApplicationGroupIdentifier:), UserDefaults(suiteName:),
//       Bundle.path(forResource:ofType:), Bundle(path:), Bundle.localizedString(forKey:value:table:) (docs checked).
import Foundation
import TimetableCore
import TimetableUI

enum WidgetSnapshotReader {
    struct Result: Sendable {
        let groupID: String
        let containerAvailable: Bool
        let snapshot: WidgetSnapshot?
    }

    static func read() -> Result {
        let groupID = AppGroup.identifier(forBundleIdentifier: Bundle.main.bundleIdentifier)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return Result(groupID: groupID, containerAvailable: false, snapshot: nil)
        }
        return Result(groupID: groupID, containerAvailable: true, snapshot: WidgetSnapshotStore.read(container: container))
    }

    /// Writes what this timeline saw for the developer screen.
    static func recordRead(_ result: Result, now: Date, entries: Int) {
        guard result.containerAvailable, let defaults = UserDefaults(suiteName: result.groupID) else { return }
        let seen = result.snapshot.map { "snapshot v\($0.version) from \($0.generatedAt.ISO8601Format())" } ?? "no snapshot"
        defaults.set("Now & Next: \(seen), \(entries) entries, read \(now.ISO8601Format())", forKey: Phase0ProbeKeys.widgetSaw)
    }

    /// Catalog lookup in the app's UI language (`languageCode` = an .lproj of this bundle), else the system's.
    static func lookup(language: String?) -> LocalizedTextRenderer.Lookup {
        let path = language.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        return { key in
            let bundle = path.flatMap { Bundle(path: $0) } ?? Bundle.main
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
    }
}
