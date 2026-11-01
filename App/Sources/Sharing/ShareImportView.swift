// "Import Timetable…" (Settings, onboarding start step, `tabula://import` links; routes `share.import`,
// `share.import-preview`). Phase 7 H1, PHASE7_PLAN decisions 2–4.
//   Entry     Scan QR Code (VisionKit scanner) · Choose Photo of QR Code (Vision) · Code (8 characters, alphabet
//             checked on every keystroke) · Paste Link (system PasteButton: no paste prompt)
//   Resolve   a code is fetched from the share service; every envelope goes through `ShareImport.decode` (untrusted)
//   Preview   ShareImportSummary: name, subjects, lesson count, bell schedules, conflicts, tasks, warnings
//   Import    "Add as New Timetable" (default, prominent) or "Replace “…”" → destructive alert → a backup copy in
//             `<store>/Backups` FIRST (Phase 6 S2 BackupFolder, label "pre-import"; no copy → no replace) →
//             `model.apply(.importShared…)`. Nothing is overwritten silently; errors are `ShareError` /
//             `ShareServiceProblem` messages in plain words.
// Free tier (1 timetable): "Add" is disabled with a footer that says why; Replace stays.
// HIG: sheets.md, alerts.md (destructive button + Cancel; title names the item), entering-data.md (live validation,
// choices over typing), privacy.md (camera asked in context, honest purpose string), feedback.md.
// APIs: PasteButton(payloadType:onPaste:) (iOS 16), PhotosPicker(selection:matching:label:) +
//       PhotosPickerItem.loadTransferable(type: Data.self), View.fullScreenCover(isPresented:), TextField(_:text:prompt:),
//       View.textInputAutocapitalization(.characters), View.autocorrectionDisabled(), View.alert(_:isPresented:presenting:).
import PhotosUI
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct ShareImportView: View {
    /// An incoming link / scanned code to open at once (`nil` = show the entry choices).
    var initial: ShareInbound?
    /// Set when importing from onboarding: the school type chosen there.
    var profile: UserProfile?

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var codeText = ""
    @State private var resolved: ResolvedShare?
    @State private var isLoading = false
    @State private var problem: String?
    @State private var scanning = false
    @State private var cameraDenied = false
    @State private var photoItem: PhotosPickerItem?
    @State private var didOpenInitial = false

    var body: some View {
        NavigationStack {
            Group {
                if let resolved {
                    ShareImportPreview(resolved: resolved, profile: profile) { imported in
                        if imported { navigation.selectedTab = .timetable }
                        dismiss()
                    }
                } else {
                    entry
                }
            }
            .overlay {
                if isLoading {
                    ProgressView { Text("share.import.loading") }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationTitle(Text("share.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("editor.common.cancel") }
                }
            }
        }
        .task {
            guard let initial, !didOpenInitial else { return }
            didOpenInitial = true
            await resolve(initial)
        }
        .fullScreenCover(isPresented: $scanning) {
            ScannerScreen { inbound in
                scanning = false
                Task { await resolve(inbound) }
            } onUnavailable: {
                scanning = false
                cameraDenied = true
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await readPhoto(item) }
        }
        .alert(Text("share.import.error.title"), isPresented: isPresented($problem), presenting: problem) { _ in
            Button { } label: { Text("editor.warnings.ok") }
        } message: { message in
            Text(verbatim: message)
        }
        .alert(Text("share.import.camera.title"), isPresented: $cameraDenied) {
            Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                Text("health.action.openSettings")
            }
            Button(role: .cancel) { } label: { Text("editor.common.cancel") }
        } message: {
            Text("share.import.camera.denied")
        }
    }

    // MARK: Entry

    private var codeState: ShareCodeInput { ShareCodeInput.evaluate(codeText) }

    private var entry: some View {
        Form {
            Section {
                if QRScanning.isScannerSupported {
                    Button {
                        if QRScanning.isScannerUsable { scanning = true } else { cameraDenied = true }
                    } label: {
                        Label { Text("share.import.scan") } icon: { Image(systemName: "qrcode.viewfinder") }
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label { Text("share.import.photo") } icon: { Image(systemName: "photo") }
                }
            } footer: {
                Text("share.import.scan.footer")
            }

            Section {
                TextField(text: $codeText, prompt: Text("share.import.code.prompt")) {
                    Text("share.import.code.header")
                }
                .font(.system(.title3, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.go)
                .onSubmit(submitCode)
                Button(action: submitCode) { Text("share.import.code.open") }
                    .disabled(codeCode == nil || isLoading)
            } header: {
                Text("share.import.code.header")
            } footer: {
                codeHint
            }

            Section {
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in open(text) }
                }
                .disabled(isLoading)
            } header: {
                Text("share.import.link.header")
            } footer: {
                Text("share.import.link.footer")
            }
        }
        .disabled(isLoading)
    }

    private var codeCode: ShortCode? {
        if case .complete(let code) = codeState { return code }
        return nil
    }

    @ViewBuilder private var codeHint: some View {
        switch codeState {
        case .incomplete(let remaining):
            Text(verbatim: model.renderer.format(key: "share.code.remaining", arguments: [.integer(Int64(remaining))]))
        case .invalidCharacter:
            Label { Text("share.code.invalidCharacter") } icon: { Image(AppSymbol.warning) }
                .foregroundStyle(Color.correction)
        case .tooLong:
            Label { Text("share.code.tooLong") } icon: { Image(AppSymbol.warning) }
                .foregroundStyle(Color.correction)
        case .empty, .complete:
            Text("share.import.code.footer")
        }
    }

    private func submitCode() {
        guard let code = codeCode, !isLoading else { return }
        Task { await resolve(.code(code)) }
    }

    /// Pasted text or a scanned payload.
    private func open(_ text: String) {
        do throws(ShareError) {
            let inbound = try ShareInbound.parse(pasted: text, configuration: ShareService.configuration)
            Task { await resolve(inbound) }
        } catch {
            problem = model.renderer.string(error.message)
        }
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = model.renderer.string(forKey: "share.import.photo.unreadable")
            return
        }
        let payloads = await QRScanning.payloads(inImageData: data)
        guard let inbound = payloads.lazy.compactMap({ try? ShareInbound.parse(pasted: $0, configuration: ShareService.configuration) }).first else {
            problem = model.renderer.string(forKey: "share.import.photo.noCode")
            return
        }
        isLoading = false
        await resolve(inbound)
    }

    // MARK: Resolve

    private func resolve(_ inbound: ShareInbound) async {
        isLoading = true
        defer { isLoading = false }
        let envelope: String
        switch inbound {
        case .envelope(let text):
            envelope = text
        case .code(let code):
            switch await ShareServiceClient.fetch(code: code) {
            case .success(let text): envelope = text
            case .failure(let failure):
                problem = model.renderer.string(forKey: failure.messageKey)
                return
            }
        }
        do throws(ShareError) {
            let payload = try ShareImport.decode(envelope)
            resolved = ResolvedShare(payload: payload,
                                     summary: try ShareImportSummary(payload: payload, context: model.calendarContext))
        } catch {
            problem = model.renderer.string(error.message)
        }
    }

    private func isPresented<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

/// A decoded, validated payload and what the preview shows of it.
struct ResolvedShare {
    let payload: SharePayloadV1
    let summary: ShareImportSummary
}

// MARK: - Scanner screen

/// Full-screen camera with Cancel and a hint; a QR code that is not Tabula's says so and scanning goes on.
private struct ScannerScreen: View {
    let onFound: (ShareInbound) -> Void
    let onUnavailable: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var foreignCode = false
    @State private var found = false   // the scanner may report the same code again before the cover closes

    var body: some View {
        NavigationStack {
            QRScannerView { payload in
                guard !found else { return }
                if let inbound = try? ShareInbound.parse(pasted: payload, configuration: ShareService.configuration) {
                    found = true
                    onFound(inbound)
                } else {
                    foreignCode = true
                }
            } onUnavailable: {
                onUnavailable()
            }
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom) {
                Group {
                    if foreignCode { Text("share.import.scan.foreign") } else { Text("share.import.scan.hint") }
                }
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(16)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .navigationTitle(Text("share.import.scan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("editor.common.cancel") }
                }
            }
        }
    }
}

/// Route `share.import-preview`: the seed's active timetable as if it had arrived by link.
struct ShareImportPreviewRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let database = model.database, let id = model.activeTimetable?.id,
           let envelope = try? ShareExport.encode(from: database, timetableID: id, includeTasks: true).envelope.text {
            ShareImportView(initial: .envelope(envelope))
        } else {
            ProgressView()
        }
    }
}
