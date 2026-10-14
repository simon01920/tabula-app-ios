// The task editor's attachments section (Phase 3 stage B3; signature fixed in Stage A):
//     AttachmentsSection(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID)
// The body is a plain `Section` of rows with NO presenters or lifecycle modifiers (in a Form those would be applied
// per row). Everything else lives in `AttachmentEditorSession` + `.attachmentsHost(_:initial:)`, which the editor
// applies once to its root and which puts the session into the environment (see AttachmentEditorSession.swift).
// The section edits only the binding (through the session); the editor saves the task (and with it the refs).
//
// Files are copied into the attachment store the moment they are added and referenced from the binding. If the editor
// is cancelled they are orphans and the cleanup removes them after the grace period. Removing an attachment only drops
// the ref (the stamper tombstones it on save); the file is deleted by the cleanup after the save.
// Links: http(s) only (validated), never opened without a confirmation that shows the full URL.
//
// APIs (docs checked, docs/ENVIRONMENT.md §23): Menu, onMove(perform:), swipeActions(edge:allowsFullSwipe:),
//   contextMenu, accessibilityAction(named:).
import SwiftUI
import TimetableCore
import TimetableUI

struct AttachmentsSection: View {
    @Binding var attachments: [AttachmentRef]
    /// The task that owns the attachments.
    let ownerID: TaskItem.ID

    @Environment(AttachmentEditorSession.self) private var session: AttachmentEditorSession?

    init(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID) {
        _attachments = attachments
        self.ownerID = ownerID
    }

    private var visible: [AttachmentRef] { AttachmentReferences.visible(attachments) }

    var body: some View {
        Section {
            if let session {
                if visible.isEmpty && session.importingCount == 0 {
                    Text("attachments.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(visible) { ref in
                    row(ref, session: session)
                }
                .onMove { source, destination in session.move(from: source, to: destination, in: $attachments) }
                if session.importingCount > 0 {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("attachments.importing").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                addMenu(session)
            } else {
                // Not hosted (programming error): never offer actions without the host's presenters.
                Text("attachments.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("attachments.section.title")
        } footer: {
            if let text = session?.usageText, !visible.isEmpty || (session?.usage ?? 0) > 0 {
                Text(verbatim: text)
            }
        }
    }

    // MARK: Pieces

    private func row(_ ref: AttachmentRef, session: AttachmentEditorSession) -> some View {
        AttachmentRow(ref: ref, fileURL: session.fileURLs[ref.id], locale: session.locale, player: session.player) {
            session.activate(ref)
        }
        .contextMenu { rowActions(ref, session: session) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { session.requestDelete(ref, in: $attachments) } label: {
                Label { Text("editor.common.delete") } icon: { Image(systemName: "trash") }
            }
            Button { session.requestRename(ref, in: $attachments) } label: {
                Label { Text("attachments.rename") } icon: { Image(systemName: "pencil") }
            }
        }
        .accessibilityAction(named: Text("attachments.rename")) { session.requestRename(ref, in: $attachments) }
        .accessibilityAction(named: Text("attachments.moveUp")) { session.move(ref, by: -1, in: $attachments) }
        .accessibilityAction(named: Text("attachments.moveDown")) { session.move(ref, by: 1, in: $attachments) }
        .accessibilityAction(named: Text("editor.common.delete")) { session.requestDelete(ref, in: $attachments) }
    }

    private func addMenu(_ session: AttachmentEditorSession) -> some View {
        Menu {
            Button { session.requestPhoto(into: $attachments) } label: {
                Label { Text("attachments.add.photo") } icon: { Image(systemName: "photo.on.rectangle") }
            }
            Button { session.requestFile(into: $attachments) } label: {
                Label { Text("attachments.add.file") } icon: { Image(systemName: "doc") }
            }
            Button { session.requestLink(into: $attachments) } label: {
                Label { Text("attachments.add.link") } icon: { Image(systemName: "link") }
            }
            Button { session.requestVoiceNote(into: $attachments) } label: {
                Label { Text("attachments.add.voiceNote") } icon: { Image(systemName: "mic") }
            }
        } label: {
            Label { Text("attachments.add") } icon: { Image(systemName: "paperclip") }
        }
    }

    @ViewBuilder private func rowActions(_ ref: AttachmentRef, session: AttachmentEditorSession) -> some View {
        if ref.kind != .link, ref.kind != .voiceNote, session.fileURLs[ref.id] != nil {
            Button { session.activate(ref) } label: {
                Label { Text("attachments.preview") } icon: { Image(systemName: "eye") }
            }
        }
        if ref.kind == .voiceNote, let url = session.fileURLs[ref.id] {
            Button { session.previewURL = url } label: {
                Label { Text("attachments.preview") } icon: { Image(systemName: "eye") }
            }
        }
        if ref.kind == .link {
            Button { session.activate(ref) } label: {
                Label { Text("attachments.link.open.confirm") } icon: { Image(systemName: "safari") }
            }
        }
        Button { session.requestRename(ref, in: $attachments) } label: {
            Label { Text("attachments.rename") } icon: { Image(systemName: "pencil") }
        }
        Button { session.move(ref, by: -1, in: $attachments) } label: {
            Label { Text("attachments.moveUp") } icon: { Image(systemName: "arrow.up") }
        }
        .disabled(visible.first?.id == ref.id)
        Button { session.move(ref, by: 1, in: $attachments) } label: {
            Label { Text("attachments.moveDown") } icon: { Image(systemName: "arrow.down") }
        }
        .disabled(visible.last?.id == ref.id)
        Button(role: .destructive) { session.requestDelete(ref, in: $attachments) } label: {
            Label { Text("editor.common.delete") } icon: { Image(systemName: "trash") }
        }
    }
}
