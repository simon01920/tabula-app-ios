// The Tasks tab (route `tasks`, plus `tasks.upcoming|overdue|completed` for screenshots): segment chips with counts
// (Overdue highlighted), a subject filter and sort menu, a quick-add section (title + optional subject; the due date is
// the subject's next lesson, else tomorrow), the task rows with swipe actions (complete / reopen, delete with
// confirmation) and empty states. Logic lives in TimetableUI/Tasks (TaskListModel, TaskRowModel, TaskQuickAdd,
// NextLessonResolver; Linux-tested). Keep the type name `TasksRootView` and its no-argument init: the app shell uses it.
// Writes go through `model.apply` only (`.completeTask`, `.upsert`, `.delete`); the reminder coordinator re-plans by itself.
// APIs: NavigationStack, List, Section, swipeActions(edge:allowsFullSwipe:), confirmationDialog(_:isPresented:titleVisibility:),
//       sheet(item:), Menu, Picker, ContentUnavailableView (iOS 17), task(priority:_:), Task.sleep(for:),
//       accessibilityAction(named:), onChange(of:) (two-parameter form, iOS 17), onSubmit(of:_:).
import SwiftUI
import TimetableCore
import TimetableUI

/// What the Tasks tab presents as a sheet (one `sheet(item:)`; two on one view are unreliable).
private enum TasksSheet: Identifiable {
    case detail(TaskItem.ID)
    case new(TaskItem.ID)

    var id: String {
        switch self {
        case .detail(let id): return "detail-" + id.uuidString
        case .new(let id): return "new-" + id.uuidString
        }
    }
}

struct TasksRootView: View {
    private let initialSegment: TaskSegment

    init(initialSegment: TaskSegment = .today) {
        self.initialSegment = initialSegment
    }

    @Environment(AppModel.self) private var model
    @State private var chosenSegment: TaskSegment?
    @State private var subjectFilter: Subject.ID?
    @State private var sort: TaskSort = .due
    @State private var sheet: TasksSheet?
    @State private var pendingDelete: TaskItem.ID?
    @State private var quickTitle = ""
    @State private var quickSubjectID: Subject.ID?
    @State private var quickNextLesson: NextLesson?
    @State private var quickResult: ApplyResult?
    @State private var minuteTick = 0

    private var segment: TaskSegment { chosenSegment ?? initialSegment }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tasks.title"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { optionsMenu }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            sheet = .new(TaskItem.ID(UUID()))
                        } label: {
                            Label { Text("tasks.add") } icon: { Image(systemName: "plus") }
                        }
                    }
                }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .detail(let id): TaskDetailView(taskID: id)
            case .new(let id): TaskEditorView(mode: .new(id))
            }
        }
        .closesForDeepLink { sheet = nil }   // QA fix Q6: a notification tap needs the screen
        .confirmationDialog("tasks.delete.title", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("tasks.delete.confirm", role: .destructive) {
                if let id = pendingDelete { model.apply(.delete(id)) }
                pendingDelete = nil
            }
            Button("editor.common.cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(verbatim: deleteMessage)
        }
        // Overdue-by-time and "today" change while the app is open: re-evaluate once a minute (not in screenshot mode).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !model.isClockFixed { minuteTick &+= 1 }
            }
        }
    }

    // MARK: Data

    private var liveTasks: [TaskItem] { (model.database?.tasks ?? []).filter { !$0.isDeleted } }

    private var subjectsByID: [Subject.ID: Subject] {
        Dictionary((model.database?.subjects ?? []).filter { !$0.isDeleted }.map { ($0.id, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var now: LocalDateTime {
        _ = minuteTick
        return model.calendarContext.local(from: model.now)
    }

    /// Subjects the quick-add menu offers: the active timetable's.
    private var quickSubjects: [Subject] {
        guard let timetableID = model.activeTimetable?.id else { return [] }
        return (model.database?.subjects ?? []).filter { !$0.isDeleted && $0.timetableID == timetableID }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteMessage: String {
        guard let id = pendingDelete, let task = liveTasks.first(where: { $0.id == id }) else { return "" }
        return model.renderer.format(key: "tasks.delete.message", arguments: [.text(task.title)])
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let nowValue = now
        let tasks = liveTasks
        let counts = TaskListModel.counts(of: tasks, now: nowValue, subjectFilter: subjectFilter)
        let subjects = subjectsByID
        let rows = TaskListModel.tasks(in: segment, from: tasks, now: nowValue, subjectFilter: subjectFilter, sort: sort)
            .map { TaskRowModel(task: $0, subjects: subjects, now: nowValue) }
        VStack(spacing: 0) {
            TaskSegmentBar(counts: counts, selection: Binding(get: { segment }, set: { chosenSegment = $0 }))
            List {
                if segment != .completed {
                    quickAddSection
                    if let quickResult {
                        ApplyResultSection(result: quickResult)
                    }
                }
                if rows.isEmpty {
                    Section { emptyState(totalOpenOrDone: tasks.count) }
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(rows) { row in
                            TaskRowView(row: row, onOpen: { sheet = .detail(row.id) }, onToggle: { toggle(row) })
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: row.accessibilityLabel(renderer: model.renderer)))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { sheet = .detail(row.id) }
                                .accessibilityAction(named: Text(catalogKey: row.isCompleted ? "tasks.action.reopen" : "tasks.action.complete")) {
                                    toggle(row)
                                }
                                .accessibilityAction(named: Text("tasks.action.delete")) { pendingDelete = row.id }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { toggle(row) } label: {
                                        Label {
                                            Text(catalogKey: row.isCompleted ? "tasks.action.reopen" : "tasks.action.complete")
                                        } icon: {
                                            Image(systemName: row.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                        }
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingDelete = row.id } label: {
                                        Label { Text("tasks.action.delete") } icon: { Image(systemName: "trash") }
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func emptyState(totalOpenOrDone: Int) -> some View {
        if totalOpenOrDone == 0 {
            ContentUnavailableView {
                Label { Text("tasks.empty.title") } icon: { Image(systemName: "checklist") }
            } description: {
                Text("tasks.empty.detail")
            }
        } else if subjectFilter != nil {
            ContentUnavailableView {
                Label { Text("tasks.empty.filtered.title") } icon: { Image(systemName: segment.symbolName) }
            } description: {
                Text("tasks.empty.filtered.detail")
            }
        } else {
            ContentUnavailableView {
                Label { Text(LocalizedStringKey(TaskL10nKeys.emptyTitle(segment))) } icon: {
                    Image(systemName: segment.symbolName)
                }
            } description: {
                Text(LocalizedStringKey(TaskL10nKeys.emptyDetail(segment)))
            }
        }
    }

    // MARK: Actions

    private func toggle(_ row: TaskRowModel) {
        if row.isCompleted {
            if let task = liveTasks.first(where: { $0.id == row.id }) {
                model.apply(.upsert(TaskEdits.reopened(task)))
            }
        } else {
            model.apply(.completeTask(row.id, at: model.now))
        }
    }

    // MARK: Options menu

    private var optionsMenu: some View {
        let subjects = TaskListModel.filterSubjects(tasks: liveTasks, subjects: model.database?.subjects ?? [])
        return Menu {
            Picker(selection: $sort) {
                ForEach(TaskSort.allCases, id: \.self) { option in
                    Text(LocalizedStringKey(option.titleKey)).tag(option)
                }
            } label: {
                Text("tasks.sort.title")
            }
            Picker(selection: $subjectFilter) {
                Text("tasks.filter.all").tag(Subject.ID?.none)
                ForEach(subjects, id: \.id) { subject in
                    Text(verbatim: subject.name).tag(Subject.ID?.some(subject.id))
                }
            } label: {
                Text("tasks.filter.title")
            }
        } label: {
            Label {
                Text("tasks.options")
            } icon: {
                Image(systemName: subjectFilter == nil ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }

    // MARK: Quick add

    private var quickAddSection: some View {
        Section {
            LabeledTextField(titleKey: "tasks.quickAdd.title", text: $quickTitle)
                .onSubmit(addQuick)
                .submitLabel(.done)
            Picker(selection: $quickSubjectID) {
                Text("tasks.subject.none").tag(Subject.ID?.none)
                ForEach(quickSubjects, id: \.id) { subject in
                    Text(verbatim: subject.name).tag(Subject.ID?.some(subject.id))
                }
            } label: {
                Text("tasks.field.subject")
            }
            .onChange(of: quickSubjectID) { _, _ in resolveQuickNextLesson() }
            Button(action: addQuick) {
                Label { Text("tasks.quickAdd.add") } icon: { Image(systemName: "plus.circle.fill") }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(EditorText.trimmedOrNil(quickTitle) == nil)
        } footer: {
            Text(verbatim: quickDueText)
        }
    }

    private var quickDueText: String {
        if let nextLesson = quickNextLesson, quickSubjectID != nil {
            return model.renderer.format(key: "tasks.quickAdd.dueNextLesson", arguments: [
                .text(model.formatter.date(nextLesson.date, style: .weekdayDayMonth)),
            ])
        }
        return model.renderer.string(forKey: "tasks.quickAdd.dueTomorrow")
    }

    private func resolveQuickNextLesson() {
        quickNextLesson = TaskSupport.nextLesson(subjectID: quickSubjectID, model: model)
    }

    private func addQuick() {
        let subject = quickSubjectID.flatMap { id in quickSubjects.first { $0.id == id } }
        let next = TaskSupport.nextLesson(subjectID: subject?.id, model: model)
        guard let task = TaskQuickAdd.makeTask(id: TaskItem.ID(UUID()), title: quickTitle, subject: subject,
                                               nextLesson: next, today: model.today,
                                               fallbackTimetableID: model.activeTimetable?.id) else { return }
        let result = model.apply(.upsert(task), origin: .userSave)   // may offer the notification explainer (Q1)
        quickResult = result
        if case .applied = result {
            quickTitle = ""
            quickResult = nil
        }
    }
}

/// Helpers shared by the Tasks views.
@MainActor
enum TaskSupport {
    /// The next lesson of `subjectID` from the subject's timetable (nil: no subject, no resolver or no lesson).
    static func nextLesson(subjectID: Subject.ID?, model: AppModel) -> NextLesson? {
        guard let subjectID,
              let subject = model.database?.subjects.first(where: { $0.id == subjectID && !$0.isDeleted }),
              let resolver = model.resolver(for: subject.timetableID) else { return nil }
        return NextLessonResolver.find(subjectID: subjectID, resolver: resolver, now: model.now)
    }
}
