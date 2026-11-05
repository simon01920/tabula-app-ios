// "Share Timetable…" (Timetable ⋯ menu; route `share.sheet`). Phase 7 H1, PHASE7_PLAN decisions 2–3.
// ShareExport builds the envelope. If it fits the inline budget, the sheet shows the inline link at once (nothing is
// uploaded); otherwise it asks the share service for a short code. Shown: a QR code of the link (crisp, VoiceOver
// label), the link through the system share sheet, and the code in large monospaced type. A failed upload says what
// went wrong in plain words and offers Try Again, plus the inline link whenever it still fits a QR code.
// "Include open tasks and exams" rebuilds the envelope (SHARE_FORMAT §3; completed items are never shared).
// HIG: sheets.md (a self-contained task, Done to close), activity-views.md (system share sheet), feedback.md (errors
// in place, no alert for a recoverable state), accessibility.md (image description, spelled-out code).
// APIs: SwiftUI.ShareLink(item:subject:message:label:) (URL is Transferable, iOS 16), Image(uiImage:).interpolation(.none),
//       Text.speechSpellsOutCharacters() (iOS 15), View.textSelection(.enabled), View.task(id:), Form, Toggle.
// Note: `ShareLink` alone is ambiguous here (SwiftUI's view and TimetableCore's link type), so both are qualified.
// Phase 10 WP3:
// - B9: a code is uploaded once per envelope for the sheet's lifetime (`uploadedCodes`): flipping "Include open tasks"
//   back and forth reuses the code of the same envelope instead of spending another KV write (RISKS #14). A failed
//   upload is not cached (Try Again uploads). Reopening the sheet still uploads again (a cache across sheets needs a
//   home in the dependency container; not in this WP).
// - P8/U12: the QR code is rendered once per link text in `.task(id:)`, off the main actor, and kept in `@State`
//   (it was re-rendered with a new CIContext on every body pass); a failed render says so and points to the link.
import SwiftUI
import TimetableCore
import TimetableUI

struct ShareTimetableSheet: View {
    let timetableID: Timetable.ID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includeTasks = false
    @State private var state: ShareSheetState = .preparing
    @State private var warnings: [ShareWarning] = []
    @State private var attempt = 0
    /// Short codes already uploaded in this sheet, by envelope text (B9).
    @State private var uploadedCodes: [String: ShortCode] = [:]

    private var timetableName: String {
        model.timetables.first { $0.id == timetableID }?.name ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                content
                Section {
                    Toggle(isOn: $includeTasks) { Text("share.sheet.includeTasks") }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(warnings, id: \.self) { warning in
                            Text(verbatim: model.renderer.string(warning.message))
                        }
                    }
                }
            }
            .navigationTitle(Text("share.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("editor.common.done") }
                }
            }
            .task(id: TaskKey(includeTasks: includeTasks, attempt: attempt)) { await prepare() }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch state {
        case .preparing:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("share.sheet.preparing").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityElement(children: .combine)
            }
        case .ready(let link, let code):
            linkSections(link, code: code)
        case .uploadFailed(let messageKey, let fallback):
            Section {
                Label {
                    Text(LocalizedStringKey(messageKey))
                } icon: {
                    Image(AppSymbol.warning).foregroundStyle(Color.correction)
                }
                Button { attempt += 1 } label: { Text("share.sheet.retry") }
            } header: {
                Text("share.sheet.error.title")
            } footer: {
                if fallback != nil { Text("share.sheet.fallback") }
            }
            if let fallback { linkSections(fallback, code: nil) }
        case .exportFailed(let message):
            Section {
                Label {
                    Text(verbatim: message)
                } icon: {
                    Image(AppSymbol.warning).foregroundStyle(Color.correction)
                }
            }
        }
    }

    @ViewBuilder
    private func linkSections(_ link: TimetableCore.ShareLink, code: ShortCode?) -> some View {
        let url = link.url(configuration: ShareService.configuration)
        Section {
            QRCodeView(text: link.urlString(configuration: ShareService.configuration), timetableName: timetableName)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } footer: {
            Text("share.sheet.qr.hint").frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
        }
        if let code {
            Section {
                Text(verbatim: code.formatted)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(verbatim: code.rawValue).speechSpellsOutCharacters())
            } header: {
                Text("share.sheet.code.header")
            } footer: {
                Text("share.sheet.code.footer")
            }
        }
        if let url {
            Section {
                SwiftUI.ShareLink(item: url, subject: Text(verbatim: timetableName), message: Text("share.sheet.message")) {
                    Label { Text("share.sheet.shareLink") } icon: { Image(systemName: "square.and.arrow.up") }
                }
            } footer: {
                if code == nil { Text("share.sheet.footer.inline") } else { Text("share.sheet.footer.code") }
            }
        }
    }

    // MARK: Work

    private func prepare() async {
        state = .preparing
        guard let database = model.database else {
            state = .exportFailed(model.renderer.string(ShareError.timetableNotFound.message))
            return
        }
        let encoded: (envelope: ShareEnvelope, warnings: [ShareWarning])
        do throws(ShareError) {
            encoded = try ShareExport.encode(from: database, timetableID: timetableID, includeTasks: includeTasks)
        } catch {
            warnings = []
            state = .exportFailed(model.renderer.string(error.message))
            return
        }
        warnings = encoded.warnings
        switch SharePlan.make(for: encoded.envelope) {
        case .inline(let link):
            state = .ready(link, code: nil)
        case .upload(let envelope):
            if let code = uploadedCodes[envelope] {
                state = .ready(.shortCode(code), code: code)
                return
            }
            let result = await ShareServiceClient.upload(envelope: envelope)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let code):
                uploadedCodes[envelope] = code
                state = .ready(.shortCode(code), code: code)
            case .failure(let problem):
                state = .uploadFailed(messageKey: problem.messageKey, fallback: SharePlan.fallback(envelope: envelope))
            }
        }
    }

    private struct TaskKey: Equatable {
        let includeTasks: Bool
        let attempt: Int
    }
}

private enum ShareSheetState {
    case preparing
    case ready(TimetableCore.ShareLink, code: ShortCode?)
    case uploadFailed(messageKey: String, fallback: TimetableCore.ShareLink?)
    case exportFailed(String)
}

/// The QR code on a white card (codes need dark modules on a light ground in dark mode too), scaled without smoothing.
/// Rendered once per `text` (P8/U12); while rendering a small spinner holds the space, a failed render shows a note.
struct QRCodeView: View {
    let text: String
    let timetableName: String
    @Environment(AppModel.self) private var model
    @State private var rendered: Rendered?

    /// The QR image of one text (`image == nil`: the render failed).
    private struct Rendered {
        let text: String
        let image: UIImage?
    }

    var body: some View {
        Group {
            if let rendered, rendered.text == text {
                if let image = rendered.image {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .frame(maxWidth: 280, maxHeight: 280)
                        .accessibilityLabel(Text(verbatim: model.renderer.format(key: "share.sheet.qr.a11y",
                                                                                 arguments: [.text(timetableName)])))
                        .accessibilityAddTraits(.isImage)
                } else {
                    Label {
                        Text("share.sheet.qr.failed")
                    } icon: {
                        Image(AppSymbol.warning).foregroundStyle(Color.correction)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: 280, minHeight: 120)
            }
        }
        .task(id: text) {
            let image = await QRCodeRenderer.image(for: text)
            guard !Task.isCancelled else { return }
            rendered = Rendered(text: text, image: image.map { UIImage(cgImage: $0) })
        }
    }
}

/// Item for `.sheet(item:)`: the timetable being shared.
struct ShareTarget: Identifiable {
    let id: Timetable.ID
}

/// Route `share.sheet`: the active timetable of the seed.
struct ShareTimetableRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.activeTimetable?.id {
            ShareTimetableSheet(timetableID: id)
        } else {
            ProgressView()
        }
    }
}
