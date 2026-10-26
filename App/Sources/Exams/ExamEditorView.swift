// The exam editor (stage B2; routes `exams.editor`, `exams.editor-new`): subject, title, type, date, optional start /
// end time (end must be after start), room, building (if the timetable shows them), topics (add, delete, drag to
// reorder), notes (if shown), the per-exam reminder override (stage B4 fills the section) and delete.
// Cancel / Save with a discard confirmation come from `EditorScaffold` (Editors/EditorSupport.swift). Fields the
// timetable hides keep their stored value (ExamDraft.makeExam). Enabled-but-empty fields are inputs with a visible
// label and no placeholder text (field rule).
// Logic: Packages/TimetableUI/Sources/TimetableUI/Exams/ExamDraft.swift (Linux-tested).
// APIs: Form via EditorScaffold, Picker(selection:content:label:), Toggle(isOn:label:), ForEach($binding) with
//   onMove(perform:) / onDelete(perform:), Environment(\.editMode) (EditMode.active), confirmationDialog,
//   Button(role: .destructive).
import SwiftUI
import TimetableCore
import TimetableUI

struct ExamEditorView: View {
    let target: ExamEditorTarget
    @Environment(AppModel.self) private var model
    @State private var newID = Exam.ID(UUID())

    var body: some View {
        if let draft = makeDraft() {
            ExamEditorBody(initial: draft)
        } else {
            EditorUnavailableView(messageKey: "exams.editor.unavailable")
        }
    }

    private func makeDraft() -> ExamDraft? {
        switch target {
        case .existing(let id):
            return model.database?.exams.first { $0.id == id && !$0.isDeleted }.map(ExamDraft.init(exam:))
        case .new:
            guard model.database != nil else { return nil }
            return ExamDraft(newOn: model.today, timetableID: model.activeTimetable?.id, id: newID)
        }
    }
}

private struct ExamEditorBody: View {
    let initial: ExamDraft
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorScaffold(
            titleKey: initial.isNew ? "exams.editor.title.new" : "exams.editor.title.edit",
            initial: initial,
            canSave: { $0.canSave },
            save: { draft in
                let visibility = model.database.map { ExamFacts.visibility(timetableID: draft.timetableID, in: $0) } ?? .all
                // QA fix Q5: merged with the exam as stored NOW (a "Mark as Done" meanwhile is kept; a deletion
                // meanwhile is not undone: inline error instead).
                let stored = model.database?.exams.first { $0.id == draft.examID }
                switch draft.examForSave(visibility: visibility, stored: stored) {
                case nil: return nil
                case .deletedMeanwhile?: return .failed(.notFound(.exam, draft.examID.uuid))
                case .save(let exam)?: return model.apply(.upsert(exam), origin: .userSave)
                }
            },
            content: { draft in ExamFormContent(draft: draft) })
    }
}

private struct ExamFormContent: View {
    @Binding var draft: ExamDraft
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var deleteFailed = false

    private var visibility: FieldVisibility {
        model.database.map { ExamFacts.visibility(timetableID: draft.timetableID, in: $0) } ?? .all
    }

    private var subjects: [Subject] {
        let timetableID = draft.timetableID ?? model.activeTimetable?.id
        let candidates = (model.database?.subjects ?? []).filter { !$0.isDeleted && ($0.timetableID == timetableID || $0.id == draft.subjectID) }
        // Display order (`SubjectOrder`); a selected subject of another timetable is grouped by the timetables order.
        return SubjectOrder.sorted(candidates, timetableOrder: [timetableID].compactMap { $0 } + model.timetables.map(\.id),
                                   locale: model.formatter.locale)
    }

    private var texts: ExamTexts { ExamTexts(renderer: model.renderer) }

    var body: some View {
        mainSection
        timeSection
        if visibility.isVisible(.room) || visibility.isVisible(.building) { placeSection }
        topicsSection
        if visibility.isVisible(.notes) {
            Section { LabeledTextField(titleKey: "exams.editor.notes", text: $draft.notes, axis: .vertical) }
        }
        ReminderOverrideSection(override: $draft.reminderOverride, target: .exam)
        if !draft.isNew { deleteSection }
    }

    // MARK: Sections

    @ViewBuilder
    private func subjectItem(_ subject: Subject) -> some View {
        if case .emoji(let emoji)? = subject.symbol {
            Text(verbatim: model.renderer.format(key: "editor.subject.emojiName", arguments: [.text(emoji), .text(subject.name)]))
        } else {
            Text(verbatim: subject.name)
        }
    }

    private var mainSection: some View {
        Section {
            Picker(selection: $draft.subjectID) {
                Text("exams.editor.subject.none").tag(Subject.ID?.none)
                ForEach(subjects) { subject in
                    subjectItem(subject).tag(Subject.ID?.some(subject.id))
                }
            } label: {
                Text("exams.editor.subject")
            }
            EditorTitleField(promptKey: "exams.editor.name.prompt", text: $draft.title,
                             missingHintKey: ExamDraft.Issue.noTitle.l10nKey)
            Picker(selection: $draft.kindRaw) {
                ForEach(draft.kindChoices, id: \.rawValue) { kind in
                    Text(verbatim: texts.kind(kind)).tag(kind.rawValue)
                }
            } label: {
                Text("exams.editor.kind")
            }
            DateRow(titleKey: "exams.editor.date", date: $draft.date)
        }
    }

    private var timeSection: some View {
        Section {
            Toggle(isOn: Binding(get: { draft.hasStart }, set: { draft.setHasStart($0) })) {
                Text("exams.editor.hasStart")
            }
            if draft.hasStart {
                TimeRow(titleKey: "exams.editor.start", time: $draft.start)
                Toggle(isOn: Binding(get: { draft.hasEnd }, set: { draft.setHasEnd($0) })) {
                    Text("exams.editor.hasEnd")
                }
                if draft.hasEnd {
                    TimeRow(titleKey: "exams.editor.end", time: $draft.end)
                }
            }
        } footer: {
            // The missing-title hint sits under the title field now (M6); this footer keeps the time errors.
            if draft.issues.contains(.endNotAfterStart) {
                ValidationMessage(key: ExamDraft.Issue.endNotAfterStart.l10nKey)
            }
        }
    }

    private var placeSection: some View {
        Section {
            if visibility.isVisible(.room) { LabeledTextField(titleKey: "exams.editor.room", text: $draft.room) }
            if visibility.isVisible(.building) { LabeledTextField(titleKey: "exams.editor.building", text: $draft.building) }
        }
    }

    private var topicsSection: some View {
        Section {
            ForEach($draft.topics) { $topic in
                TextField(text: $topic.text, prompt: Text(emptyPrompt)) { Text("exams.editor.topic") }
                    .frame(minHeight: 44)
            }
            .onDelete { draft.removeTopics(at: $0) }
            .onMove { draft.moveTopics(from: $0, to: $1) }
            // Topics are always in edit mode: drag handles and delete controls, no separate Edit button.
            .environment(\.editMode, .constant(.active))
            Button { draft.addTopic() } label: {
                Label { Text("exams.editor.topics.add") } icon: { Image(systemName: "plus.circle.fill") }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("exams.editor.topics")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("exams.editor.delete").frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            if deleteFailed { Text("editor.error.failed").foregroundStyle(.red) }
        }
        .confirmationDialog("exams.editor.delete.title", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("exams.editor.delete.confirm", role: .destructive) {
                if case .applied = model.apply(.delete(draft.examID)) {
                    dismiss()
                } else {
                    deleteFailed = true
                }
            }
            Button("editor.common.cancel", role: .cancel) {}
        }
    }
}
