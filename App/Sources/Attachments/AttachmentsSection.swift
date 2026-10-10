// STUB (Phase 3 Stage A) of the task editor's attachments section. Stage B1 embeds it in the task editor's Form;
// stage B3 replaces the body (photos, files, links, voice notes; files in the App Group under
// `Attachments/<attachmentID>/<fileName>`, PHASE3_PLAN §0.7).
// KEEP THIS SIGNATURE (B1 and B3 work against it in parallel):
//     AttachmentsSection(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID)
// The body is a `Section` (place it directly inside a `Form` / `List`). It edits only the binding; the editor saves the
// task (and with it the refs) through `model.apply(.upsert(task))`.
import SwiftUI
import TimetableCore

struct AttachmentsSection: View {
    @Binding var attachments: [AttachmentRef]
    /// The task that owns the attachments (B3 uses it for the storage folder and orphan cleanup).
    let ownerID: TaskItem.ID

    init(attachments: Binding<[AttachmentRef]>, ownerID: TaskItem.ID) {
        _attachments = attachments
        self.ownerID = ownerID
    }

    var body: some View {
        Section {
            Text("attachments.placeholder")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("attachments.section.title")
        }
    }
}
