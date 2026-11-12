// Settings › Import (route `settings.import-model`, Phase 9 I2, PHASE9_PLAN decision 1):
//   Import from Photo or PDF…   starts the photo import (the sheet hangs on the Form, never on a Section: RISKS #99)
//   Apple Intelligence          the honest status: available / not turned on / language not supported / device not
//                               eligible / getting ready (AppleIntelligenceStatus). Tier A is used only when available.
//   Recognition model           Tier B placeholder: what it is, its size, "Available in a later version" and a disabled
//                               Download button. No progress, nothing downloads (the runtime and hosting need the
//                               human's approval and the paid account, PHASE9_PLAN "Needs the paid account").
// HIG: settings.md, generative-ai.md (disclose where the model runs, keep the feature usable without it), writing.md.
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsImportView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var aiStatus = AppleIntelligenceStatus.current

    /// Size of the planned model download (a 4-bit ~1.7B open-weight model, docs/spikes/LLM_RUNTIME.md §5).
    static let modelBytes: Int64 = 1_100_000_000

    var body: some View {
        Form {
            Section {
                Button { importing = true } label: {
                    Label { Text("import.entry.photoOrPDF") } icon: { Image(systemName: "doc.viewfinder") }
                }
                .disabled(model.isReadOnly || model.database == nil)
            } footer: {
                Text("settings.import.footer")
            }

            Section {
                LabeledContent {
                    Text(LocalizedStringKey(aiStatus.valueKey))
                } label: {
                    Label { Text("settings.import.ai.status") } icon: { Image(systemName: "sparkles") }
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("settings.import.ai.header")
            } footer: {
                Text(LocalizedStringKey(aiStatus.footerKey))
            }

            Section {
                Text("settings.import.model.explanation")
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent {
                    Text(verbatim: model.renderer.format(key: "settings.import.model.size.value", arguments: [
                        .text(Self.modelBytes.formatted(.byteCount(style: .file).locale(model.formatter.locale))),
                    ]))
                } label: {
                    Text("settings.import.model.size")
                }
                LabeledContent {
                    Text("settings.import.model.status.later")
                } label: {
                    Text("settings.import.model.status")
                }
                Button {} label: {
                    Label { Text("settings.import.model.download") } icon: { Image(systemName: "arrow.down.circle") }
                        .foregroundStyle(.secondary)   // visibly unavailable, not just inert
                }
                .disabled(true)
                .accessibilityHint(Text("settings.import.model.status.later"))
            } header: {
                Text("settings.import.model.header")
            } footer: {
                Text("settings.import.model.footer")
            }
        }
        .readableWidth()   // one readable column on wide screens (ADAPTIVE_LAYOUT.md)
        .navigationTitle(Text("settings.import.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $importing) { PhotoImportView() }
        .onAppear { aiStatus = .current }   // the user may have turned Apple Intelligence on in the meantime
    }
}
