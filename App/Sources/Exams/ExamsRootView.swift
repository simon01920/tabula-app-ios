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
    @Environment(AppModel.self) private var model
    /// `nil` = not chosen by the user yet → `initialSegment` (no `State(initialValue:)` in initialisers).
    @State private var chosenSegment: ExamSegment?
    @State private var editor: ExamEditorTarget?
    /// The pushed details (the featured card pushes by appending its id; rows use value links).
    @State private var path: [Exam.ID] = []

    init(initialSegment: ExamSegment = .upcoming) {
        self.initialSegment = initialSegment
    }

    private var segment: ExamSegment { chosenSegment ?? initialSegment }
    private var segmentBinding: Binding<ExamSegment> {
        Binding(get: { segment }, set: { chosenSegment = $0 })
    }

    private var listModel: ExamListModel? {
        model.database.map { ExamListModel.make(database: $0, today: model.today, context: model.calendarContext) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(Text("exams.title"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { editor = .new } label: {
                            Label { Text("exams.add") } icon: { Image(systemName: "plus") }
                        }
                    }
                }
                .navigationDestination(for: Exam.ID.self) { id in
                    ExamDetailContent(examID: id)
                }
        }
        .sheet(item: $editor) { target in
            ExamEditorView(target: target)
        }
        .closesForDeepLink { editor = nil }   // QA fix Q6: a notification tap needs the screen
    }

    @ViewBuilder
    private var content: some View {
        if let list = listModel, !list.isEmpty {
            List {
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
                Button { path.append(next.id) } label: {
                    ExamFeaturedCard(row: next, facts: facts(for: next.exam), texts: texts)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .accessibilityAddTraits(.isLink)
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
