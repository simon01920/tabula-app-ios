// The Timetable tab (routes `timetable`, `timetable.grid|week|day|tiles`): week navigation + strip on top, the
// timetable's view below, a title menu to switch timetables (only with more than one), and a view-options menu
// (view kind remembered per timetable via `model.apply(.upsert(timetable with defaultView))`, density, "show week
// A/B" for week cycles, "Change for this day…" in day views, "Today").
// Taps: a lesson → `LessonDetailView` sheet; a free grid slot → `QuickAddSheet`.
// Navigation state is `TimetableSelection` (TimetableUI, Linux-tested); "now" is `model.now`, refreshed once a minute
// by a TimelineView unless the clock is fixed (screenshot mode).
// APIs: NavigationStack, toolbar { ToolbarItem(placement: .topBarTrailing / .topBarLeading) }, Menu, Picker
//       (.inline), Section, toolbarTitleMenu(content:) (iOS 16), navigationBarTitleDisplayMode(.inline),
//       TimelineView(.everyMinute), sheet(item:), simultaneousGesture(DragGesture), ContentUnavailableView,
//       Environment(\.dynamicTypeSize).
import SwiftUI
import TimetableCore
import TimetableUI

struct TimetableRootView: View {
    /// View forced by a launch route (`timetable.grid` …) until the user picks one.
    private let initialView: TimetableViewKind?

    @Environment(AppModel.self) private var model
    @State private var selection: TimetableSelection?
    @State private var sessionViews: [Timetable.ID: TimetableViewKind] = [:]
    @State private var detail: LessonDetailTarget?
    @State private var quickAdd: QuickAddTarget?
    @State private var editor: EditorPresentation?

    init() {
        initialView = nil
    }

    init(initialView: TimetableViewKind) {
        self.initialView = initialView
    }

    var body: some View {
        NavigationStack {
            Group {
                if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) {
                    if model.isClockFixed {
                        TimetableContent(timetable: timetable, resolver: resolver, now: model.now,
                                         viewKind: viewKind(for: timetable), selection: selectionBinding(resolver),
                                         onOpen: open, onAdd: { quickAdd = $0 })
                    } else {
                        TimelineView(.everyMinute) { _ in
                            TimetableContent(timetable: timetable, resolver: resolver, now: model.now,
                                             viewKind: viewKind(for: timetable), selection: selectionBinding(resolver),
                                             onOpen: open, onAdd: { quickAdd = $0 })
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label { Text("timetable.empty.noTimetable") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
                    } description: {
                        EmptyView()
                    } actions: {
                        EmptyView()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .timetableSwitcher(isEnabled: model.timetables.count > 1) { timetableMenu }
            .toolbar { toolbarContent }
        }
        .sheet(item: $detail) { target in
            LessonDetailView(target: target)
        }
        .sheet(item: $quickAdd) { target in
            QuickAddSheet(target: target)
        }
        .editorSheet($editor)
    }

    // MARK: State

    private var title: Text {
        guard let timetable = model.activeTimetable else { return Text("shell.tab.timetable") }
        if let emoji = timetable.emoji?.trimmingCharacters(in: .whitespaces), !emoji.isEmpty {
            return Text(verbatim: model.renderer.format(key: "timetable.title.withEmoji",
                                                        arguments: [.text(emoji), .text(timetable.name)]))
        }
        return Text(verbatim: timetable.name)
    }

    private func viewKind(for timetable: Timetable) -> TimetableViewKind {
        TimetableViewChoice.resolve(sessionViews[timetable.id] ?? initialView ?? timetable.defaultView)
    }

    private func selectionBinding(_ resolver: ScheduleResolver) -> Binding<TimetableSelection> {
        Binding(get: { selection ?? TimetableSelection.initial(today: model.today, resolver: resolver) },
                set: { selection = $0 })
    }

    private func open(_ lesson: ResolvedLesson) {
        detail = LessonDetailTarget(lesson)
    }

    /// Remembers the view for this timetable (persisted; also kept for the session if the store is read-only).
    private func choose(_ kind: TimetableViewKind, for timetable: Timetable) {
        sessionViews[timetable.id] = kind
        guard timetable.defaultView != kind else { return }
        var edited = timetable
        edited.defaultView = kind
        model.apply(.upsert(edited))
    }

    private func setDensity(_ density: Density, for timetable: Timetable) {
        guard timetable.density != density else { return }
        var edited = timetable
        edited.density = density
        model.apply(.upsert(edited))
    }

    // MARK: Menus

    @ViewBuilder
    private var timetableMenu: some View {
        if model.timetables.count > 1 {
            ForEach(model.timetables) { timetable in
                Button {
                    selection = nil
                    model.apply(.settings { $0.activeTimetableID = timetable.id })
                } label: {
                    if timetable.id == model.activeTimetable?.id {
                        Label { Text(verbatim: timetable.name) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: timetable.name)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) {
            let current = selectionBinding(resolver).wrappedValue
            let todayWeek = resolver.context.startOfWeek(containing: model.today)
            if current.weekStart != todayWeek || current.selectedDate != model.today {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selection = TimetableSelection.initial(today: model.today, resolver: resolver)
                    } label: {
                        Text("timetable.week.today")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu(timetable: timetable, resolver: resolver, current: current)
            }
        }
    }

    private func optionsMenu(timetable: Timetable, resolver: ScheduleResolver, current: TimetableSelection) -> some View {
        let kind = viewKind(for: timetable)
        return Menu {
            Picker(selection: Binding(get: { kind }, set: { choose($0, for: timetable) })) {
                ForEach(TimetableViewChoice.offered, id: \.self) { option in
                    Label { Text(LocalizedStringKey(TimetableViewChoice.nameKey(option))) } icon: {
                        Image(systemName: TimetableViewChoice.symbolName(option))
                    }
                    .tag(option)
                }
            } label: {
                Text("timetable.options.view")
            }
            .pickerStyle(.inline)

            Picker(selection: Binding(get: { timetable.density.effective }, set: { setDensity($0, for: timetable) })) {
                Text("timetable.density.comfortable").tag(Density.comfortable)
                Text("timetable.density.compact").tag(Density.compact)
            } label: {
                Text("timetable.options.density")
            }
            .pickerStyle(.inline)

            if case .weekCycle(let cycle) = timetable.rotation {
                Section {
                    ForEach(1...max(1, min(cycle.length, 6)), id: \.self) { week in
                        Button {
                            if let jump = TimetableSelection.week(withCycleWeek: week, onOrAfter: model.today,
                                                                  today: model.today, resolver: resolver) {
                                selection = jump
                            }
                        } label: {
                            Text(verbatim: CycleLabel.week(week, scheme: timetable.rotation,
                                                           userLabel: resolver.rotation.label(forCycleWeek: week))?
                                .text(renderer: model.renderer) ?? "")
                        }
                    }
                } header: {
                    Text("timetable.options.showWeek")
                }
            }

            if TimetableViewChoice.isDayBased(kind) {
                Button {
                    editor = EditorPresentation.make(EditorContext.RouteID.dayChange, context: EditorContext(
                        timetableID: timetable.id, target: .dayChange(date: current.selectedDate, occurrence: nil, lessonID: nil)))
                } label: {
                    Label { Text("timetable.options.changeDay") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
                }
                .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.dayChange))
            }
        } label: {
            Label { Text("timetable.options") } icon: { Image(systemName: TimetableViewChoice.symbolName(kind)) }
        }
    }
}

private extension View {
    /// The navigation title becomes a menu of timetables only when there is more than one (no empty menu chevron).
    @ViewBuilder
    func timetableSwitcher<Menu: View>(isEnabled: Bool, @ViewBuilder menu: () -> Menu) -> some View {
        if isEnabled {
            toolbarTitleMenu { menu() }
        } else {
            self
        }
    }
}

/// Week bar + strip + the chosen view for one timetable.
private struct TimetableContent: View {
    let timetable: Timetable
    let resolver: ScheduleResolver
    let now: Date
    let viewKind: TimetableViewKind
    @Binding var selection: TimetableSelection
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let today = resolver.context.localDate(of: now)
        let strip = WeekStripModel.make(selection: selection, today: today, resolver: resolver)
        VStack(spacing: 0) {
            WeekNavigationBar(strip: strip, onPrevious: { shift(-1) }, onNext: { shift(1) })
                .padding(.horizontal, 8)
            if TimetableViewChoice.isDayBased(viewKind) {
                WeekDayStrip(strip: strip) { selection = selection.selecting($0, resolver: resolver) }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                Divider()
            }
            content(today: today, strip: strip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 80, abs(horizontal) > abs(value.translation.height) * 2 else { return }
                if TimetableViewChoice.isDayBased(viewKind) {
                    shiftDay(horizontal < 0 ? 1 : -1)
                } else {
                    shift(horizontal < 0 ? 1 : -1)
                }
            }
        )
    }

    @ViewBuilder
    private func content(today: LocalDate, strip: WeekStripModel) -> some View {
        let nowMinute = resolver.context.local(from: now).time.minuteOfDay
        switch viewKind {
        case .timeBlocks where !typeSize.isAccessibilitySize:
            TimeBlockWeekView(layout: TimeBlockLayout.week(containing: selection.weekStart, resolver: resolver),
                              strip: strip, timetable: timetable, reasons: reasons(for: strip.days.map(\.date)),
                              today: today, nowMinute: nowMinute, onOpen: onOpen)
        case .day, .tiles:
            let resolution = resolver.resolution(for: selection.selectedDate)
            if resolution.schedule.entries.isEmpty {
                DayEmptyView(schedule: resolution.schedule)
            } else if viewKind == .tiles || typeSize.isAccessibilitySize {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        TimelineItemsView(items: TodayState.timeline(resolution.schedule.entries, resolution: resolution,
                                                                     bell: bell(resolution.schedule.bellScheduleID), now: now),
                                          visibility: timetable.fieldVisibility,
                                          size: viewKind == .tiles ? .large : .regular, density: timetable.density,
                                          onOpen: onOpen)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else {
                TimeBlockDayView(layout: TimeBlockLayout.make(days: [resolution.schedule]), timetable: timetable,
                                 reasons: reasons(for: [selection.selectedDate]), today: today, nowMinute: nowMinute,
                                 onOpen: onOpen)
            }
        default:
            // Grid (and the week view at accessibility sizes, which the grid shows as a list).
            let layout = GridLayout.week(containing: selection.weekStart, resolver: resolver)
            GridWeekView(layout: layout, strip: strip, timetable: timetable,
                         reasons: reasons(for: layout.columns.map(\.date)), onOpen: onOpen, onAdd: onAdd)
        }
    }

    private func shift(_ weeks: Int) {
        selection = selection.shifted(byWeeks: weeks, resolver: resolver)
    }

    /// Next/previous shown day (crossing into the neighbouring week).
    private func shiftDay(_ step: Int) {
        var candidate = selection.selectedDate
        for _ in 0..<7 {
            candidate = candidate.adding(days: step)
            if resolver.timetable.enabledDays.contains(candidate.weekday) || resolver.timetable.enabledDays.isEmpty {
                selection = selection.selecting(candidate, resolver: resolver)
                return
            }
        }
    }

    private func reasons(for dates: [LocalDate]) -> [OccurrenceID: [ModificationReason]] {
        var result: [OccurrenceID: [ModificationReason]] = [:]
        for date in dates {
            for change in resolver.resolution(for: date).changes { result[change.occurrenceID] = change.reasons }
        }
        return result
    }

    private func bell(_ id: BellSchedule.ID?) -> BellSchedule? {
        guard let id else { return nil }
        return model.database?.bellSchedules.first { $0.id == id && !$0.isDeleted }
    }
}
