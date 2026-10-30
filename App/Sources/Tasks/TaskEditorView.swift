// The task editor (routes `tasks.editor` and `tasks.editor-new`): title, kind, subject, due (none / date / date + time /
// the next lesson of the subject), priority, notes, subtasks (add, check, reorder, delete), repetition (daily / weekly
// with weekdays / monthly, interval, end date), the reminder-override section and the attachments section (both owned by
// other stages, embedded here). Cancel / Save with a discard confirmation come from `EditorScaffold`; blocking problems
// show inline under the section they belong to and disable Save.
// All decisions live in `TaskDraft` (TimetableUI, Linux-tested); this file only draws and bridges.
// Draft pattern as in EditorSupport.swift (no State(initialValue:)).
// APIs: Form, Section(content:header:footer:), Picker, Stepper, Toggle, LazyVGrid(columns:) with GridItem(.adaptive),
//       ForEach($bindings) { $element in }, onDelete(perform:), onMove(perform:), EditMode via environment(\.editMode, _),
//       confirmationDialog, onChange(of:) (two-parameter form, iOS 17), TextField(text:prompt:axis:label:), lineLimit(_:).
import SwiftUI
import TimetableCore
import TimetableUI

/// What the editor opens on.
enum TaskEditorMode {
    /// Edit the existing task.
    case edit(TaskItem.ID)
    /// Create a task with this (pre-generated) ID.
    case new(TaskItem.ID)
}

struct TaskEditorView: View {
    let mode: TaskEditorMode
    /// Phase 3 C1: a new task for one lesson occurrence (subject, due date, link); ignored when editing.
    var prefill: TaskPrefill?
    /// The timetable of the prefilled lesson.
    var prefillTimetableID: Timetable.ID?
    @Environment(AppModel.self) private var model

    var body: some View {
        if let draft = initialDraft() {
            TaskEditorBody(initial: draft)
        } else {
            EditorUnavailableView(messageKey: "tasks.editor.unavailable")
        }
    }

    private func initialDraft() -> TaskDraft? {
        guard let database = model.database else { return nil }
        switch mode {
        case .edit(let id):
            guard let task = database.tasks.first(where: { $0.id == id && !$0.isDeleted }) else { return nil }
            return TaskDraft(task: task, today: model.today)
        case .new(let id):
            if let prefill {
                return prefill.draft(newWithID: id, today: model.today,
                                     timetableID: prefillTimetableID ?? model.activeTimetable?.id)
            }
            return TaskDraft(newWithID: id, today: model.today, timetableID: model.activeTimetable?.id)
        }
    }
}

struct TaskEditorBody: View {
    let initial: TaskDraft
    @Environment(AppModel.self) private var model
    /// Attachment presenters, store protection and in-flight copies for this editor (B3). While a copy runs, Save and
    /// swipe-to-dismiss are disabled so the attachment cannot be dropped.
    @State private var attachmentSession = AttachmentEditorSession()

    var body: some View {
        EditorScaffold(
            titleKey: initial.isNew ? "tasks.editor.title.new" : "tasks.editor.title.edit",
            initial: initial,
            canSave: { $0.canSave },
            save: { draft in
                // QA fix Q5: merged with the task as stored NOW, so a "Mark as Done" from a notification while the
                // editor was open is kept, and a task deleted meanwhile is not resurrected (inline error instead).
                let stored = model.database?.tasks.first { $0.id == draft.taskID }
                switch draft.taskForSave(now: model.now, stored: stored) {
                case nil: return nil
                case .deletedMeanwhile?: return .failed(.notFound(.task, draft.taskID.uuid))
                case .save(let task)?: return model.apply(.upsert(task), origin: .userSave)
                }
            },
            isBusy: attachmentSession.importingCount > 0,
            content: { draft in TaskFormContent(draft: draft) })
        .attachmentsHost(attachmentSession, initial: initial.attachments)
    }
}

private struct TaskFormContent: View {
    @Binding var draft: TaskDraft
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newSubtask = ""
    @State private var editMode: EditMode = .inactive
    @State private var confirmingDelete = false

    var body: some View {
        titleSection
        dueSection
        prioritySection
        subtasksSection
        repeatSection
        ReminderOverrideSection(override: $draft.reminderOverride, target: ReminderTarget(rawValue: draft.kind.rawValue))
        AttachmentsSection(attachments: $draft.attachments, ownerID: draft.taskID)
        if !draft.isNew {
            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label { Text("tasks.action.delete") } icon: { Image(systemName: "trash") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .confirmationDialog("tasks.delete.title", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("tasks.delete.confirm", role: .destructive) {
                        model.apply(.delete(draft.taskID))
                        dismiss()
                    }
                    Button("editor.common.cancel", role: .cancel) {}
                } message: {
                    Text(verbatim: model.renderer.format(key: "tasks.delete.message", arguments: [.text(draft.title)]))
                }
            }
        }
    }

    // MARK: Title, kind, subject

    private var subjects: [Subject] {
        let timetableID = draft.timetableID ?? model.activeTimetable?.id
        let candidates = (model.database?.subjects ?? []).filter { subject in
            !subject.isDeleted && (subject.timetableID == timetableID || subject.id == draft.subjectID)
        }
        // Display order (`SubjectOrder`); a selected subject of another timetable is grouped by the timetables order.
        return SubjectOrder.sorted(candidates, timetableOrder: [timetableID].compactMap { $0 } + model.timetables.map(\.id),
                                   locale: model.formatter.locale)
    }

    private var kindOptions: [TaskKind] {
        TaskKind.knownValues + (TaskKind.knownValues.contains(draft.kind) ? [] : [draft.kind])
    }

    private var titleSection: some View {
        Section {
            EditorTitleField(promptKey: "tasks.field.title.prompt", text: $draft.title, axis: .vertical,
                             missingHintKey: TaskDraft.Issue.titleEmpty.l10nKey)
            Picker(selection: $draft.kind) {
                ForEach(kindOptions, id: \.rawValue) { kind in
                    if let key = TaskL10nKeys.kind(kind) {
                        Text(LocalizedStringKey(key)).tag(kind)
                    } else {
                        Text(verbatim: kind.rawValue).tag(kind)
                    }
                }
            } label: {
                Text("tasks.field.kind")
            }
            if let key = TaskL10nKeys.kindHint(draft.kind) {   // D5 / U2-2: what the type means, in one line
                Text(LocalizedStringKey(key)).font(.footnote).foregroundStyle(.secondary)
            }
            Picker(selection: Binding(get: { draft.subjectID }, set: chooseSubject)) {
                Text("tasks.subject.none").tag(Subject.ID?.none)
                ForEach(subjects, id: \.id) { subject in
                    Text(verbatim: subject.name).tag(Subject.ID?.some(subject.id))
                }
            } label: {
                Text("tasks.field.subject")
            }
        }
    }

    private func chooseSubject(_ id: Subject.ID?) {
        draft.setSubject(id)
        if let id, let subject = subjects.first(where: { $0.id == id }) { draft.timetableID = subject.timetableID }
        resolveNextLesson()
    }

    // MARK: Due

    private func resolveNextLesson() {
        guard draft.dueMode == .nextLesson else { return }
        draft.nextLesson = TaskSupport.nextLesson(subjectID: draft.subjectID, model: model)
    }

    private var dueSection: some View {
        Section {
            Picker(selection: Binding(get: { draft.dueMode }, set: { newMode in
                draft.setDueMode(newMode)
                resolveNextLesson()
            })) {
                ForEach(TaskDraft.DueMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(TaskL10nKeys.dueMode(mode))).tag(mode)
                }
            } label: {
                Text("tasks.field.due")
            }
            .labelledBySectionHeader()   // M1: the header already says "Due"
            switch draft.dueMode {
            case .none:
                EmptyView()
            case .date:
                DateRow(titleKey: "tasks.field.date", date: $draft.dueDate)
            case .dateTime:
                DateRow(titleKey: "tasks.field.date", date: $draft.dueDate)
                TimeRow(titleKey: "tasks.field.time", time: $draft.dueTime)
            case .nextLesson:
                if let lesson = draft.nextLesson {
                    Label {
                        Text(verbatim: nextLessonText(lesson))
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
            }
        } header: {
            Text("tasks.editor.section.due")
        } footer: {
            IssueFooter(issues: draft.issues.filter { $0 == .nextLessonNeedsSubject || $0 == .nextLessonNotFound })
        }
    }

    private func nextLessonText(_ lesson: NextLesson) -> String {
        let date = model.formatter.date(lesson.date, style: .full)
        guard let start = lesson.startTime else {
            return model.renderer.format(key: "tasks.editor.due.nextLesson.when", arguments: [.text(date)])
        }
        return model.renderer.format(key: "tasks.editor.due.nextLesson.whenAt",
                                     arguments: [.text(date), .text(model.formatter.time(start))])
    }

    // MARK: Priority and notes

    @ViewBuilder
    private var prioritySection: some View {
        Section {
            Picker(selection: $draft.priority) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Text(LocalizedStringKey(TaskL10nKeys.priority(priority))).tag(priority)
                }
            } label: {
                Text("tasks.field.priority")
            }
        }
        Section {
            TextField(text: $draft.notes, prompt: Text(emptyPrompt), axis: .vertical) {
                Text("tasks.field.notes")
            }
            .lineLimit(3...8)
            .frame(minHeight: 44, alignment: .topLeading)
            .labelledBySectionHeader()   // M1 / U2-7: the header already says "Notes"
        } header: {
            Text("tasks.field.notes")
        }
    }

    // MARK: Subtasks

    private var subtasksSection: some View {
        Section {
            ForEach($draft.subtasks) { $subtask in
                HStack(alignment: .center, spacing: 4) {
                    Button { subtask.isDone.toggle() } label: {
                        Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(catalogKey: subtask.isDone ? "tasks.action.subtask.reopen" : "tasks.action.subtask.complete"))
                    TextField(text: $subtask.title, prompt: Text(emptyPrompt), axis: .vertical) {
                        Text("tasks.editor.subtask.title")
                    }
                    .strikethrough(subtask.isDone)
                }
            }
            .onDelete { draft.removeSubtasks(atOffsets: $0) }
            .onMove { draft.moveSubtasks(fromOffsets: $0, toOffset: $1) }
            LabeledTextField(titleKey: "tasks.editor.subtask.new", text: $newSubtask)
                .onSubmit(addSubtask)
                .submitLabel(.done)
            Button(action: addSubtask) {
                Label { Text("tasks.editor.subtask.add") } icon: { Image(systemName: "plus.circle.fill") }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(EditorText.trimmedOrNil(newSubtask) == nil)
        } header: {
            HStack {
                Text("tasks.field.subtasks")
                Spacer()
                if draft.subtasks.count > 1 {
                    Button {
                        editMode = editMode.isEditing ? .inactive : .active
                    } label: {
                        // M18 / U2-9: "Edit", like the other lists (it also reveals the drag handles).
                        Text(catalogKey: editMode.isEditing ? "tasks.editor.subtask.doneReordering" : "editor.common.edit")
                            .frame(minHeight: 44)
                    }
                    .textCase(nil)
                }
            }
        }
        .environment(\.editMode, $editMode)
    }

    private func addSubtask() {
        if draft.addSubtask(title: newSubtask, id: Subtask.ID(UUID())) { newSubtask = "" }
    }

    // MARK: Repeat

    private var repeatSection: some View {
        Section {
            Picker(selection: Binding(get: { draft.repeatMode }, set: { draft.setRepeatMode($0) })) {
                ForEach(TaskDraft.RepeatMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(TaskL10nKeys.repeatMode(mode))).tag(mode)
                }
            } label: {
                Text("tasks.field.repeat")
            }
            if let frequency = draft.repeatMode.frequency {
                Stepper(value: $draft.repeatInterval, in: 1...TaskDraft.maxInterval) {
                    Text(verbatim: TaskRepeatSummary.everyText(frequency: frequency, interval: draft.repeatInterval,
                                                               renderer: model.renderer) ?? "")
                }
                if draft.repeatMode == .weekly {
                    weekdayGrid
                }
                Toggle(isOn: $draft.hasUntil) {
                    Text("tasks.editor.repeat.until")
                }
                if draft.hasUntil {
                    DateRow(titleKey: "tasks.editor.repeat.untilDate", date: $draft.until)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                IssueFooter(issues: draft.issues.filter { $0 == .repeatNeedsDue || $0 == .untilBeforeDue })
                if draft.repeatMode == .weekly && draft.repeatWeekdays.isEmpty {
                    Text("tasks.editor.repeat.weekdaysNote")
                }
            }
        }
    }

    /// U2-11: the shared weekday chips (ink when on, an outline when off, a switch for VoiceOver).
    private var weekdayGrid: some View {
        WeekdayChips(days: Weekday.week(startingAt: model.calendarContext.firstWeekday),
                     isOn: { draft.repeatWeekdays.contains($0) },
                     setOn: { day, on in if on != draft.repeatWeekdays.contains(day) { draft.toggleWeekday(day) } })
    }
}

/// The inline validation messages of a section (icon + text, so colour is not the only cue), shown after the first
/// edit or a save attempt (M5, `ValidationMessage`).
private struct IssueFooter: View {
    let issues: [TaskDraft.Issue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.self) { issue in
                    ValidationMessage(key: issue.l10nKey, severity: issue == .titleEmpty ? .hint : .error)
                }
            }
        }
    }
}
