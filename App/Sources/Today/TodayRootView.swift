// The Today tab (route `today`): the Now & Next header with a live countdown, today's lessons as tiles with status
// badges and break separators, and — once today has nothing left (evening, weekend, holiday, cancelled day) — the
// next school day's lessons. State comes from `TodayState` (TimetableUI, Linux-tested); this view re-builds it once a
// minute with a TimelineView (countdowns tick on their own via `Text(timerInterval:)`), or once with a fixed clock
// in screenshot mode (`model.isClockFixed`: countdowns paused at `model.now`).
// Keep the type name `TodayRootView` and its no-argument init: the app shell uses it.
// APIs: NavigationStack, ScrollView, LazyVStack, TimelineView(.everyMinute) (iOS 15), sheet(item:),
//       ContentUnavailableView (iOS 17), accessibilityAddTraits(.isHeader).
import SwiftUI
import TimetableCore
import TimetableUI

struct TodayRootView: View {
    @Environment(AppModel.self) private var model
    @State private var detail: LessonDetailTarget?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("shell.tab.today"))
        }
        .sheet(item: $detail) { target in
            LessonDetailView(target: target)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id),
           let database = model.database {
            if model.isClockFixed {
                TodayContent(state: TodayState.make(now: model.now, resolver: resolver, database: database),
                             timetable: timetable, hasLessons: hasLessons(database, timetable), onOpen: open)
            } else {
                TimelineView(.everyMinute) { _ in
                    TodayContent(state: TodayState.make(now: model.now, resolver: resolver, database: database),
                                 timetable: timetable, hasLessons: hasLessons(database, timetable), onOpen: open)
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

    private func hasLessons(_ database: TabulaDatabase, _ timetable: Timetable) -> Bool {
        database.lessons.contains { !$0.isDeleted && $0.timetableID == timetable.id }
            || database.overrides.contains { override in
                guard !override.isDeleted, override.timetableID == timetable.id,
                      case .addLesson = override.change else { return false }
                return true
            }
    }

    private func open(_ lesson: ResolvedLesson) {
        detail = LessonDetailTarget(lesson)
    }
}

/// The scrolling content of Today.
private struct TodayContent: View {
    let state: TodayState
    let timetable: Timetable
    let hasLessons: Bool
    let onOpen: (ResolvedLesson) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        if !hasLessons {
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
                    NowNextHeaderView(header: state.header, today: state.date, visibility: timetable.fieldVisibility,
                                      reasons: state.reasonsByOccurrence)
                        .padding(.bottom, 8)
                    if !state.items.isEmpty {
                        SectionTitle(text: model.formatter.date(state.date, style: .full))
                        TimelineItemsView(items: state.items, visibility: timetable.fieldVisibility,
                                          density: timetable.density, onOpen: onOpen)
                    }
                    if let next = state.upcomingDay, !state.upcomingItems.isEmpty {
                        SectionTitle(text: nextDayTitle(next.date), caption: model.formatter.date(next.date, style: .full))
                            .padding(.top, 12)
                        TimelineItemsView(items: state.upcomingItems, visibility: timetable.fieldVisibility,
                                          density: timetable.density, onOpen: onOpen)
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

/// A section heading inside the scroll view.
private struct SectionTitle: View {
    let text: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: text)
                .font(.title3.weight(.semibold))
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
