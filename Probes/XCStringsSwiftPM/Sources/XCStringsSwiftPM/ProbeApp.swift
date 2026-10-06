// String Catalog-as-SwiftPM-resource probe. UNCOMPILED.
// On device: a raw key ("probe.hello") means the catalog was copied but not compiled.
// APIs (docs checked): String(localized:table:bundle:locale:comment:) iOS 15, Bundle.module (SwiftPM).
import SwiftUI

@main
struct XCStringsProbeApp: App {
    var body: some Scene {
        WindowGroup {
            List {
                Text(verbatim: "Current: " + String(localized: "probe.hello", bundle: .module))
                Text(verbatim: "Plural: " + String(localized: "probe.lessons \(3)", bundle: .module))
                Text(verbatim: "Localizations: \(Bundle.module.localizations)")
            }
        }
    }
}
