// Read-only task detail (route `tasks.detail`, also the notification deep-link target): title and completion control,
// subject, kind, due date, priority, repetition, notes, subtasks that can be checked inline, an attachment count, and
// the actions Complete / Reopen, Edit and Delete. Empty fields are absent, never placeholders. Data comes from
// `TaskDetailModel` (TimetableUI, Linux-tested). If the task disappears (deleted here or on another device) the sheet
// shows a short message with Close.
// APIs: NavigationStack, List, Section, Button, confirmationDialog(_:isPresented:titleVisibility:), sheet(item:),
//       ToolbarItem(.cancellationAction / .primaryAction), ContentUnavailableView, Environment(\.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

/// Wraps a task ID so it can drive `sheet(item:)`.
private struct TaskEditTarget: Identifiable {
    let taskID: TaskItem.ID
    var id: String { taskID.uuidString }
}

struct TaskDetailView: View {
    let taskID: TaskItem.ID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editTarget: TaskEditTarget?
    @State private var confirmingDelete = false

    private var task: TaskItem? { model.database?.tasks.first { $0.id == taskID && !$0.isDeleted } }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    detailList(task)
                } else {
                    ContentUnavailableView {
                        Label { Text("tasks.detail.missing") } icon: { Image(systemName: "questionmark.square.dashed") }
                    } description: {
                        EmptyView()
                    }
                }
            }
            .navigationTitle(Text("tasks.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
                if task != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { editTarget = TaskEditTarget(taskID: taskID) } label: { Text("tasks.action.edit") }
                    }
                }
            }
        }
        // Deleted in the editor above (or on another device) while the detail is open: close it.
        .onChange(of: task == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(item: $editTarget) { target in
            TaskEditorView(mode: .edit(target.taskID))
        }
        .confirmationDialog("tasks.delete.title", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("tasks.delete.confirm", role: .destructive) {
                model.apply(.delete(taskID))
                dismiss()
            }
            Button("editor.common.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: model.renderer.format(key: "tasks.delete.message", arguments: [.text(task?.title ?? "")]))
        }
    }

    private var subjects: [Subject.ID: Subject] {
        Dictionary((model.database?.subjects ?? []).filter { !$0.isDeleted }.map { ($0.id, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func detailList(_ task: TaskItem) -> some View {
        let detail = TaskDetailModel(task: task, subjects: subjects, now: model.calendarContext.local(from: model.now))
        let row = detail.row
        return List {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    TaskCompletionControl(isCompleted: row.isCompleted, subject: row.subject) { toggle(task) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: row.title)
                            .font(.title3.weight(.semibold))
                            .strikethrough(row.isCompleted)
                            .foregroundStyle(row.isCompleted ? Color.secondary : Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subject = row.subject {
                            HStack(spacing: 8) {
                                SubjectBadge(subject: subject, size: 24)
                                Text(verbatim: subject.name).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if row.isCompleted {
                            Label { Text("tasks.detail.completed") } icon: { Image(systemName: "checkmark.circle.fill") }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            factsSection(detail)
            if let notes = detail.notes {
                Section {
                    Text(verbatim: notes)
                } header: {
                    Text("tasks.field.notes")
                }
            }
            if !detail.subtasks.isEmpty {
                Section {
                    ForEach(detail.subtasks, id: \.id) { subtask in
                        SubtaskCheckRow(subtask: subtask) { toggleSubtask(subtask.id, in: task) }
                    }
                } header: {
                    // "2 of 5 subtasks complete" for VoiceOver (the visible "2/5" is the short form of the same fact).
                    HStack {
                        Text("tasks.field.subtasks")
                        Spacer()
                        Text(verbatim: model.renderer.format(key: "tasks.row.subtasks", arguments: [
                            .integer(Int64(row.subtasksDone)), .integer(Int64(row.subtasksTotal)),
                        ]))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("tasks.field.subtasks"))
                    .accessibilityValue(Text(verbatim: model.renderer.format(key: "a11y.task.subtasks", arguments: [
                        .integer(Int64(row.subtasksDone)), .integer(Int64(row.subtasksTotal)),
                    ])))
                    .accessibilityAddTraits(.isHeader)
                }
            }
            Section {
                Button { toggle(task) } label: {
                    Label {
                        Text(catalogKey: task.isCompleted ? "tasks.action.reopen" : "tasks.action.complete")
                    } icon: {
                        Image(systemName: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label { Text("tasks.action.delete") } icon: { Image(systemName: "trash") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func factsSection(_ detail: TaskDetailModel) -> some View {
        let row = detail.row
        let kindText: String = detail.kindKey.map { model.renderer.string(forKey: $0) } ?? detail.kindRawValue
        Section {
            LabeledContent {
                Text(verbatim: kindText).multilineTextAlignment(.trailing)
            } label: {
                Text("tasks.field.kind")
            }
            if let due = row.due {
                LabeledContent {
                    // Only an overdue task gets an icon: a Label whose icon closure can be empty lays out with a
                    // stretched, blank icon slot, so the plain Text is used otherwise.
                    // M22: every value is secondary text; only an overdue due is correction red (with its icon).
                    Group {
                        if row.isOverdue {
                            Label {
                                Text(verbatim: due.text(renderer: model.renderer))
                            } icon: {
                                Image(AppSymbol.overdue)
                            }
                            .foregroundStyle(Color.correction)
                        } else {
                            Text(verbatim: due.text(renderer: model.renderer))
                        }
                    }
                    .multilineTextAlignment(.trailing)
                } label: {
                    Text("tasks.field.due")
                }
            }
            if let date = detail.linkedLessonDate {
                Label {
                    Text(verbatim: model.renderer.format(key: "tasks.detail.linkedLesson", arguments: [
                        .text(model.formatter.date(date, style: .full)),
                    ]))
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
            }
            if row.priority != .normal {
                LabeledContent {
                    Text(LocalizedStringKey(TaskL10nKeys.priority(row.priority))).multilineTextAlignment(.trailing)
                } label: {
                    Text("tasks.field.priority")
                }
            }
            if let summary = detail.repeatSummary {
                // M22: the rule on one line ("Weekly on Tuesday"), same label and value style as the other rows.
                LabeledContent {
                    Text(verbatim: summary.line(renderer: model.renderer)).multilineTextAlignment(.trailing)
                } label: {
                    Text("tasks.field.repeat")
                }
                if let until = summary.untilText(renderer: model.renderer) {
                    Text(verbatim: until)
                }
            }
            if row.attachmentCount > 0 {
                Label {
                    Text(verbatim: model.renderer.format(key: "tasks.detail.attachments",
                                                         arguments: [.integer(Int64(row.attachmentCount))]))
                } icon: {
                    Image(systemName: "paperclip")
                }
            }
        }
    }

    // MARK: Actions

    private func toggle(_ task: TaskItem) {
        if task.isCompleted {
            model.apply(.upsert(TaskEdits.reopened(task)))
        } else {
            model.apply(.completeTask(task.id, at: model.now))
        }
    }

    private func toggleSubtask(_ id: Subtask.ID, in task: TaskItem) {
        guard let edited = TaskEdits.togglingSubtask(id, in: task, now: model.now) else { return }
        model.apply(.upsert(edited))
    }
}

/// One checkable subtask line (44 pt target; the check shape differs between states).
private struct SubtaskCheckRow: View {
    let subtask: Subtask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: subtask.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(subtask.completedAt == nil ? Color.secondary : Color.accentColor)
                Text(verbatim: subtask.title)
                    .strikethrough(subtask.completedAt != nil)
                    .foregroundStyle(subtask.completedAt == nil ? Color.primary : Color.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: subtask.title))
        .accessibilityValue(Text(catalogKey: subtask.completedAt == nil ? "tasks.a11y.subtask.open" : "tasks.a11y.subtask.done"))
        .accessibilityAddTraits(.isButton)
    }
}
