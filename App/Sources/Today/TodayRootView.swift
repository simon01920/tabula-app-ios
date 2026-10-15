// The Today tab (route `today`): the Now & Next header with a live countdown (always first), then — Phase 3 C1 — the
// "Due today" tasks (complete inline; an "N overdue" chip opens the Tasks tab on Overdue) and the next exam when it is
// at most 14 days away, then today's lessons as tiles with status and task / exam badges and break separators, and —
// once today has nothing left (evening, weekend, holiday, cancelled day) — the next school day's lessons.
// State comes from `TodayState` and `TodayWork` (TimetableUI, Linux-tested); this view re-builds them once a minute
// with a TimelineView (countdowns tick on their own via `Text(timerInterval:)`), or once with a fixed clock in
// screenshot mode (`model.isClockFixed`: countdowns paused at `model.now`).
// Taps open sheets in place (Today stays selected): a lesson → `LessonDetailView`, a task → `TaskDetailView` (what
// the `tasks.detail` route shows), the exam card → `ExamDetailSheet` (what `exams.detail` shows).
// Keep the type name `TodayRootView` and its no-argument init: the app shell uses it.
// APIs: NavigationStack, ScrollView, LazyVStack, TimelineView(.everyMinute) (iOS 15), sheet(item:),
//       ContentUnavailableView (iOS 17), ViewThatFits(in:) (iOS 16), accessibilityAddTraits(.isHeader / .isButton),
//       accessibilityAction(named:_:), accessibilityHint(_:), buttonBorderShape(.capsule), controlSize(.large).
import SwiftUI
import TimetableCore
import TimetableUI

/// What Today presents (one `sheet(item:)`: two sheet modifiers on one view are unreliable).
private enum TodaySheet: Identifiable {
    case lesson(LessonDetailTarget)
    case task(TaskItem.ID)
    case exam(Exam.ID)

    var id: String {
        switch self {
        case .lesson(let target): return "lesson-" + target.id
        case .task(let id): return "task-" + id.uuidString
        case .exam(let id): return "exam-" + id.uuidString
        }
    }
}

struct TodayRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var sheet: TodaySheet?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("shell.tab.today"))
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .lesson(let target): LessonDetailView(target: target)
            case .task(let id): TaskDetailView(taskID: id)
            case .exam(let id): ExamDetailSheet(examID: id)
            }
        }
        .closesForDeepLink { sheet = nil }   // QA fix Q6: a notification tap needs the screen
    }

    @ViewBuilder
    private var content: some View {
        if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id),
           let database = model.database {
            if model.isClockFixed {
                todayContent(timetable: timetable, resolver: resolver, database: database)
            } else {
                TimelineView(.everyMinute) { _ in
                    todayContent(timetable: timetable, resolver: resolver, database: database)
                }
            }
        } else {
            ContentUnavailableView {
                Label { Text("today.empty.noTimetable.title") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
            } description: {
                Text("today.empty.noTimetable.message")
            } actions: {
                EmptyView()
            }
        }
    }

    private func todayContent(timetable: Timetable, resolver: ScheduleResolver, database: TabulaDatabase) -> some View {
        let state = TodayState.make(now: model.now, resolver: resolver, database: database)
        let work = TodayWork.make(database: database, now: model.calendarContext.local(from: model.now),
                                  context: model.calendarContext)
        let dates = [state.date] + [state.upcomingDay?.date, state.header.next?.date].compactMap { $0 }
        return TodayContent(state: state, work: work, timetable: timetable,
                            hasLessons: hasLessons(database, timetable),
                            actions: TodayActions(openLesson: { sheet = .lesson(LessonDetailTarget($0)) },
                                                  openTask: { sheet = .task($0) },
                                                  completeTask: complete,
                                                  openExam: { sheet = .exam($0) },
                                                  showOverdue: { navigation.showTasks(.overdue) }))
            .environment(\.lessonWork, LessonWorkSupport.index(dates: dates, resolver: resolver, database: database))
    }

    private func hasLessons(_ database: TabulaDatabase, _ timetable: Timetable) -> Bool {
        database.lessons.contains { !$0.isDeleted && $0.timetableID == timetable.id }
            || database.overrides.contains { override in
                guard !override.isDeleted, override.timetableID == timetable.id,
                      case .addLesson = override.change else { return false }
                return true
            }
    }

    private func complete(_ id: TaskItem.ID) {
        model.apply(.completeTask(id, at: model.now))
    }
}

/// The callbacks of Today's content.
private struct TodayActions {
    let openLesson: (ResolvedLesson) -> Void
    let openTask: (TaskItem.ID) -> Void
    let completeTask: (TaskItem.ID) -> Void
    let openExam: (Exam.ID) -> Void
    let showOverdue: () -> Void
}

/// The scrolling content of Today.
private struct TodayContent: View {
    let state: TodayState
    let work: TodayWork
    let timetable: Timetable
    let hasLessons: Bool
    let actions: TodayActions
    @Environment(AppModel.self) private var model

    var body: some View {
        if !hasLessons && !work.showsTasks && work.nextExam == nil {
            ContentUnavailableView {
                Label { Text("today.empty.noLessons.title") } icon: { Image(systemName: "square.grid.3x3") }
            } description: {
                Text("today.empty.noLessons.message")
            } actions: {
                EmptyView()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if hasLessons {
                        NowNextHeaderView(header: state.header, today: state.date, visibility: timetable.fieldVisibility,
                                          reasons: state.reasonsByOccurrence)
                            .padding(.bottom, 8)
                    }
                    if work.showsTasks {
                        DueTodaySection(work: work, actions: actions)
                            .padding(.bottom, 8)
                    }
                    if let exam = work.nextExam {
                        NextExamCard(row: exam, onOpen: actions.openExam)
                            .padding(.bottom, 8)
                    }
                    if !state.items.isEmpty {
                        SectionTitle(text: model.formatter.date(state.date, style: .full))
                        TimelineItemsView(items: state.items, visibility: timetable.fieldVisibility,
                                          density: timetable.density, onOpen: actions.openLesson)
                    }
                    if let next = state.upcomingDay, !state.upcomingItems.isEmpty {
                        SectionTitle(text: nextDayTitle(next.date), caption: model.formatter.date(next.date, style: .full))
                            .padding(.top, 12)
                        TimelineItemsView(items: state.upcomingItems, visibility: timetable.fieldVisibility,
                                          density: timetable.density, onOpen: actions.openLesson)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func nextDayTitle(_ date: LocalDate) -> String {
        date == state.date.adding(days: 1)
            ? model.renderer.string(forKey: "today.section.tomorrow")
            : model.renderer.string(forKey: "today.section.nextSchoolDay")
    }
}

/// "Due today": the open tasks due today (rows as in the Tasks tab, completable inline) and the overdue chip.
private struct DueTodaySection: View {
    let work: TodayWork
    let actions: TodayActions
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.calendarContext.local(from: model.now)
        let subjects = Dictionary((model.database?.subjects ?? []).filter { !$0.isDeleted }.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    SectionTitle(text: model.renderer.string(forKey: "today.section.dueToday"))
                    Spacer(minLength: 0)
                    overdueChip
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: model.renderer.string(forKey: "today.section.dueToday"))
                    overdueChip
                }
            }
            if !work.dueToday.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(work.dueToday.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider().padding(.leading, 48) }
                        row(TaskRowModel(task: task, subjects: subjects, now: now))
                    }
                }
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    private func row(_ row: TaskRowModel) -> some View {
        TaskRowView(row: row, onOpen: { actions.openTask(row.id) }, onToggle: { actions.completeTask(row.id) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.accessibilityLabel(renderer: model.renderer)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.openTask(row.id) }
            .accessibilityAction(named: Text("tasks.action.complete")) { actions.completeTask(row.id) }
    }

    @ViewBuilder
    private var overdueChip: some View {
        if work.overdueCount > 0 {
            Button(action: actions.showOverdue) {
                Label {
                    Text(verbatim: model.renderer.format(key: "today.tasks.overdue",
                                                         arguments: [.integer(Int64(work.overdueCount))]))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.red)
            .accessibilityHint(Text("today.tasks.overdue.hint"))
        }
    }
}

/// The Exams tab's featured card for the next exam, as a button that opens its detail.
private struct NextExamCard: View {
    let row: ExamRow
    let onOpen: (Exam.ID) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let visibility = model.database.map { ExamFacts.visibility(for: row.exam, in: $0) } ?? .all
        Button { onOpen(row.id) } label: {
            ExamFeaturedCard(row: row, facts: ExamFacts(exam: row.exam, visibility: visibility),
                             texts: ExamTexts(renderer: model.renderer))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// A section heading inside the scroll view.
private struct SectionTitle: View {
    let text: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(verbatim: caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
