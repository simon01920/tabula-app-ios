// The Timetable tab (routes `timetable`, `timetable.grid|week|day|tiles`, `timetable.grid-next-week`,
// `timetable.grid-legend`). Phase 4U U4 (Opus H4, L2, L8; Astra F20, F22):
// - title = the timetable's name (a title menu switches timetables when there are several); the shown week's range
//   and rotation phrase ("12 Oct – 16 Oct · Odd week") are the iOS 26 navigation subtitle, so no date header and no
//   button-like "Week B" capsule sit in the content;
// - toolbar: leading "Today" only when another week/day is shown; trailing previous / next week, then ONE stable
//   "View Options" menu (`ellipsis`): the view picker (Grid / Week / Day / Tiles, each with its symbol), Edit
//   Timetable, Add Lesson, "Change for This Day…" in day views, then density, "Show Week" and Subjects;
// - an empty timetable shows "No lessons yet" with an Add Lesson button above the (quiet) grid;
// - the one-time symbol legend (TipKit, TimetableMarkers.swift) above weeks with change markers.
// Taps: a lesson → `LessonDetailView` sheet; a free grid slot → `QuickAddSheet`.
// Task / exam badges: `TimetableContent` puts the `LessonWorkIndex` of the shown week into the environment.
// Navigation state is `TimetableSelection` (TimetableUI, Linux-tested); "now" is `model.now`, refreshed once a minute
// by a TimelineView unless the clock is fixed (screenshot mode).
// HIG: toolbars.md › Actions ("Make sure the meaning of each control is clear"), › Item groupings (navigation and
// actions in separate groups; ToolbarSpacer), pull-down-buttons.md › Mobile (More button discoverability), menus.md ›
// Labels / Icons / Organization.
// APIs: NavigationStack, navigationSubtitle(_:) (iOS 26, SDK interface checked), toolbar { ToolbarItem(placement:
//       .topBarLeading / .topBarTrailing) }, ToolbarSpacer(.fixed, placement:) (iOS 26), Menu, Picker(.inline/.menu),
//       toolbarTitleMenu(content:), TimelineView(.everyMinute), sheet(item:), TipView, DragGesture, ContentUnavailableView.
import SwiftUI
import TipKit
import TimetableCore
import TimetableUI

struct TimetableRootView: View {
    /// View forced by a launch route (`timetable.grid` …) until the user picks one.
    private let initialView: TimetableViewKind?
    /// Screenshot routes: start this many weeks after the current one (shows the "Today" button).
    private let initialWeekOffset: Int
    /// Screenshot route `timetable.grid-legend`: show the symbol legend although the clock is fixed.
    private let forcesLegendTip: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: TimetableSelection?
    @State private var sessionViews: [Timetable.ID: TimetableViewKind] = [:]
    @State private var detail: LessonDetailTarget?
    @State private var quickAdd: QuickAddTarget?
    @State private var editor: EditorPresentation?
    @State private var management: ManagementSheet?

    init() {
        initialView = nil
        initialWeekOffset = 0
        forcesLegendTip = false
    }

    init(initialView: TimetableViewKind, weekOffset: Int = 0, forcesLegendTip: Bool = false) {
        self.initialView = initialView
        initialWeekOffset = weekOffset
        self.forcesLegendTip = forcesLegendTip
    }

    var body: some View {
        NavigationStack {
            Group {
                if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) {
                    VStack(spacing: 0) {
                        if !hasLessons(timetable) {
                            EmptyTimetableBanner { addLesson(timetable: timetable, resolver: resolver) }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        if model.isClockFixed {
                            content(timetable: timetable, resolver: resolver)
                        } else {
                            TimelineView(.everyMinute) { _ in
                                content(timetable: timetable, resolver: resolver)
                            }
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
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .timetableSwitcher(isEnabled: model.timetables.count > 1) { timetableMenu }
            .toolbar { toolbarContent }
        }
        .task { TimetableTips.configure(forceShow: forcesLegendTip) }
        .sheet(item: $detail) { target in
            LessonDetailView(target: target)
        }
        .sheet(item: $quickAdd) { target in
            QuickAddSheet(target: target)
        }
        .editorSheet($editor)
        .sheet(item: $management) { item in item.route.makeView() }
        .closesForDeepLink {   // QA fix Q6: a notification tap needs the screen
            detail = nil
            quickAdd = nil
            management = nil
        }
    }

    private func content(timetable: Timetable, resolver: ScheduleResolver) -> some View {
        TimetableContent(timetable: timetable, resolver: resolver, now: model.now,
                         viewKind: viewKind(for: timetable), selection: selectionBinding(resolver),
                         showsLegendTip: forcesLegendTip || !model.isClockFixed,
                         onOpen: open, onAdd: { quickAdd = $0 })
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

    /// "12 Oct – 16 Oct · Odd week" for the shown week (empty without a timetable).
    private var subtitle: Text {
        guard let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) else {
            return Text(verbatim: "")
        }
        let current = selectionBinding(resolver).wrappedValue
        let days = TimetableSelection.shownDays(weekStart: current.weekStart, resolver: resolver)
        let first = days.first ?? current.weekStart
        let last = days.last ?? current.weekStart.adding(days: 6)
        let cycleWeek = resolver.rotation.cycleWeek(on: current.weekStart.adding(days: 3))
        let cycle = CycleLabel.week(cycleWeek, scheme: timetable.rotation,
                                    userLabel: cycleWeek.flatMap(resolver.rotation.label(forCycleWeek:)))
        return Text(verbatim: TimetableSubtitle.text(first: model.formatter.date(first, style: .dayMonth),
                                                     last: model.formatter.date(last, style: .dayMonth),
                                                     cycle: cycle, renderer: model.renderer))
    }

    private func viewKind(for timetable: Timetable) -> TimetableViewKind {
        TimetableViewChoice.resolve(sessionViews[timetable.id] ?? initialView ?? timetable.defaultView)
    }

    private func selectionBinding(_ resolver: ScheduleResolver) -> Binding<TimetableSelection> {
        Binding(get: { selection ?? initialSelection(resolver) },
                set: { selection = $0 })
    }

    private func initialSelection(_ resolver: ScheduleResolver) -> TimetableSelection {
        let start = TimetableSelection.initial(today: model.today, resolver: resolver)
        return initialWeekOffset == 0 ? start : start.shifted(byWeeks: initialWeekOffset, resolver: resolver)
    }

    private func hasLessons(_ timetable: Timetable) -> Bool {
        model.database?.lessons.contains { $0.timetableID == timetable.id && !$0.isDeleted } ?? true
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

    /// "Add Lesson": the lesson editor prefilled with a free period of the shown day / week (`AddLessonSlot`), or
    /// without a slot when the week has none.
    private func addLesson(timetable: Timetable, resolver: ScheduleResolver) {
        let current = selectionBinding(resolver).wrappedValue
        let layout = TimetableCore.GridLayout.week(containing: current.weekStart, resolver: resolver)
        let weekEnd = current.weekStart.adding(days: 6)
        let preferred: LocalDate
        if TimetableViewChoice.isDayBased(viewKind(for: timetable)) {
            preferred = current.selectedDate
        } else if current.weekStart <= model.today && model.today <= weekEnd {
            preferred = model.today
        } else {
            preferred = current.weekStart
        }
        if let slot = AddLessonSlot.pick(layout: layout, preferredDate: preferred, timetable: timetable),
           let presentation = EditorPresentation.make(EditorContext.RouteID.lesson,
                                                      context: EditorContext(timetableID: timetable.id,
                                                                             target: .newLesson(slot))) {
            editor = presentation
        } else {
            management = ManagementSheet.make(Self.newLessonRoute)
        }
    }

    /// The new-lesson editor route (seed defaults pick the day and slot).
    private static let newLessonRoute = "editor.lesson-new"
    private static let editTimetableRoute = "editor.timetable"
    private static let subjectsRoute = "editor.subjects"

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
            let kind = viewKind(for: timetable)
            let dayBased = TimetableViewChoice.isDayBased(kind)
            let todayWeek = resolver.context.startOfWeek(containing: model.today)
            if current.weekStart != todayWeek || (dayBased && current.selectedDate != model.today) {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selection = TimetableSelection.initial(today: model.today, resolver: resolver)
                    } label: {
                        Text("timetable.week.today")
                    }
                    .accessibilityHint(Text(dayBased ? "timetable.a11y.todayHint.day" : "timetable.a11y.todayHint.week"))
                }
            }
            // Day views at accessibility sizes page by day in the content (DayPagerHeader); everywhere else the
            // toolbar pages by week.
            if !(dayBased && typeSize.isAccessibilitySize) {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        selection = current.shifted(byWeeks: -1, resolver: resolver)
                    } label: {
                        Label { Text("timetable.week.previous") } icon: { Image(systemName: "chevron.backward") }
                    }
                    Button {
                        selection = current.shifted(byWeeks: 1, resolver: resolver)
                    } label: {
                        Label { Text("timetable.week.next") } icon: { Image(systemName: "chevron.forward") }
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
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

            Section {
                Button { management = ManagementSheet.make(Self.editTimetableRoute) } label: {
                    Label { Text("timetable.options.editTimetable") } icon: { Image(systemName: "pencil") }
                }
                .disabled(!EditorRouteLookup.isAvailable(Self.editTimetableRoute))
                Button { addLesson(timetable: timetable, resolver: resolver) } label: {
                    Label { Text("timetable.options.addLesson") } icon: { Image(systemName: "plus") }
                }
                .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson))
                if TimetableViewChoice.isDayBased(kind) {
                    Button {
                        editor = EditorPresentation.make(EditorContext.RouteID.dayChange, context: EditorContext(
                            timetableID: timetable.id,
                            target: .dayChange(date: current.selectedDate, occurrence: nil, lessonID: nil)))
                    } label: {
                        Label { Text("timetable.options.changeDay") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
                    }
                    .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.dayChange))
                }
            }

            Section {
                Picker(selection: Binding(get: { timetable.density.effective }, set: { setDensity($0, for: timetable) })) {
                    Text("timetable.density.comfortable").tag(Density.comfortable)
                    Text("timetable.density.compact").tag(Density.compact)
                } label: {
                    Label { Text("timetable.options.density") } icon: { Image(systemName: "rectangle.compress.vertical") }
                }
                .pickerStyle(.menu)

                if case .weekCycle(let cycle) = timetable.rotation {
                    Menu {
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
                    } label: {
                        Label { Text("timetable.options.showWeek") } icon: { Image(systemName: "calendar") }
                    }
                }

                Button { management = ManagementSheet.make(Self.subjectsRoute) } label: {
                    Label { Text(LocalizedStringKey(DynamicL10nKeys.managementTitleKeys[2])) } icon: {
                        Image(systemName: "books.vertical")
                    }
                }
                .disabled(!EditorRouteLookup.isAvailable(Self.subjectsRoute))
            }
        } label: {
            // One stable glyph whatever the current view (Opus H4); VoiceOver and long-press read "View Options".
            Label { Text("timetable.options") } icon: { Image(systemName: "ellipsis") }
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

/// "No lessons yet" + Add Lesson, above an empty timetable (Astra F22: adding the first lesson needs no hidden gesture).
private struct EmptyTimetableBanner: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("timetable.empty.noLessons.title")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("timetable.empty.noLessons.detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label { Text("timetable.options.addLesson") } icon: { Image(systemName: "plus") }
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

/// Day header + the chosen view for one timetable.
private struct TimetableContent: View {
    let timetable: Timetable
    let resolver: ScheduleResolver
    let now: Date
    let viewKind: TimetableViewKind
    @Binding var selection: TimetableSelection
    let showsLegendTip: Bool
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    private let legendTip = ChangeLegendTip()

    var body: some View {
        let today = resolver.context.localDate(of: now)
        let strip = WeekStripModel.make(selection: selection, today: today, resolver: resolver)
        let work = LessonWorkSupport.index(dates: (0..<7).map { selection.weekStart.adding(days: $0) }
                                               + [selection.selectedDate],
                                           resolver: resolver, database: model.database)
        let dayBased = TimetableViewChoice.isDayBased(viewKind)
        VStack(spacing: 0) {
            if showsLegendTip, strip.days.contains(where: \.hasChanges) {
                TipView(legendTip)
                    .tipViewStyle(ChangeLegendTipStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            if dayBased {
                if typeSize.isAccessibilitySize {
                    DayPagerHeader(date: selection.selectedDate, onPrevious: { shiftDay(-1) }, onNext: { shiftDay(1) },
                                   onPick: { selection = selection.selecting($0, resolver: resolver) })
                        .padding(.horizontal, 12)
                } else {
                    WeekDayStrip(strip: strip) { selection = selection.selecting($0, resolver: resolver) }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                Divider()
            }
            content(today: today, strip: strip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.lessonWork, work)
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > 80, abs(horizontal) > abs(value.translation.height) * 2 else { return }
                if dayBased {
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
                // L5: the last tile ends above the floating tab bar at rest, not under it.
                .contentMargins(.bottom, 24, for: .scrollContent)
            } else {
                TimeBlockDayView(layout: TimeBlockLayout.make(days: [resolution.schedule]), timetable: timetable,
                                 reasons: reasons(for: [selection.selectedDate]), today: today, nowMinute: nowMinute,
                                 onOpen: onOpen)
            }
        default:
            // Grid (and the week view at accessibility sizes, which the grid shows as a list).
            let layout = TimetableCore.GridLayout.week(containing: selection.weekStart, resolver: resolver)
            GridWeekView(layout: layout, strip: strip, timetable: timetable,
                         reasons: reasons(for: layout.columns.map(\.date)), today: today, nowMinute: nowMinute,
                         onOpen: onOpen, onAdd: onAdd)
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
