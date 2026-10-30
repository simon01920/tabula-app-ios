// The Today tab (route `today`; Phase 4U U3, Opus review R1 "one job, one order, every profile", Astra §4 "Today
// content order"). One inset-grouped List, in the same order for every school type (the content inside adapts through
// the timetable's field visibility: bring lists for elementary, buildings for university):
//   1. Hero (`TodayHeroView`): before school / break / lesson / after school / day off.
//   2. Due today: open tasks due today (no repeated "Today" label, M10; swipe or VoiceOver action to complete) and a
//      plain "1 overdue task ›" row that opens Tasks › Overdue (F15 / H3.6).
//   3. Rest of today: compact rows of the lessons still to come (the current lesson is in the hero, never repeated,
//      H3.2 / F14), then a collapsed "Earlier today" disclosure with the lessons that are over. Once today has nothing
//      left: the next school day's lessons ("Tomorrow" or its date).
//   4. Next exam (at most 14 days ahead): title first, then "Thu, Oct 22 · in 9 days" in subheadline, never the largest
//      text on screen, the same row in every profile (H3.1 / H3.4 / F16).
// The date and rotation week are the iOS 26 navigation subtitle ("Tue, Oct 13 · Week B", L2), so there is no date
// header. State comes from `TodayState`, `TodayWork` and `TodayHeroText` (TimetableUI, Linux-tested); the view rebuilds
// them once a minute with a TimelineView, or once with a fixed clock (screenshot mode, or a `today.*` state route).
// Taps open sheets in place (Today stays selected): a lesson → `LessonDetailView`, a task → `TaskDetailView`, the exam
// → `ExamDetailSheet`.
// Keep the type name `TodayRootView` and its no-argument init: the app shell uses it.
// APIs: NavigationStack, navigationSubtitle(_:) (iOS 26, as in TimetableRootView), List, Section(content:header:),
//       listStyle(.insetGrouped), DisclosureGroup(isExpanded:content:label:), swipeActions(edge:allowsFullSwipe:),
//       TimelineView(.everyMinute), sheet(item:), ContentUnavailableView (iOS 17), accessibilityAction(named:_:).
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
    /// A fixed "now" for the DEBUG state routes (`today.before-school`, …); `nil` = the app's clock.
    var fixedNow: Date?
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var sheet: TodaySheet?
    @State private var undoTaskID: TaskItem.ID?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("shell.tab.today"))
                .taskUndoToast($undoTaskID)
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
            if model.isClockFixed || fixedNow != nil {
                todayContent(timetable: timetable, resolver: resolver, database: database, now: fixedNow ?? model.now)
            } else {
                TimelineView(.everyMinute) { _ in
                    todayContent(timetable: timetable, resolver: resolver, database: database, now: model.now)
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

    private func todayContent(timetable: Timetable, resolver: ScheduleResolver, database: TabulaDatabase,
                              now: Date) -> some View {
        let state = TodayState.make(now: now, resolver: resolver, database: database)
        let work = TodayWork.make(database: database, now: model.calendarContext.local(from: now),
                                  context: model.calendarContext)
        let dates = [state.date] + [state.upcomingDay?.date, state.header.next?.date].compactMap { $0 }
        let subtitle = TodayHeroText(renderer: model.renderer, visibility: timetable.fieldVisibility).subtitle(state)
        return TodayContent(state: state, work: work, timetable: timetable, now: now,
                            hasLessons: hasLessons(database, timetable),
                            actions: TodayActions(openLesson: { sheet = .lesson(LessonDetailTarget($0)) },
                                                  openTask: { sheet = .task($0) },
                                                  completeTask: { TaskSupport.complete($0, at: now, model: model, undo: $undoTaskID) },
                                                  openExam: { sheet = .exam($0) },
                                                  showOverdue: { navigation.showTasks(.overdue) }))
            .environment(\.lessonWork, LessonWorkSupport.index(dates: dates, resolver: resolver, database: database))
            .navigationSubtitle(Text(verbatim: subtitle))
    }

    private func hasLessons(_ database: TabulaDatabase, _ timetable: Timetable) -> Bool {
        database.lessons.contains { !$0.isDeleted && $0.timetableID == timetable.id }
            || database.overrides.contains { override in
                guard !override.isDeleted, override.timetableID == timetable.id,
                      case .addLesson = override.change else { return false }
                return true
            }
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

/// The list of Today.
private struct TodayContent: View {
    let state: TodayState
    let work: TodayWork
    let timetable: Timetable
    let now: Date
    let hasLessons: Bool
    let actions: TodayActions
    @Environment(AppModel.self) private var model
    @State private var showsEarlier = false

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
            List {
                if hasLessons {
                    Section {
                        TodayHeroView(state: state, now: now, visibility: timetable.fieldVisibility)
                    }
                }
                if work.showsTasks {
                    DueTodaySection(work: work, now: now, actions: actions)
                }
                lessonSections
                if let exam = work.nextExam {
                    Section {
                        Button { actions.openExam(exam.id) } label: { TodayExamRow(row: exam) }
                    } header: {
                        Text("today.section.nextExam")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var lessonSections: some View {
        let remaining = state.remainingItems
        let earlier = state.earlierItems
        if !remaining.isEmpty || !earlier.isEmpty {
            Section {
                ForEach(remaining) { lessonRow($0) }
                if !earlier.isEmpty {
                    DisclosureGroup(isExpanded: $showsEarlier) {
                        ForEach(earlier) { lessonRow($0) }
                    } label: {
                        Text("today.section.earlier")
                    }
                }
            } header: {
                if !remaining.isEmpty { Text("today.section.restOfToday") }
            }
        }
        if let day = state.upcomingDay, !state.upcomingItems.isEmpty {
            Section {
                ForEach(state.upcomingItems) { lessonRow($0) }
            } header: {
                Text(verbatim: day.date == state.date.adding(days: 1)
                     ? model.renderer.string(forKey: "today.section.tomorrow")
                     : model.formatter.contextualDate(day.date, today: state.date))
            }
        }
    }

    @ViewBuilder
    private func lessonRow(_ item: TodayItem) -> some View {
        if case let .lesson(lesson, reasons, _) = item {
            Button { actions.openLesson(lesson) } label: {
                TodayLessonRow(lesson: lesson, reasons: reasons, visibility: timetable.fieldVisibility)
            }
            .accessibilityHint(Text("timetable.a11y.openHint"))
        }
    }
}

/// "Due today": the open tasks due today (completable by swipe or VoiceOver action) and the overdue row.
private struct DueTodaySection: View {
    let work: TodayWork
    let now: Date
    let actions: TodayActions
    @Environment(AppModel.self) private var model

    var body: some View {
        let local = model.calendarContext.local(from: now)
        let subjects = Dictionary((model.database?.subjects ?? []).filter { !$0.isDeleted }.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        Section {
            ForEach(work.dueToday) { task in
                let row = TaskRowModel(task: task, subjects: subjects, now: local)
                TaskRowView(row: row, section: .today, onOpen: { actions.openTask(row.id) },
                            onToggle: { actions.completeTask(row.id) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: row.accessibilityLabel(renderer: model.renderer)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { actions.openTask(row.id) }
                    .accessibilityAction(named: Text("tasks.action.complete")) { actions.completeTask(row.id) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { actions.completeTask(row.id) } label: {
                            Label { Text("tasks.action.complete") } icon: { Image(AppSymbol.completed) }
                        }
                        .tint(Color.ink)
                    }
            }
            if work.overdueCount > 0 {
                Button(action: actions.showOverdue) {
                    HStack(spacing: 12) {
                        // Correction red on the plain cell (no pale-red fill, Astra F04): icon and title only.
                        Label {
                            Text(verbatim: TodayHeroText(renderer: model.renderer, visibility: .all)
                                .overdue(work.overdueCount))
                        } icon: {
                            Image(AppSymbol.overdue)
                        }
                        .foregroundStyle(Color.correction)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityHint(Text("today.tasks.overdue.hint"))
            }
        } header: {
            Text("today.section.dueToday")
        }
    }
}

/// One compact lesson row: "10:55  [badge] Biology / 214" (badge left out at accessibility sizes, the text stacks).
private struct TodayLessonRow: View {
    let lesson: ResolvedLesson
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    @Environment(AppModel.self) private var model
    @Environment(\.lessonWork) private var work
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeWidth: CGFloat = 48

    var body: some View {
        let badges = work.badges(for: lesson.id)
        let isStacked = AdaptiveLayout.isStacked(dynamicTypeSize)
        AdaptiveStack(horizontalAlignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: model.formatter.time(lesson.startTime))
                .font(TypeScale.detail)
                .timeStyle()
                .frame(minWidth: isStacked ? nil : timeWidth, alignment: .leading)
            HStack(alignment: .center, spacing: 10) {
                if !isStacked { SubjectBadge(subject: lesson.subject, size: 28) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lesson.subject.name)
                        .font(TypeScale.detail)
                        .strikethrough(lesson.status == .cancelled)
                        .fixedSize(horizontal: false, vertical: true)
                    LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility,
                                                                      only: [.room, .building]),
                                         font: .subheadline, quietIcons: true)
                    if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                        LessonStatusBadge(badge)
                    }
                    if let badges { LessonWorkBadgeRow(badges: badges) }
                }
            }
        }
        .foregroundStyle(.primary)
        .opacity(lesson.status == .cancelled ? 0.6 : 1)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(lesson: lesson, visibility: visibility,
                                                                         reasons: reasons, badges: badges,
                                                                         renderer: model.renderer)))
    }
}

/// The next exam: title first (headline), then "Thu, Oct 22 · in 9 days" (subheadline). Never larger than the hero.
private struct TodayExamRow: View {
    let row: ExamRow
    @Environment(AppModel.self) private var model

    var body: some View {
        let visibility = model.database.map { ExamFacts.visibility(for: row.exam, in: $0) } ?? .all
        let texts = ExamTexts(renderer: model.renderer)
        AdaptiveStack(horizontalAlignment: .center, spacing: 12) {
            ExamBadge(subject: row.subject, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.exam.title)
                    .font(TypeScale.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: TodayHeroText(renderer: model.renderer, visibility: .all).examWhen(row))
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.accessibilityLabel(row, facts: ExamFacts(exam: row.exam,
                                                                                            visibility: visibility))))
        .accessibilityAddTraits(.isButton)
    }
}
