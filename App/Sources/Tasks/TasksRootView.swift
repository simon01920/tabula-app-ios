// The Tasks tab (Phase 4U U2, Opus review R2 / C3 / H6 / H7 / M10 / M23, Astra F15): ONE grouped list instead of
// filter chips and an inline form. Sections: Overdue, Today, Tomorrow, This week, Later, No date (undated tasks have
// their own last section), each with its count in the header; completed tasks sit behind a "Show N completed tasks"
// button at the end (also a switch in the filter menu). The toolbar has a filter/sort menu (subject, type, show
// completed, sort) and "+", which opens the quick-entry sheet (TaskQuickEntrySheet).
// The routes `tasks.upcoming|overdue|completed` and `AppNavigation.showTasks(_:)` map a `TaskSegment` to a scroll
// anchor (`TaskListModel.anchor(for:in:)`): Overdue / Today to their section, Upcoming to the first later section,
// Completed opens the completed tasks and scrolls to them.
// Completing a task shows "Marked as done · Undo" for a few seconds (F15). Logic lives in TimetableUI/Tasks
// (TaskListModel, TaskRowModel, TaskQuickEntry, NextLessonResolver; Linux-tested). Keep the type name `TasksRootView`
// and its no-argument init: the app shell uses it. Writes go through `model.apply` only (`.completeTask`, `.upsert`,
// `.delete`); the reminder coordinator re-plans by itself.
// HIG (apple-design references): lists-and-tables.md (grouped list, swipe actions, one background), toolbars.md
// (a menu for the filter, "+" for the action), sheets.md (see TaskQuickEntrySheet), segmented-controls.md (the chips
// that C3 flagged are gone).
// APIs: NavigationStack, List, Section, ScrollViewReader, swipeActions(edge:allowsFullSwipe:),
//       confirmationDialog(_:isPresented:titleVisibility:), sheet(item:), Menu, Picker, Toggle, ContentUnavailableView,
//       safeAreaInset(edge:), task(id:priority:_:), Task.sleep(for:), accessibilityAction(named:),
//       AccessibilityNotification.Announcement (iOS 17), onChange(of:) (two-parameter form, iOS 17).
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
    private let initialSegment: TaskSegment?

    /// `initialSegment`: where to scroll on appearing (screenshots, Today's overdue link); `nil` = the top.
    init(initialSegment: TaskSegment? = nil) {
        self.initialSegment = initialSegment
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var subjectFilter: Subject.ID?
    @State private var kindFilter: TaskKind?
    @State private var sort: TaskSort = .due
    /// `nil` = not chosen by the user yet, so the route decides (no `State(initialValue:)` in initialisers).
    @State private var chosenShowCompleted: Bool?
    @State private var sheet: TasksSheet?
    @State private var pendingDelete: TaskItem.ID?
    @State private var undoTaskID: TaskItem.ID?
    @State private var didScroll = false
    @State private var minuteTick = 0

    private var showCompleted: Bool { chosenShowCompleted ?? (initialSegment == .completed) }

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
                            Label { Text("tasks.add") } icon: { Image(AppSymbol.add) }
                        }
                    }
                }
                .taskUndoToast($undoTaskID)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .detail(let id): TaskDetailView(taskID: id)
            case .new(let id): TaskQuickEntrySheet(id: id)
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
        let lastDay = TaskListModel.lastDayOfWeek(containing: nowValue.date, context: model.calendarContext)
        let groups = TaskListModel.sections(of: tasks, now: nowValue, lastDayOfWeek: lastDay, subjectFilter: subjectFilter,
                                            kindFilter: kindFilter, sort: sort)
        let completed = TaskListModel.completedTasks(of: tasks, now: nowValue, subjectFilter: subjectFilter, kindFilter: kindFilter)
        let subjects = subjectsByID
        ScrollViewReader { proxy in
            List {
                if groups.isEmpty && !(showCompleted && !completed.isEmpty) {
                    Section { emptyState(hasTasks: !tasks.isEmpty, hasCompleted: !completed.isEmpty) }
                        .listRowBackground(Color.clear)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            taskRow(task, section: group.section, subjects: subjects, now: nowValue)
                        }
                    } header: {
                        TaskSectionHeader(section: group.section, count: group.tasks.count)
                    }
                    .id(TaskListAnchor.section(group.section))
                }
                if !completed.isEmpty {
                    Section {
                        if showCompleted {
                            ForEach(completed) { task in
                                taskRow(task, section: nil, subjects: subjects, now: nowValue)
                            }
                        }
                        Button { chosenShowCompleted = !showCompleted } label: {
                            Text(verbatim: completedButtonTitle(count: completed.count))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        }
                    } header: {
                        if showCompleted {
                            Text("tasks.section.completed")
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                    .id(TaskListAnchor.completed)
                }
            }
            .listStyle(.insetGrouped)   // one grouped background from the title to the last row (M23)
            .task {
                // Once: scroll to the section the route or link asked for, after the first layout.
                guard !didScroll, let initialSegment else { return }
                didScroll = true
                guard let anchor = TaskListModel.anchor(for: initialSegment, in: groups) else { return }
                await Task.yield()
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    private func completedButtonTitle(count: Int) -> String {
        showCompleted
            ? model.renderer.string(forKey: "tasks.completed.hide")
            : model.renderer.format(key: "tasks.completed.show", arguments: [.integer(Int64(count))])
    }

    private func taskRow(_ task: TaskItem, section: TaskSection?, subjects: [Subject.ID: Subject], now: LocalDateTime) -> some View {
        let row = TaskRowModel(task: task, subjects: subjects, now: now)
        return TaskRowView(row: row, section: section, onOpen: { sheet = .detail(row.id) }, onToggle: { toggle(row) })
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
                        Image(row.isCompleted ? AppSymbol.notCompleted : AppSymbol.completed)
                    }
                }
                .tint(Color.ink)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { pendingDelete = row.id } label: {
                    Label { Text("tasks.action.delete") } icon: { Image(AppSymbol.delete) }
                }
            }
    }

    @ViewBuilder
    private func emptyState(hasTasks: Bool, hasCompleted: Bool) -> some View {
        if !hasTasks {
            ContentUnavailableView {
                Label { Text("tasks.empty.title") } icon: { Image(AppSymbol.task) }
            } description: {
                Text("tasks.empty.detail")
            }
        } else if subjectFilter != nil || kindFilter != nil {
            ContentUnavailableView {
                Label { Text("tasks.empty.filtered.title") } icon: { Image(AppSymbol.task) }
            } description: {
                Text("tasks.empty.filtered.detail")
            }
        } else {
            ContentUnavailableView {
                Label { Text("tasks.empty.allDone.title") } icon: { Image(AppSymbol.completed) }
            } description: {
                Text("tasks.empty.allDone.detail")
            }
        }
    }

    // MARK: Actions

    private func toggle(_ row: TaskRowModel) {
        if row.isCompleted {
            if let task = liveTasks.first(where: { $0.id == row.id }) {
                model.apply(.upsert(TaskEdits.reopened(task)))
                TaskSupport.announce("tasks.action.reopen", model: model)
            }
        } else {
            TaskSupport.complete(row.id, at: model.now, model: model, undo: $undoTaskID)
        }
    }

    // MARK: Filter menu

    private var optionsMenu: some View {
        let subjects = TaskListModel.filterSubjects(tasks: liveTasks, subjects: model.database?.subjects ?? [],
                                                    timetableOrder: model.timetables.map(\.id), locale: model.formatter.locale)
        let isFiltered = subjectFilter != nil || kindFilter != nil
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
            Picker(selection: $kindFilter) {
                Text("tasks.filter.type.all").tag(TaskKind?.none)
                ForEach(TaskQuickEntry.kinds, id: \.rawValue) { kind in
                    if let key = TaskL10nKeys.kind(kind) { Text(LocalizedStringKey(key)).tag(TaskKind?.some(kind)) }
                }
            } label: {
                Text("tasks.filter.type")
            }
            Toggle(isOn: Binding(get: { showCompleted }, set: { chosenShowCompleted = $0 })) {
                Text("tasks.filter.showCompleted")
            }
        } label: {
            Label {
                Text("tasks.options")
            } icon: {
                Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
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

    /// The subject of the lesson that is on now, else of the next one, in the active timetable (the quick-entry
    /// default, M21). Nil when there is no lesson in the horizon.
    static func currentOrNextSubject(model: AppModel) -> Subject.ID? {
        guard let timetableID = model.activeTimetable?.id, let resolver = model.resolver(for: timetableID) else { return nil }
        let nowNext = resolver.nowAndNext(at: model.now)
        return (nowNext.current ?? nowNext.next)?.subject.id
    }
}
