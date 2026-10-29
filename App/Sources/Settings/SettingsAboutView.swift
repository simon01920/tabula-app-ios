// Settings → About & Feedback (route `settings.about`; Phase 4U U5a, L4): version and build (from the bundle; a missing value is
// simply absent), Send Feedback (mailto), Privacy Policy (web), Rate Tabula (only once an App Store link exists), the privacy
// summary and a pushed Acknowledgements page. The three targets are PLACEHOLDERS in `AppLinks` (SettingsComponents.swift).
// No network access happens in the app itself: the links hand over to Mail / Safari / the App Store.
// APIs: Bundle.main.object(forInfoDictionaryKey:) with CFBundleShortVersionString / CFBundleVersion, LabeledContent,
//       EnvironmentValues.openURL, NavigationLink.
import SwiftUI

struct SettingsAboutView: View {
    @Environment(\.openURL) private var openURL
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
                if let url = AppLinks.feedbackURL(version: version) {
                    linkRow("settings.about.feedback", symbol: "envelope", url: url)
                }
                if let url = AppLinks.privacyPolicyURL {
                    linkRow("settings.about.privacyPolicy", symbol: "hand.raised", url: url)
                }
                if let url = AppLinks.reviewURL {
                    linkRow("settings.about.rate", symbol: "star", url: url)
                }
            }
            Section {
                Text("settings.about.privacy.body")
            } header: {
                Text("settings.about.privacy.title")
            }
            Section {
                NavigationLink {
                    Form {
                        Section { Text("settings.about.acknowledgements.body2") }
                    }
                    .navigationTitle(Text("settings.about.acknowledgements.title"))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label { Text("settings.about.acknowledgements.title") } icon: { Image(systemName: "doc.text") }
                }
            }
        }
        .navigationTitle(Text("settings.aboutfeedback.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(_ key: LocalizedStringKey, symbol: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            LabeledContent {
                Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            } label: {
                Label { Text(key) } icon: { Image(systemName: symbol) }
            }
            .foregroundStyle(.primary)
        }
    }
}
