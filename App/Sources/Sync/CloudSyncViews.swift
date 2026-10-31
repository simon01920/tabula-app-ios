// iCloud UI (Phase 6 S1): the first-sync alert and the Settings › iCloud section.
// Paid builds (TABULA_CLOUDKIT): the iCloud Sync switch (AppSettings.syncEnabled, default on) with a status line in the
// footer. Other builds: an honest informational row, no switch (PHASE6_PLAN decision 1).
// HIG: alerts.md › Buttons ("up to three buttons", default at the top of a stack, destructive style for an action people
// did not choose deliberately); here the safe choice, Merge, is the default and the way out, so there is no Cancel.
// settings.md: a switch row with an explanatory footer. APIs: View.alert(_:isPresented:actions:message:),
// Button(role: .destructive), View.keyboardShortcut(.defaultAction), Toggle, Section(content:header:footer:),
// Date.formatted(.relative(presentation:)).
import SwiftUI
import TimetableCore
import TimetableUI

/// Settings › iCloud.
struct CloudSyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    #if TABULA_CLOUDKIT
    @Environment(CloudSyncController.self) private var cloudSync: CloudSyncController?
    #endif

    var body: some View {
        #if TABULA_CLOUDKIT
        Section {
            Toggle(isOn: Binding(get: { model.settings.syncEnabled },
                                 set: { value in model.apply(.settings { $0.syncEnabled = value }) })) {
                SettingsRowLabel("settings.icloud.title", symbol: "icloud.fill", color: .blue)
            }
            .disabled(model.isReadOnly)
        } footer: {
            Text(verbatim: statusText)
        }
        #else
        Section {
            LabeledContent {
                Text("settings.icloud.unavailable.value")
            } label: {
                SettingsRowLabel("settings.icloud.title", symbol: "icloud.fill", color: .blue)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            Text("settings.icloud.unavailable.footer")
        }
        #endif
    }

    #if TABULA_CLOUDKIT
    private var statusText: String {
        let status = model.settings.syncEnabled ? cloudSync?.status ?? .notSyncedYet : .off
        switch status {
        case .synced(let date):
            let when = date.formatted(.relative(presentation: .named).locale(model.formatter.locale))
            return model.renderer.format(key: "settings.icloud.status.synced", arguments: [.text(when)])
        case .off: return model.renderer.string(forKey: "settings.icloud.status.off")
        case .notSyncedYet: return model.renderer.string(forKey: "settings.icloud.status.notSyncedYet")
        case .syncing: return model.renderer.string(forKey: "settings.icloud.status.syncing")
        case .noAccount: return model.renderer.string(forKey: "settings.icloud.status.noAccount")
        case .quotaExceeded: return model.renderer.string(forKey: "settings.icloud.status.quotaExceeded")
        case .itemsTooLarge: return model.renderer.string(forKey: "settings.icloud.status.itemsTooLarge")
        case .newerAppVersion: return model.renderer.string(forKey: "settings.icloud.status.newerAppVersion")
        case .iCloudDataDeleted: return model.renderer.string(forKey: "settings.icloud.status.iCloudDataDeleted")
        }
    }
    #endif
}

#if TABULA_CLOUDKIT
/// The first-sync question, shown over any screen when this iPhone and iCloud both hold data.
struct FirstSyncAlert: ViewModifier {
    let cloudSync: CloudSyncController?

    func body(content: Content) -> some View {
        content.alert(Text("sync.firstSync.title"), isPresented: Binding(
            get: { cloudSync?.isAwaitingFirstSyncChoice ?? false },
            set: { _ in })   // the alert closes through `choose(_:)`, which clears the flag
        ) {
            Button("sync.firstSync.merge") { cloudSync?.choose(.merge) }
                .keyboardShortcut(.defaultAction)
            Button("sync.firstSync.keepThisDevice", role: .destructive) { cloudSync?.choose(.keepThisDevice) }
            Button("sync.firstSync.useICloud", role: .destructive) { cloudSync?.choose(.useICloud) }
        } message: {
            Text("sync.firstSync.message")
        }
    }
}
#endif
