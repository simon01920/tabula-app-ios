// One attachment-editing session per open task editor (stage B3, QA fix pass). The editor owns it (`@State`), hands it
// to `AttachmentsSection` through the environment and applies `attachmentsHost(_:)` once to its root view, so:
// - presenters (photo picker, file importer, recorder sheet, alerts, dialogs, Quick Look) exist once, outside the Form
//   (a modifier on a Form `Section` is applied per row);
// - store protection lives exactly as long as the editor: every ID the editor showed or added stays protected
//   (`AttachmentEditorProtection`, grow-only) from `begin` until the editor disappears;
// - `importingCount` lets the editor disable Save and swipe-to-dismiss while a copy is in flight, so a Save can never
//   drop an attachment whose file is still being copied;
// - a voice note's temporary file is deleted only after its ref is in the draft; when the copy fails the recording is
//   kept and the user can retry or delete it.
// Every change to the attachments goes through this session (the section passes its binding with each action), so the
// session always knows the current refs without observing the draft.
import PhotosUI
import QuickLook
import SwiftUI
import TimetableCore
import TimetableUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AttachmentEditorSession {
    // MARK: Observed state (section + host)

    /// Copies in flight. While > 0 the editor must not save or be swiped away.
    private(set) var importingCount = 0
    /// Stored files of the current refs (missing = not on this device).
    private(set) var fileURLs: [AttachmentRef.ID: URL] = [:]
    /// Bytes used by all attachments (footer).
    private(set) var usage: Int64?
    let player = VoiceNotePlayer()

    var showPhotoPicker = false
    var photoItem: PhotosPickerItem?
    var showFileImporter = false
    var showRecorder = false
    var showLinkPrompt = false
    var linkText = ""
    var showInvalidLink = false
    var renameTarget: AttachmentRef?
    var renameText = ""
    var deleteTarget: AttachmentRef?
    var linkToOpen: URL?
    var previewURL: URL?
    /// Message of the error alert.
    var importError: String?
    /// A recording whose copy failed: kept until the user retries or deletes it.
    var pendingVoiceNote: URL?

    // MARK: Plumbing

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var target: Binding<[AttachmentRef]>?
    @ObservationIgnored private var refs: [AttachmentRef] = []
    @ObservationIgnored private var protection = AttachmentEditorProtection()
    @ObservationIgnored private let owner = UUID()
    @ObservationIgnored private var started = false
    /// The editor is gone (`end()`, until a re-appear calls `begin` again): a recording whose copy fails now cannot be
    /// retried, so its temporary file is deleted instead of being kept as `pendingVoiceNote`.
    @ObservationIgnored private var isEnded = false

    private var store: (any AttachmentStore)? { model?.environment.attachments }
    private var quota: AttachmentQuota { model.map { AttachmentQuota(entitlements: $0.entitlements) } ?? .unlimited }
    var locale: Locale { model?.formatter.locale ?? .current }

    // MARK: Lifecycle (called by the host)

    /// The editor appeared: protect its refs and load file URLs. Re-appearing (after Quick Look) re-protects.
    func begin(model: AppModel, initial: [AttachmentRef]) {
        self.model = model
        isEnded = false
        if !started {
            started = true
            refs = initial
        }
        protection.record(refs)
        Task { await refresh() }
    }

    /// The editor disappeared: stop playback, end protection (orphans are then subject to the grace period).
    func end() {
        isEnded = true
        player.stop()
        guard let store else { return }
        let owner = owner
        Task { await store.clearProtection(owner: owner) }
    }

    /// File URLs, usage and protection for the current refs.
    func refresh() async {
        guard let store else { return }
        await store.setProtectedIDs(protection.ids, owner: owner)
        var urls: [AttachmentRef.ID: URL] = [:]
        for ref in AttachmentReferences.visible(refs) where ref.kind != .link {
            if let url = await store.fileURL(id: ref.id, fileName: ref.fileName) { urls[ref.id] = url }
        }
        fileURLs = urls
        usage = await store.totalUsage()
    }

    // MARK: Actions from the section (each passes the draft binding)

    func requestPhoto(into binding: Binding<[AttachmentRef]>) { target = binding; showPhotoPicker = true }
    func requestFile(into binding: Binding<[AttachmentRef]>) { target = binding; showFileImporter = true }
    func requestVoiceNote(into binding: Binding<[AttachmentRef]>) { target = binding; showRecorder = true }
    func requestLink(into binding: Binding<[AttachmentRef]>) {
        target = binding
        linkText = ""
        showLinkPrompt = true
    }

    func requestRename(_ ref: AttachmentRef, in binding: Binding<[AttachmentRef]>) {
        target = binding
        renameText = ref.title ?? ""
        renameTarget = ref
    }

    func requestDelete(_ ref: AttachmentRef, in binding: Binding<[AttachmentRef]>) {
        target = binding
        deleteTarget = ref
    }

    func move(_ ref: AttachmentRef, by offset: Int, in binding: Binding<[AttachmentRef]>) {
        target = binding
        var order = AttachmentReferences.visible(binding.wrappedValue).map(\.id)
        guard let index = order.firstIndex(of: ref.id), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        mutate { AttachmentReferences.reordered($0, to: order) }
    }

    func move(from source: IndexSet, to destination: Int, in binding: Binding<[AttachmentRef]>) {
        target = binding
        var order = AttachmentReferences.visible(binding.wrappedValue).map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        mutate { AttachmentReferences.reordered($0, to: order) }
    }

    /// Tap on a row: preview, play/pause, or the link confirmation.
    func activate(_ ref: AttachmentRef) {
        switch ref.kind {
        case .link:
            // Re-validated: refs can arrive through sync; only http(s) is ever offered.
            linkToOpen = AttachmentLink.validated(ref.url ?? "")
            if linkToOpen == nil { showInvalidLink = true }
        case .voiceNote:
            if let url = fileURLs[ref.id] { player.toggle(id: ref.id, url: url) }
        default:
            if let url = fileURLs[ref.id] { previewURL = url }
        }
    }

    // MARK: Actions from the host's dialogs

    func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { refs in
            refs.map { ref in
                guard ref.id == target.id else { return ref }
                var copy = ref
                copy.title = trimmed.isEmpty ? nil : String(trimmed.prefix(200))
                return copy
            }
        }
        renameTarget = nil
    }

    func confirmDelete(_ ref: AttachmentRef) {
        if player.playingID == ref.id { player.stop() }
        // Only the ref leaves the draft; the file is removed by the cleanup after the task is saved.
        mutate { $0.filter { $0.id != ref.id } }
        deleteTarget = nil
    }

    func addLink() {
        let text = linkText
        linkText = ""
        guard let url = AttachmentLink.validated(text) else {
            showInvalidLink = true
            return
        }
        let id = AttachmentRef.ID(UUID())
        protection.record(id)
        mutate { refs in
            refs + [AttachmentRef(id: id, meta: EditorEntities.placeholderMeta, kind: .link, url: url.absoluteString,
                                  sortIndex: AttachmentReferences.nextSortIndex(refs))]
        }
    }

    func importPhoto(_ item: PhotosPickerItem) {
        let type = item.supportedContentTypes.first
        let name = AttachmentFileName.generated(prefix: "Photo", fileExtension: type?.preferredFilenameExtension ?? "jpg",
                                                date: Date(), timeZone: .current)
        runImport(kind: .photo) { store, id, quota in
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AttachmentStoreError.sourceUnreadable
            }
            return try await store.importData(data, id: id, suggestedName: name, contentType: type?.identifier, quota: quota)
        }
    }

    func importFiles(_ result: Result<[URL], any Error>) {
        switch result {
        case .success(let urls): urls.forEach(importFile)
        case .failure: importError = string("attachments.error.generic")
        }
    }

    private func importFile(_ url: URL) {
        runImport(kind: .file) { store, id, quota in
            // fileImporter hands out security-scoped URLs: access is needed for the checks and the copy only.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
            if values?.isDirectory == true || values?.isPackage == true {
                throw AttachmentStoreError.notARegularFile
            }
            let contentType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
            return try await store.importFile(at: url, id: id, suggestedName: url.lastPathComponent,
                                              contentType: contentType?.identifier, quota: quota)
        }
    }

    /// Copies a finished recording in. The temporary file is deleted only once the ref is in the draft; on failure it
    /// is kept as `pendingVoiceNote` (alert: Try Again / Delete Recording).
    func importVoiceNote(_ temporaryURL: URL) {
        pendingVoiceNote = nil
        let name = AttachmentFileName.generated(prefix: "VoiceNote", fileExtension: "m4a", date: Date(), timeZone: .current)
        runImport(kind: .voiceNote, onSuccess: {
            try? FileManager.default.removeItem(at: temporaryURL)
        }, onFailure: { [weak self] in
            // Editor still open: keep the recording for Try Again / Delete. Editor (or session) gone: nobody can retry,
            // so delete the temporary file now (B3 QA low finding: it used to leak).
            if let self, !self.isEnded {
                self.pendingVoiceNote = temporaryURL
            } else {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }) { store, id, quota in
            try await store.importFile(at: temporaryURL, id: id, suggestedName: name,
                                       contentType: UTType.mpeg4Audio.identifier, quota: quota)
        }
    }

    func retryVoiceNote() {
        guard let url = pendingVoiceNote else { return }
        importVoiceNote(url)
    }

    func deletePendingVoiceNote() {
        if let url = pendingVoiceNote { try? FileManager.default.removeItem(at: url) }
        pendingVoiceNote = nil
    }

    /// The error alert was dismissed without choosing (keeps a pending recording only while the editor is open).
    func errorDismissed() {
        importError = nil
    }

    // MARK: Footer

    var usageText: String? {
        guard let usage, let model else { return nil }
        let style = ByteCountFormatStyle(style: .file).locale(locale)
        let used = usage.formatted(style)
        if let limit = quota.limitBytes {
            return model.renderer.format(key: "attachments.usage.limited", arguments: [.text(used), .text(limit.formatted(style))])
        }
        return model.renderer.format(key: "attachments.usage.unlimited", arguments: [.text(used)])
    }

    /// A catalog string through the app's renderer.
    func string(_ key: String) -> String {
        model?.renderer.string(forKey: key) ?? key
    }

    // MARK: Internals

    private func mutate(_ change: ([AttachmentRef]) -> [AttachmentRef]) {
        let base = target?.wrappedValue ?? refs
        let updated = change(base)
        refs = updated
        protection.record(updated)
        target?.wrappedValue = updated
        Task { await refresh() }
    }

    /// Copies one file in (counted in `importingCount`), then appends its ref. Failures show an alert.
    private func runImport(kind: AttachmentKind, onSuccess: @escaping @MainActor () -> Void = {},
                           onFailure: @escaping @MainActor () -> Void = {},
                           _ operation: @escaping @MainActor (any AttachmentStore, AttachmentRef.ID, AttachmentQuota) async throws
                               -> StoredAttachmentFile) {
        guard let store else { return }
        let quota = quota
        let id = AttachmentRef.ID(UUID())
        protection.record(id)   // protected before the folder exists
        importingCount += 1
        Task {
            await store.setProtectedIDs(protection.ids, owner: owner)
            do {
                let stored = try await operation(store, id, quota)
                mutate { refs in
                    refs + [AttachmentRef(id: id, meta: EditorEntities.placeholderMeta, kind: kind,
                                          fileName: stored.fileName, contentType: stored.contentType,
                                          byteCount: stored.byteCount, sortIndex: AttachmentReferences.nextSortIndex(refs))]
                }
                onSuccess()
            } catch {
                onFailure()
                importError = message(for: error)
            }
            importingCount -= 1
        }
    }

    private func message(for error: any Error) -> String {
        let style = ByteCountFormatStyle(style: .file).locale(locale)
        switch error as? AttachmentStoreError {
        case let .quotaExceeded(needed, available)?:
            return model?.renderer.format(key: "attachments.error.quota",
                                          arguments: [.text(needed.formatted(style)), .text(available.formatted(style))])
                ?? "attachments.error.quota"
        case .notARegularFile?:
            return string("attachments.error.folder")
        default:
            return string("attachments.error.generic")
        }
    }
}

extension View {
    /// Presenters and lifecycle of an attachment-editing session. Apply once, to the editor's root (outside the Form).
    func attachmentsHost(_ session: AttachmentEditorSession, initial: [AttachmentRef]) -> some View {
        modifier(AttachmentsHost(session: session, initial: initial))
    }
}

private struct AttachmentsHost: ViewModifier {
    @Bindable var session: AttachmentEditorSession
    let initial: [AttachmentRef]
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .environment(session)
            .safeAreaInset(edge: .bottom) {
                if session.importingCount > 0 {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("attachments.adding.banner")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
                    .accessibilityElement(children: .combine)
                }
            }
            .photosPicker(isPresented: $session.showPhotoPicker, selection: $session.photoItem, matching: .images)
            .onChange(of: session.photoItem) { _, item in
                guard let item else { return }
                session.photoItem = nil
                session.importPhoto(item)
            }
            .fileImporter(isPresented: $session.showFileImporter, allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                session.importFiles(result)
            }
            .sheet(isPresented: $session.showRecorder) {
                VoiceNoteRecorderSheet { url in session.importVoiceNote(url) }
            }
            .alert(Text("attachments.link.title"), isPresented: $session.showLinkPrompt) {
                TextField(text: $session.linkText) { Text("attachments.link.field") }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("editor.common.cancel", role: .cancel) { session.linkText = "" }
                Button("attachments.link.add") { session.addLink() }
            } message: {
                Text("attachments.link.message")
            }
            .alert(Text("attachments.link.invalid.title"), isPresented: $session.showInvalidLink) {
                Button("editor.common.cancel", role: .cancel) {}
            } message: {
                Text("attachments.link.invalid.message")
            }
            .alert(Text("attachments.rename.title"), isPresented: optionalPresented(\.renameTarget)) {
                TextField(text: $session.renameText) { Text("attachments.rename.field") }
                Button("editor.common.cancel", role: .cancel) { session.renameTarget = nil }
                Button("editor.common.save") { session.commitRename() }
            }
            .confirmationDialog(Text("attachments.delete.title"), isPresented: optionalPresented(\.deleteTarget),
                                titleVisibility: .visible, presenting: session.deleteTarget) { ref in
                Button("attachments.delete.confirm", role: .destructive) { session.confirmDelete(ref) }
                Button("editor.common.cancel", role: .cancel) {}
            } message: { _ in
                Text("attachments.delete.message")
            }
            .confirmationDialog(Text("attachments.link.open.title"), isPresented: optionalPresented(\.linkToOpen),
                                titleVisibility: .visible, presenting: session.linkToOpen) { url in
                Button("attachments.link.open.confirm") { openURL(url) }
                Button("editor.common.cancel", role: .cancel) {}
            } message: { url in
                Text(verbatim: url.absoluteString)
            }
            .alert(Text("attachments.error.title"), isPresented: optionalPresented(\.importError)) {
                if session.pendingVoiceNote != nil {
                    Button("attachments.voice.retry") { session.retryVoiceNote() }
                    Button("attachments.voice.deleteRecording", role: .destructive) { session.deletePendingVoiceNote() }
                } else {
                    Button("editor.common.cancel", role: .cancel) { session.errorDismissed() }
                }
            } message: {
                if let message = session.importError { Text(verbatim: message) }
            }
            .quickLookPreview($session.previewURL)
            .onAppear { session.begin(model: model, initial: initial) }
            .onDisappear {
                session.end()
                // The editor is gone: a recording that could not be copied is not recoverable any more.
                session.deletePendingVoiceNote()
            }
    }

    private func optionalPresented<Value>(_ keyPath: ReferenceWritableKeyPath<AttachmentEditorSession, Value?>) -> Binding<Bool> {
        let session = session
        return Binding(get: { session[keyPath: keyPath] != nil }, set: { if !$0 { session[keyPath: keyPath] = nil } })
    }
}
