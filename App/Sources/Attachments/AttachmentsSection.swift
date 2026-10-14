// The task editor's attachments section (Phase 3 stage B3; signature fixed in Stage A, B1 embeds it in the Form):
//     AttachmentsSection(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID)
// The body is a `Section`. It edits only the binding; the editor saves the task (and with it the refs) through
// `model.apply(.upsert(task))`.
//
// Files: copied into the attachment store (`<store directory>/Attachments/<attachmentID>/<fileName>`, see
// TimetableUI/Attachments) the moment they are added, then referenced from the binding. If the editor is cancelled
// they are orphans and the cleanup removes them after the grace period; while this section is on screen its IDs are
// protected. Removing an attachment only drops the ref from the binding (the stamper tombstones it on save); the file
// is deleted by the cleanup after the save — never here, because a cancelled editor must keep the saved task intact.
// Links: http(s) only (validated), never opened without a confirmation that shows the full URL.
//
// APIs (docs checked 2026-10-10, docs/ENVIRONMENT.md §22): View.photosPicker(isPresented:selection:matching:
//   preferredItemEncoding:) + PhotosPickerItem.loadTransferable(type: Data.self) + supportedContentTypes (iOS 16),
//   View.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:) (iOS 14; security-scoped
//   URLs: startAccessingSecurityScopedResource / stopAccessingSecurityScopedResource), View.quickLookPreview(_:)
//   (iOS 14), EnvironmentValues.openURL, alert with TextField (iOS 16), confirmationDialog, onMove, swipeActions,
//   accessibilityAction(named:).
import PhotosUI
import QuickLook
import SwiftUI
import TimetableCore
import TimetableUI
import UniformTypeIdentifiers

struct AttachmentsSection: View {
    @Binding var attachments: [AttachmentRef]
    /// The task that owns the attachments.
    let ownerID: TaskItem.ID

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    /// This section's protection token in the store (its IDs are never cleaned up while it is shown).
    @State private var protectionOwner = UUID()
    @State private var player = VoiceNotePlayer()
    @State private var fileURLs: [AttachmentRef.ID: URL] = [:]
    @State private var usage: Int64?
    @State private var importingCount = 0

    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showRecorder = false
    @State private var showLinkPrompt = false
    @State private var linkText = ""
    @State private var showInvalidLink = false
    @State private var renameTarget: AttachmentRef?
    @State private var renameText = ""
    @State private var deleteTarget: AttachmentRef?
    @State private var linkToOpen: URL?
    @State private var previewURL: URL?
    @State private var importError: String?

    init(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID) {
        _attachments = attachments
        self.ownerID = ownerID
    }

    private var visible: [AttachmentRef] { AttachmentReferences.visible(attachments) }
    private var store: any AttachmentStore { model.environment.attachments }
    private var quota: AttachmentQuota { AttachmentQuota(entitlements: model.entitlements) }
    private var locale: Locale { model.formatter.locale }
    /// Changes whenever a ref is added, removed or renamed on disk → reload URLs, protection and usage.
    private var refreshKey: [String] { attachments.map { "\($0.id)|\($0.fileName ?? "")|\($0.meta.isDeleted)" } }

    var body: some View {
        Section {
            if visible.isEmpty && importingCount == 0 {
                Text("attachments.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { ref in
                AttachmentRow(ref: ref, fileURL: fileURLs[ref.id], locale: locale, player: player) { activate(ref) }
                    .contextMenu { rowActions(ref) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteTarget = ref } label: {
                            Label { Text("editor.common.delete") } icon: { Image(systemName: "trash") }
                        }
                        Button { beginRename(ref) } label: {
                            Label { Text("attachments.rename") } icon: { Image(systemName: "pencil") }
                        }
                    }
                    .accessibilityAction(named: Text("attachments.rename")) { beginRename(ref) }
                    .accessibilityAction(named: Text("attachments.moveUp")) { move(ref, by: -1) }
                    .accessibilityAction(named: Text("attachments.moveDown")) { move(ref, by: 1) }
                    .accessibilityAction(named: Text("editor.common.delete")) { deleteTarget = ref }
            }
            .onMove(perform: move)
            if importingCount > 0 {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("attachments.importing").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            addMenu
        } header: {
            Text("attachments.section.title")
        } footer: {
            if let usageText { Text(verbatim: usageText) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            importPhoto(item)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(importFile)
            case .failure: importError = model.renderer.string(forKey: "attachments.error.generic")
            }
        }
        .sheet(isPresented: $showRecorder) {
            VoiceNoteRecorderSheet { url in importVoiceNote(url) }
        }
        .alert(Text("attachments.link.title"), isPresented: $showLinkPrompt) {
            TextField(text: $linkText) { Text("attachments.link.field") }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("editor.common.cancel", role: .cancel) { linkText = "" }
            Button("attachments.link.add") { addLink() }
        } message: {
            Text("attachments.link.message")
        }
        .alert(Text("attachments.link.invalid.title"), isPresented: $showInvalidLink) {
            Button("editor.common.cancel", role: .cancel) {}
        } message: {
            Text("attachments.link.invalid.message")
        }
        .alert(Text("attachments.rename.title"), isPresented: renamePresented) {
            TextField(text: $renameText) { Text("attachments.rename.field") }
            Button("editor.common.cancel", role: .cancel) { renameTarget = nil }
            Button("editor.common.save") { commitRename() }
        }
        .confirmationDialog(Text("attachments.delete.title"), isPresented: deletePresented, titleVisibility: .visible,
                            presenting: deleteTarget) { ref in
            Button("attachments.delete.confirm", role: .destructive) { remove(ref) }
            Button("editor.common.cancel", role: .cancel) {}
        } message: { _ in
            Text("attachments.delete.message")
        }
        .confirmationDialog(Text("attachments.link.open.title"), isPresented: openLinkPresented, titleVisibility: .visible,
                            presenting: linkToOpen) { url in
            Button("attachments.link.open.confirm") { openURL(url) }
            Button("editor.common.cancel", role: .cancel) {}
        } message: { url in
            Text(verbatim: url.absoluteString)
        }
        .alert(Text("attachments.error.title"), isPresented: errorPresented) {
            Button("editor.common.cancel", role: .cancel) {}
        } message: {
            if let importError { Text(verbatim: importError) }
        }
        .quickLookPreview($previewURL)
        .task(id: refreshKey) { await refreshFiles() }
        .onDisappear {
            player.stop()
            let store = store, owner = protectionOwner
            Task { await store.clearProtection(owner: owner) }
        }
    }

    // MARK: Pieces

    private var addMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: {
                Label { Text("attachments.add.photo") } icon: { Image(systemName: "photo.on.rectangle") }
            }
            Button { showFileImporter = true } label: {
                Label { Text("attachments.add.file") } icon: { Image(systemName: "doc") }
            }
            Button { linkText = ""; showLinkPrompt = true } label: {
                Label { Text("attachments.add.link") } icon: { Image(systemName: "link") }
            }
            Button { showRecorder = true } label: {
                Label { Text("attachments.add.voiceNote") } icon: { Image(systemName: "mic") }
            }
        } label: {
            Label { Text("attachments.add") } icon: { Image(systemName: "paperclip") }
        }
    }

    @ViewBuilder private func rowActions(_ ref: AttachmentRef) -> some View {
        if ref.kind != .link, ref.kind != .voiceNote, fileURLs[ref.id] != nil {
            Button { activate(ref) } label: {
                Label { Text("attachments.preview") } icon: { Image(systemName: "eye") }
            }
        }
        if ref.kind == .voiceNote, let url = fileURLs[ref.id] {
            Button { previewURL = url } label: {
                Label { Text("attachments.preview") } icon: { Image(systemName: "eye") }
            }
        }
        if ref.kind == .link {
            Button { activate(ref) } label: {
                Label { Text("attachments.link.open.confirm") } icon: { Image(systemName: "safari") }
            }
        }
        Button { beginRename(ref) } label: {
            Label { Text("attachments.rename") } icon: { Image(systemName: "pencil") }
        }
        Button { move(ref, by: -1) } label: {
            Label { Text("attachments.moveUp") } icon: { Image(systemName: "arrow.up") }
        }
        .disabled(visible.first?.id == ref.id)
        Button { move(ref, by: 1) } label: {
            Label { Text("attachments.moveDown") } icon: { Image(systemName: "arrow.down") }
        }
        .disabled(visible.last?.id == ref.id)
        Button(role: .destructive) { deleteTarget = ref } label: {
            Label { Text("editor.common.delete") } icon: { Image(systemName: "trash") }
        }
    }

    private var usageText: String? {
        guard let usage, !visible.isEmpty || usage > 0 else { return nil }
        let used = usage.formatted(.byteCount(style: .file).locale(locale))
        if let limit = quota.limitBytes {
            return model.renderer.format(key: "attachments.usage.limited",
                                         arguments: [.text(used), .text(limit.formatted(.byteCount(style: .file).locale(locale)))])
        }
        return model.renderer.format(key: "attachments.usage.unlimited", arguments: [.text(used)])
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var openLinkPresented: Binding<Bool> {
        Binding(get: { linkToOpen != nil }, set: { if !$0 { linkToOpen = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    // MARK: Actions

    private func activate(_ ref: AttachmentRef) {
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

    private func beginRename(_ ref: AttachmentRef) {
        renameText = ref.title ?? ""
        renameTarget = ref
    }

    private func commitRename() {
        guard let target = renameTarget, let index = attachments.firstIndex(where: { $0.id == target.id }) else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        attachments[index].title = trimmed.isEmpty ? nil : String(trimmed.prefix(200))
        renameTarget = nil
    }

    private func remove(_ ref: AttachmentRef) {
        if player.playingID == ref.id { player.stop() }
        attachments.removeAll { $0.id == ref.id }
        deleteTarget = nil
    }

    private func move(from source: IndexSet, to destination: Int) {
        var order = visible.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        attachments = AttachmentReferences.reordered(attachments, to: order)
    }

    private func move(_ ref: AttachmentRef, by offset: Int) {
        var order = visible.map(\.id)
        guard let index = order.firstIndex(of: ref.id), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        attachments = AttachmentReferences.reordered(attachments, to: order)
    }

    private func addLink() {
        let text = linkText
        linkText = ""
        guard let url = AttachmentLink.validated(text) else {
            showInvalidLink = true
            return
        }
        attachments.append(AttachmentRef(id: AttachmentRef.ID(UUID()), meta: EditorEntities.placeholderMeta, kind: .link,
                                         url: url.absoluteString,
                                         sortIndex: AttachmentReferences.nextSortIndex(attachments)))
    }

    // MARK: Import

    private func importPhoto(_ item: PhotosPickerItem) {
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

    private func importFile(_ url: URL) {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        runImport(kind: .file) { store, id, quota in
            // fileImporter hands out security-scoped URLs: access is needed for the copy only.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try await store.importFile(at: url, id: id, suggestedName: url.lastPathComponent,
                                              contentType: contentType?.identifier, quota: quota)
        }
    }

    private func importVoiceNote(_ temporaryURL: URL) {
        let name = AttachmentFileName.generated(prefix: "VoiceNote", fileExtension: "m4a", date: Date(), timeZone: .current)
        runImport(kind: .voiceNote) { store, id, quota in
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            return try await store.importFile(at: temporaryURL, id: id, suggestedName: name,
                                              contentType: UTType.mpeg4Audio.identifier, quota: quota)
        }
    }

    /// Copies one file in, then appends its ref. Failures show an alert; nothing is appended.
    private func runImport(kind: AttachmentKind,
                           _ operation: @escaping @MainActor (any AttachmentStore, AttachmentRef.ID, AttachmentQuota) async throws
                               -> StoredAttachmentFile) {
        let store = store, quota = quota, id = AttachmentRef.ID(UUID())
        importingCount += 1
        Task {
            defer { importingCount -= 1 }
            do {
                let stored = try await operation(store, id, quota)
                attachments.append(AttachmentRef(id: id, meta: EditorEntities.placeholderMeta, kind: kind,
                                                 fileName: stored.fileName, contentType: stored.contentType,
                                                 byteCount: stored.byteCount,
                                                 sortIndex: AttachmentReferences.nextSortIndex(attachments)))
            } catch {
                importError = message(for: error)
            }
        }
    }

    private func message(for error: any Error) -> String {
        if case let AttachmentStoreError.quotaExceeded(needed, available)? = error as? AttachmentStoreError {
            return model.renderer.format(key: "attachments.error.quota", arguments: [
                .text(needed.formatted(.byteCount(style: .file).locale(locale))),
                .text(available.formatted(.byteCount(style: .file).locale(locale))),
            ])
        }
        return model.renderer.string(forKey: "attachments.error.generic")
    }

    private func refreshFiles() async {
        let store = store
        await store.setProtectedIDs(Set(attachments.map(\.id.uuid)), owner: protectionOwner)
        var urls: [AttachmentRef.ID: URL] = [:]
        for ref in visible where ref.kind != .link {
            if let url = await store.fileURL(id: ref.id, fileName: ref.fileName) { urls[ref.id] = url }
        }
        fileURLs = urls
        usage = await store.totalUsage()
    }
}
