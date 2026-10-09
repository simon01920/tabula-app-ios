// Settings → About: version and build (from the bundle; a missing value is simply absent), privacy summary,
// acknowledgements. Plain text; no network, no links out.
// APIs: Bundle.main.object(forInfoDictionaryKey:) with CFBundleShortVersionString / CFBundleVersion, LabeledContent.
import SwiftUI

struct SettingsAboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    var body: some View {
        Form {
            if version != nil || build != nil {
                Section {
                    if let version {
                        LabeledContent { Text(verbatim: version) } label: { Text("settings.about.version") }
                            .accessibilityElement(children: .combine)
                    }
                    if let build {
                        LabeledContent { Text(verbatim: build) } label: { Text("settings.about.build") }
                            .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Text("settings.about.privacy.body")
            } header: {
                Text("settings.about.privacy.title")
            }
            Section {
                Text("settings.about.acknowledgements.body")
            } header: {
                Text("settings.about.acknowledgements.title")
            }
        }
        .navigationTitle(Text("settings.about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
