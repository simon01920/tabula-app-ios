// The quick-entry sheet behind the Tasks tab's "+" (route `tasks.quick-add`; Phase 4U U2, Opus review R2 / H6 / M21,
// decision D5): a focused title ("What do you need to do?"), the subject (default: the current or next lesson's), the
// due (Next lesson (date) / Tomorrow / Pick a date…, default the next lesson for Homework) and the type as a segmented
// Homework / To-do / Assignment with a one-line description. "More options" swaps the sheet's content for the full task
// editor on the same draft (priority, notes, subtasks, repeat, reminder, attachments). Detents medium and large; Add is
// the confirmation action and stays disabled until there is a title.
// It edits a plain `TaskDraft` through `EditorScaffold`: the model, validation, save merge and reminder planning are the
// task editor's; only the defaults live in `TaskQuickEntry` (TimetableUI, Linux-tested).
// HIG (apple-design references): sheets.md (a short task, a way out, medium detent first), text-fields.md (a prompt
// that says what to enter), segmented-controls.md (few, short options; a menu at accessibility sizes), pickers.md,
// entering-data.md (defaults from context, choices over typing).
// APIs: presentationDetents(_:selection:), presentationDragIndicator(_:), FocusState, Picker (.segmented / .menu),
//       DatePicker through DateRow, @Environment(\.dynamicTypeSize).
import SwiftUI
import TimetableCore
import TimetableUI

struct TaskQuickEntrySheet: View {
    let id: TaskItem.ID
    @Environment(AppModel.self) private var model
    /// Set by "More options": the current draft, now shown in the full editor.
    @State private var expanded: TaskDraft?
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        Group {
            if let expanded {
                TaskEditorBody(initial: expanded)
            } else if model.database != nil {
                let initial = initialDraft()
                EditorScaffold(
                    titleKey: "tasks.editor.title.new",
                    initial: initial,
                    canSave: { $0.canSave },
                    save: { draft in
                        switch draft.taskForSave(now: model.now, stored: nil) {
                        case nil: return nil
                        case .deletedMeanwhile?: return .failed(.notFound(.task, draft.taskID.uuid))
                        case .save(let task)?: return model.apply(.upsert(task), origin: .userSave)
                        }
                    },
                    confirmKey: "tasks.quickAdd.add",
                    content: { draft in
                        TaskQuickEntryForm(draft: draft) { more in
                            expanded = more
                            detent = .large
                        }
                    })
            } else {
                EditorUnavailableView(messageKey: "tasks.editor.unavailable")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func initialDraft() -> TaskDraft {
        let subjectID = TaskSupport.currentOrNextSubject(model: model)
        return TaskQuickEntry.initialDraft(id: id, today: model.today, timetableID: model.activeTimetable?.id,
                                           subjectID: subjectID, nextLesson: TaskSupport.nextLesson(subjectID: subjectID, model: model))
    }
}

private struct TaskQuickEntryForm: View {
    @Binding var draft: TaskDraft
    let onMore: (TaskDraft) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var titleFocused: Bool
    /// The user has not chosen the type / the due herself: they follow the subject (M21).
    @State private var followKind = true
    @State private var followDue = true
    /// The due option the user picked last; nil = what the draft represents.
    @State private var pickedDue: QuickDue?

    private var subjects: [Subject] {
        guard let timetableID = draft.timetableID ?? model.activeTimetable?.id, let database = model.database else { return [] }
        return SubjectOrder.live(database, timetableID: timetableID, locale: model.formatter.locale)
    }

    var body: some View {
        let nextLesson = TaskSupport.nextLesson(subjectID: draft.subjectID, model: model)
        Group {
            Section {
                EditorTitleField(promptKey: "tasks.quick.prompt", text: $draft.title, axis: .vertical,
                                 missingHintKey: TaskDraft.Issue.titleEmpty.l10nKey, focus: $titleFocused)
            }
            Section {
                subjectPicker(nextLesson)
                duePicker(nextLesson)
                if (pickedDue ?? TaskQuickEntry.choice(of: draft, today: model.today)) == .date {
                    DateRow(titleKey: "tasks.field.date", date: $draft.dueDate)
                }
            }
            Section {
                kindPicker(nextLesson)
            } header: {
                Text("tasks.field.kind")
            } footer: {
                if let hint = TaskL10nKeys.kindHint(draft.kind) { Text(LocalizedStringKey(hint)) }
            }
            Section {
                Button { onMore(draft) } label: {
                    Text("tasks.quick.more").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    private func subjectPicker(_ nextLesson: NextLesson?) -> some View {
        Picker(selection: Binding(get: { draft.subjectID }, set: { id in
            let lesson = TaskSupport.nextLesson(subjectID: id, model: model)
            draft.quickChooseSubject(id, nextLesson: lesson, today: model.today, followKind: followKind, followDue: followDue)
            if followDue { pickedDue = nil }
        })) {
            Text("tasks.subject.none").tag(Subject.ID?.none)
            ForEach(subjects, id: \.id) { subject in
                Text(verbatim: subject.name).tag(Subject.ID?.some(subject.id))
            }
        } label: {
            Text("tasks.field.subject")
        }
    }

    private func duePicker(_ nextLesson: NextLesson?) -> some View {
        Picker(selection: Binding(get: { pickedDue ?? TaskQuickEntry.choice(of: draft, today: model.today) }, set: { choice in
            followDue = false
            pickedDue = choice
            draft.quickApply(choice, nextLesson: nextLesson, today: model.today)
        })) {
            ForEach(TaskQuickEntry.options(nextLesson: nextLesson), id: \.self) { option in
                switch option {
                case .nextLesson:
                    Text(verbatim: nextLesson.map(nextLessonText) ?? "").tag(option)
                case .tomorrow:
                    Text("tasks.quickAdd.due.tomorrow").tag(option)
                case .date:
                    Text("tasks.quick.due.pick").tag(option)
                }
            }
        } label: {
            Text("tasks.field.due")
        }
    }

    private func nextLessonText(_ lesson: NextLesson) -> String {
        model.renderer.format(key: "tasks.quick.due.nextLesson",
                              arguments: [.text(model.formatter.date(lesson.date, style: .weekdayDayMonth))])
    }

    /// Segmented while there is room; a menu at accessibility sizes (three long words do not fit one line there).
    @ViewBuilder
    private func kindPicker(_ nextLesson: NextLesson?) -> some View {
        let picker = Picker(selection: Binding(get: { draft.kind }, set: { kind in
            followKind = false
            draft.quickChooseKind(kind, nextLesson: nextLesson, today: model.today, followDue: followDue)
            if followDue { pickedDue = nil }
        })) {
            ForEach(TaskQuickEntry.kinds, id: \.rawValue) { kind in
                if let key = TaskL10nKeys.kind(kind) { Text(LocalizedStringKey(key)).tag(kind) }
            }
        } label: {
            Text("tasks.field.kind")
        }
        .labelledBySectionHeader()   // the section header already says "Type" (M1)
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }
}
