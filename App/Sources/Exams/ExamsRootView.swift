// The Exams tab (stage B2; PRODUCT.md "Exams"): Upcoming (the next exam as a big countdown card, then exam periods
// and weeks) and History (past or completed exams, with "mark done"), an empty state, and "+" for the editor.
// Tapping an exam pushes the detail; the same detail is the notification deep-link sheet (`exams.detail`).
// Keep the type name and the no-argument use `ExamsRootView()` (app shell, `exams` route).
// Logic: Packages/TimetableUI/Sources/TimetableUI/Exams/ExamListModel.swift (Linux-tested).
// APIs: NavigationStack, navigationDestination(for:destination:), List, Section(content:header:), Picker with
//   .segmented style, NavigationLink(value:label:), swipeActions, ContentUnavailableView(label:description:actions:),
//   sheet(item:content:), ToolbarItem(placement: .primaryAction), listRowBackground, listRowInsets.
import SwiftUI
import TimetableCore
import TimetableUI

/// The two views of the tab.
enum ExamSegment: String, CaseIterable, Identifiable {
    case upcoming, history
    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .upcoming: return "exams.segment.upcoming"
        case .history: return "exams.segment.history"
        }
    }
}

/// What the editor sheet opens.
enum ExamEditorTarget: Identifiable, Hashable {
    case new
    case existing(Exam.ID)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let id): return id.uuidString
        }
    }
}

struct ExamsRootView: View {
    private let initialSegment: ExamSegment
    private let initialSelection: Exam.ID?
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutWidth) private var layoutWidth
    @Environment(\.layoutContainerWidth) private var containerWidth
    /// `nil` = not chosen by the user yet → `initialSegment` (no `State(initialValue:)` in initialisers).
    @State private var chosenSegment: ExamSegment?
    @State private var editor: ExamEditorTarget?
    /// The pushed details (the featured card pushes by appending its id; rows use value links). In the split layout
    /// the same path is the detail column's stack (a sidebar link replaces it).
    @State private var path: [Exam.ID] = []
    @State private var didSelectInitial = false

    /// `initialSelection`: an exam to open on appearing (screenshot route `exams.selected`).
    init(initialSegment: ExamSegment = .upcoming, initialSelection: Exam.ID? = nil) {
        self.initialSegment = initialSegment
        self.initialSelection = initialSelection
    }

    private var segment: ExamSegment { chosenSegment ?? initialSegment }
    private var segmentBinding: Binding<ExamSegment> {
        Binding(get: { segment }, set: { chosenSegment = $0 })
    }

    private var listModel: ExamListModel? {
        model.database.map { ExamListModel.make(database: $0, today: model.today, context: model.calendarContext) }
    }

    var body: some View {
        Group {
            if layoutWidth.showsSplit {
                // Adaptive layout: the list beside the open exam. The same `path` drives both layouts, so a resize keeps
                // the open exam (pushed when narrow, in the detail column when wide).
                NavigationSplitView {
                    list
                        .listColumnWidth()
                } detail: {
                    NavigationStack(path: $path) {
                        ContentUnavailableView {
                            Label { Text("exams.split.placeholder") } icon: { Image(systemName: "graduationcap") }
                        }
                        .navigationDestination(for: Exam.ID.self) { detail($0) }
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    list.navigationDestination(for: Exam.ID.self) { detail($0) }
                }
            }
        }
        // Screenshot route `exams.selected`: once the width is measured (keyed, so the closure sees the measured layout).
        .task(id: containerWidth > 0) {
            guard containerWidth > 0, !didSelectInitial, let initialSelection else { return }
            didSelectInitial = true
            open(initialSelection)
        }
        .sheet(item: $editor) { target in
            ExamEditorView(target: target)
        }
        .closesForDeepLink { editor = nil }   // QA fix Q6: a notification tap needs the screen
    }

    /// The list with its title and toolbar (the stack's root, or the split view's list column).
    private var list: some View {
        content
            .navigationTitle(Text("exams.title"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = .new } label: {
                        Label { Text("exams.add") } icon: { Image(systemName: "plus") }
                    }
                }
            }
    }

    /// The detail, with its editor presented by this tab (survives a resize between the two layouts).
    private func detail(_ id: Exam.ID) -> some View {
        ExamDetailContent(examID: id, pane: DetailPane(close: { path = [] }, edit: { editor = .existing(id) }))
    }

    /// Opens an exam: replaces the detail column when side by side, else pushes it (unchanged on iPhone).
    private func open(_ id: Exam.ID) {
        if layoutWidth.showsSplit { path = [id] } else { path.append(id) }
    }

    /// The exam in the detail column stays highlighted (HIG split-views.md › Best practices); nil = default background.
    private func selectionBackground(_ id: Exam.ID) -> Color? {
        layoutWidth.showsSplit && path.last == id ? Color(uiColor: .systemGray5) : nil
    }

    @ViewBuilder
    private var content: some View {
        if let list = listModel, !list.isEmpty {
            List {
                if AdaptiveLayout.isStacked(typeSize) {
                    // Phase 10 screenshot review (iPhone SE, sk, AX-XXXL): the menu fallback of the segmented picker
                    // was clipped at the top and bottom in this tight, background-less row. At accessibility sizes the
                    // two choices are full-width rows instead, which wrap any translation.
                    Section {
                        ForEach(ExamSegment.allCases) { option in
                            Button { segmentBinding.wrappedValue = option } label: {
                                HStack(spacing: 12) {
                                    Text(option.titleKey)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if segment == option {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(segment == option ? .isSelected : [])
                        }
                    } header: {
                        Text("exams.segment.label")
                    }
                } else {
                    Section {
                        Picker(selection: segmentBinding) {
                            ForEach(ExamSegment.allCases) { Text($0.titleKey).tag($0) }
                        } label: {
                            Text("exams.segment.label")
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }
                switch segment {
                case .upcoming: upcoming(list)
                case .history: history(list)
                }
            }
        } else {
            ContentUnavailableView {
                Label { Text("exams.empty.title") } icon: { Image(systemName: "graduationcap") }
            } description: {
                Text("exams.empty.detail")
            } actions: {
                Button { editor = .new } label: { Text("exams.add").frame(minHeight: 44).onInkLabel() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Upcoming

    @ViewBuilder
    private func upcoming(_ list: ExamListModel) -> some View {
        let texts = ExamTexts(renderer: model.renderer)
        if let next = list.next {
            Section {
                // M24: the whole card is the control, with the chevron inside it. A List's own NavigationLink would put
                // its disclosure chevron outside the card, so the card is a button that pushes the detail.
                Button { open(next.id) } label: {
                    ExamFeaturedCard(row: next, facts: facts(for: next.exam), texts: texts)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { doneAction(next) }
            } header: {
                Text("exams.next.title")
            }
            ForEach(list.periods) { period in
                Section {
                    ForEach(period.rows) { upcomingRow($0, texts: texts) }
                } header: {
                    ExamPeriodHeader(section: period, texts: texts)
                }
            }
            ForEach(list.weeks) { week in
                Section {
                    ForEach(week.rows) { upcomingRow($0, texts: texts) }
                } header: {
                    Text(verbatim: texts.weekTitle(week.label))
                }
            }
        } else {
            Section {
                ContentUnavailableView {
                    Label { Text("exams.empty.upcoming.title") } icon: { Image(systemName: "graduationcap") }
                } description: {
                    Text("exams.empty.upcoming.detail")
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func upcomingRow(_ row: ExamRow, texts: ExamTexts) -> some View {
        NavigationLink(value: row.id) {
            ExamRowView(row: row, facts: facts(for: row.exam), texts: texts)
        }
        .listRowBackground(selectionBackground(row.id))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { doneAction(row) }
    }

    private func doneAction(_ row: ExamRow) -> some View {
        Button { ExamActions.markDone(row.id, model: model) } label: {
            Label { Text(LocalizedStringKey(ExamActions.completion(of: row.exam, model: model).l10nKey)) } icon: {
                Image(AppSymbol.completed)
            }
        }
        .tint(Color.ink)
    }

    // MARK: History

    @ViewBuilder
    private func history(_ list: ExamListModel) -> some View {
        let texts = ExamTexts(renderer: model.renderer)
        if list.history.isEmpty {
            Section {
                ContentUnavailableView {
                    Label { Text("exams.empty.history.title") } icon: { Image(systemName: "clock.arrow.circlepath") }
                } description: {
                    Text("exams.empty.history.detail")
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(list.history) { row in
                    NavigationLink(value: row.id) {
                        ExamRowView(row: row, facts: facts(for: row.exam), texts: texts)
                    }
                    .listRowBackground(selectionBackground(row.id))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if row.exam.isCompleted {
                            Button { ExamActions.reopen(row.id, model: model) } label: {
                                Label { Text("exams.action.markNotDone") } icon: { Image(systemName: "arrow.uturn.backward") }
                            }
                            .tint(Color.secondary)
                        } else {
                            doneAction(row)
                        }
                    }
                }
            }
        }
    }

    private func facts(for exam: Exam) -> ExamFacts {
        let visibility = model.database.map { ExamFacts.visibility(for: exam, in: $0) } ?? .all
        return ExamFacts(exam: exam, visibility: visibility)
    }
}
