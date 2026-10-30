// The watch's offline snapshot cache (Phase 5 W1), compiled into BOTH watch targets: the watch app writes it when the
// iPhone sends a snapshot, the complication extension reads it. Same path and format as the iPhone widgets
// (`WidgetSnapshotStore`: <App Group>/Widgets/widget-snapshot.json, atomic writes, reads never throw).
//
// Why an App Group: a WidgetKit extension runs in its own process and sandbox; Apple's way to share files between an
// app and its extension is an App Group container ("You can also use an app group to share data between an app
// extension … and its host app", https://developer.apple.com/documentation/xcode/configuring-app-groups, watchOS listed).
// The group is the iPhone's (`AppGroup.identifier` → canonical for the watch bundle IDs; Config/TabulaWatch.entitlements).
// The watch ships only through TestFlight (paid account, RISKS #37), so the free team's missing App Group (RISKS #47)
// does not apply; without a container the app shows "Open Tabula on your iPhone".
// APIs: FileManager.containerURL(forSecurityApplicationGroupIdentifier:), Bundle.path(forResource:ofType:),
//       Bundle.localizedString(forKey:value:table:) (docs checked 2026-10-30).
import Foundation
import TimetableCore
import TimetableUI

enum WatchCache {
    static var container: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier(forBundleIdentifier: Bundle.main.bundleIdentifier))
    }

    /// The cached snapshot, or `nil` (none yet, no container, unreadable or newer format).
    static func read() -> WidgetSnapshot? {
        container.flatMap { WidgetSnapshotStore.read(container: $0) }
    }

    /// Stores validated snapshot bytes; `false` when they equal the cached file (nothing to reload).
    static func store(_ data: Data) throws -> Bool {
        guard let container else { throw CocoaError(.fileNoSuchFile) }
        if (try? Data(contentsOf: WidgetSnapshotStore.fileURL(container: container))) == data { return false }
        try WidgetSnapshotStore.write(data, container: container)
        return true
    }

    /// Catalog lookup in the iPhone app's UI language (an .lproj of this bundle), else the watch's.
    static func lookup(language: String?) -> LocalizedTextRenderer.Lookup {
        let path = language.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        return { key in
            let bundle = path.flatMap { Bundle(path: $0) } ?? Bundle.main
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
    }
}
