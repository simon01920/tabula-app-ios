// Read-only detail of one lesson occurrence (route `timetable.lesson-detail`, sheet from every timetable view and
// Today): subject, status, date/time/period, cycle weeks, the visible non-empty fields, what changed on this date
// with the usual value, and two actions: "Edit" (route `editor.lesson`) and "Change for this day"
// (route `editor.day-change`). Both are disabled with an explanation while the editor routes are not registered.
// Phase 3 C1: the task / exam badges under the status, and a "Homework & tasks" section with the tasks of this
// occurrence (`LessonWorkIndex` rule: linked to it, or due that day for its subject; open first, completed struck
// through; complete / reopen inline, tap → task detail) and "Add homework for this lesson", which opens the
// `tasks.editor-new` route with `EditorContext(.newTask(TaskPrefill))` (subject, due = this date, linked occurrence).
// Data comes from `LessonDetailModel` (TimetableUI, Linux-tested).
// APIs: NavigationStack, List, Section(content:header:footer:), LabeledContent(content:label:), ToolbarItem
//       (.cancellationAction / .primaryAction), Button(action:label:), disabled(_:), ContentUnavailableView,
//       presentationDetents(_:), Environment(\.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

/// A task opened from the lesson detail.
private struct LessonTaskTarget: Identifiable {
    let taskID: TaskItem.ID
    var id: String { taskID.uuidString }
}

/// Which occurrence a detail sheet shows.
struct LessonDetailTarget: Identifiable, Hashable {
    let timetableID: Timetable.ID
    let occurrenceID: OccurrenceID
    let date: LocalDate
    var id: String { occurrenceID.rawValue }

    init(_ lesson: ResolvedLesson) {
        timetableID = lesson.timetableID
        occurrenceID = lesson.id
        date = lesson.date
    }
}

struct LessonDetailView: View {
    let target: LessonDetailTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorPresentation?
    @State private var openTask: LessonTaskTarget?

    var body: some View {
        NavigationStack {
            content
                .sheet(item: $openTask) { target in
                    TaskDetailView(taskID: target.taskID)
                }
                .navigationTitle(Text("timetable.detail.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { openLessonEditor() } label: { Text("timetable.detail.edit") }
                            .disabled(lessonEditorContext == nil || !EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson))
                    }
                }
        }
        .editorSheet($editor)
    }

    private var detail: LessonDetailModel? {
        guard let database = model.database, let resolver = model.resolver(for: target.timetableID) else { return nil }
        return LessonDetailModel.make(occurrenceID: target.occurrenceID, date: target.date, resolver: resolver,
                                      database: database, formatter: model.formatter)
    }

    /// Tasks and exams of this occurrence (the whole day is indexed, as the matching rule needs).
    private var work: LessonWork {
        guard let resolver = model.resolver(for: target.timetableID) else { return LessonWork() }
        return LessonWorkSupport.index(dates: [target.date], resolver: resolver, database: model.database)[target.occurrenceID]
    }

    private var lessonEditorContext: EditorContext? {
        detail?.lessonID.map { EditorContext(timetableID: target.timetableID, target: .lesson($0)) }
    }

    @ViewBuilder
    private var content: some View {
        if let detail, let timetable = model.resolver(for: target.timetableID)?.timetable {
            List {
                headerSection(detail, timetable: timetable)
                whenSection(detail, timetable: timetable)
                if !detail.fields.isEmpty {
                    Section {
                        ForEach(detail.fields) { line in
                            LabeledContent {
                                Text(verbatim: line.text(renderer: model.renderer))
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Label { Text(LocalizedStringKey(Self.fieldNameKey(line.field))) } icon: {
                                    Image(systemName: line.symbolName)
                                }
                            }
                        }
                    }
                }
                tasksSection(detail)
                if !detail.changes.isEmpty {
                    Section {
                        ForEach(detail.changes) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(change.reason.l10nKey)).font(.body.weight(.semibold))
                                if let usual = change.usualValue {
                                    Text(verbatim: model.renderer.format(key: "timetable.detail.usually",
                                                                         arguments: [.text(usual)]))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("timetable.detail.changes")
                    }
                }
                actionsSection(detail)
            }
        } else {
            ContentUnavailableView {
                Label { Text("timetable.detail.missing") } icon: { Image(systemName: "questionmark.square.dashed") }
            } description: {
                EmptyView()
            } actions: {
                EmptyView()
            }
        }
    }

    private func headerSection(_ detail: LessonDetailModel, timetable: Timetable) -> some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                SubjectBadge(subject: detail.lesson.subject, size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: detail.lesson.subject.name)
                        .font(.title2.weight(.semibold))
                        .strikethrough(detail.lesson.status == .cancelled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = LessonStatusBadgeModel.make(status: detail.lesson.status, reasons: detail.reasons) {
                        LessonStatusBadge(badge)
                    }
                    if let badges = work.badges {
                        LessonWorkBadgeRow(badges: badges)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(
                lesson: detail.lesson, visibility: timetable.fieldVisibility, reasons: detail.reasons,
                badges: work.badges, renderer: model.renderer)))
        }
    }

    private func whenSection(_ detail: LessonDetailModel, timetable: Timetable) -> some View {
        Section {
            Label {
                Text(verbatim: model.formatter.date(detail.lesson.date, style: .full))
            } icon: {
                Image(systemName: "calendar")
            }
            Label {
                Text(verbatim: model.formatter.timeRange(detail.lesson.startTime, detail.lesson.endTime))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "clock")
            }
            if let number = detail.lesson.periodNumber {
                Label {
                    Text(verbatim: model.renderer.format(key: "timetable.detail.period", arguments: [.integer(Int64(number))]))
                } icon: {
                    Image(systemName: "number")
                }
            } else if let label = detail.lesson.periodLabel, !label.trimmingCharacters(in: .whitespaces).isEmpty {
                Label { Text(verbatim: label) } icon: { Image(systemName: "number") }
            }
            if !detail.cycleWeeks.isEmpty {
                let weeks = detail.cycleWeeks.compactMap { week in
                    CycleLabel.week(week, scheme: timetable.rotation,
                                    userLabel: model.resolver(for: timetable.id)?.rotation.label(forCycleWeek: week))
                        .map { $0.text(renderer: model.renderer) }
                }
                Label {
                    Text(verbatim: model.renderer.format(key: "timetable.detail.weeks",
                                                         arguments: [.text(model.formatter.list(weeks))]))
                } icon: {
                    Image(systemName: "repeat")
                }
            }
        }
    }

    /// "Homework & tasks": this occurrence's tasks (open, then completed) and "Add homework for this lesson".
    private func tasksSection(_ detail: LessonDetailModel) -> some View {
        let work = work
        let tasks = model.database?.tasks ?? []
        let byID = Dictionary(tasks.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let subjects = Dictionary((model.database?.subjects ?? []).filter { !$0.isDeleted }.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let now = model.calendarContext.local(from: model.now)
        let rows = (work.openTaskIDs + work.completedTaskIDs).compactMap { byID[$0] }
            .map { TaskRowModel(task: $0, subjects: subjects, now: now) }
        return Section {
            ForEach(rows) { row in
                TaskRowView(row: row, onOpen: { openTask = LessonTaskTarget(taskID: row.id) },
                            onToggle: { toggle(row) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: row.accessibilityLabel(renderer: model.renderer)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { openTask = LessonTaskTarget(taskID: row.id) }
                    .accessibilityAction(named: Text(catalogKey: row.isCompleted ? "tasks.action.reopen" : "tasks.action.complete")) {
                        toggle(row)
                    }
            }
            Button {
                editor = EditorPresentation.make(EditorContext.RouteID.newTask, context: EditorContext(
                    timetableID: target.timetableID, target: .newTask(TaskPrefill(lesson: detail.lesson))))
            } label: {
                Label { Text("timetable.detail.addHomework") } icon: { Image(systemName: "plus.circle.fill") }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.newTask))
        } header: {
            Text("timetable.detail.tasks")
        }
    }

    private func toggle(_ row: TaskRowModel) {
        if row.isCompleted {
            if let task = model.database?.tasks.first(where: { $0.id == row.id && !$0.isDeleted }) {
                model.apply(.upsert(TaskEdits.reopened(task)))
            }
        } else {
            model.apply(.completeTask(row.id, at: model.now))
        }
    }

    private func actionsSection(_ detail: LessonDetailModel) -> some View {
        let dayChangeAvailable = EditorRouteLookup.isAvailable(EditorContext.RouteID.dayChange)
        let lessonEditorAvailable = EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson)
        return Section {
            Button {
                editor = EditorPresentation.make(EditorContext.RouteID.dayChange, context: EditorContext(
                    timetableID: target.timetableID,
                    target: .dayChange(date: target.date, occurrence: target.occurrenceID, lessonID: detail.lessonID)))
            } label: {
                Label { Text("timetable.detail.changeDay") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
            }
            .disabled(!dayChangeAvailable)
        } footer: {
            if detail.lessonID == nil {
                Text("timetable.detail.oneOffFooter")
            } else if !dayChangeAvailable || !lessonEditorAvailable {
                Text("timetable.detail.editorsMissing")
            }
        }
    }

    private func openLessonEditor() {
        guard let context = lessonEditorContext else { return }
        editor = EditorPresentation.make(EditorContext.RouteID.lesson, context: context)
    }

    /// Catalog key of a field's name in the detail list.
    static func fieldNameKey(_ field: LessonField) -> String { DynamicL10nKeys.lessonDetailField(field) }
}
