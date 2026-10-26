// Read-only exam detail (stage B2): countdown, subject, type, date, time, room / building (per the timetable's field
// visibility; empty = absent), topics, notes, mark done / not done and Edit. Used pushed from the Exams tab and as the
// notification deep-link sheet `exams.detail` (`ExamDetailSheet`).
// Topics have no per-topic done state in the frozen schema, so they are shown as a plain bulleted list.
// APIs: List, Section(content:header:), LabeledContent(content:label:), Label(title:icon:), NavigationStack,
//   ToolbarItem(.cancellationAction / .primaryAction), sheet(item:), onChange(of:initial:_:) (iOS 17), Environment(\.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

/// The sheet form of the detail (deep link / route): its own NavigationStack and a Done button.
struct ExamDetailSheet: View {
    let examID: Exam.ID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExamDetailContent(examID: examID)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton()
                    }
                }
        }
    }
}

/// The detail list (no navigation container of its own).
struct ExamDetailContent: View {
    let examID: Exam.ID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ExamEditorTarget?

    private var exam: Exam? {
        model.database?.exams.first { $0.id == examID && !$0.isDeleted }
    }

    var body: some View {
        Group {
            if let exam {
                detail(exam)
            } else {
                ContentUnavailableView {
                    Label { Text("exams.detail.missing") } icon: { Image(systemName: "graduationcap") }
                }
            }
        }
        .navigationTitle(Text("exams.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .existing(examID) } label: { Text("exams.action.edit") }
                    .disabled(exam == nil)
            }
        }
        .sheet(item: $editor) { target in
            ExamEditorView(target: target)
        }
        .closesForDeepLink { editor = nil }   // QA fix Q6 (pushed in the Exams tab, not nested in a tab sheet)
        // Deleted from the editor: leave the detail (pop / dismiss) instead of showing an empty page.
        .onChange(of: exam == nil) { _, isMissing in
            if isMissing { dismiss() }
        }
    }

    @ViewBuilder
    private func detail(_ exam: Exam) -> some View {
        let database = model.database
        let texts = ExamTexts(renderer: model.renderer)
        let facts = ExamFacts(exam: exam, visibility: database.map { ExamFacts.visibility(for: exam, in: $0) } ?? .all)
        let subject = exam.subjectID.flatMap { id in
            database?.subjects.first { $0.id == id && !$0.isDeleted }.map(SubjectSummary.init)
        }
        let row = ExamRow(exam: exam, subject: subject, today: model.today)
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    ExamBadge(subject: subject, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: exam.title).font(.title2.weight(.semibold))
                        Label {
                            Text(verbatim: exam.isCompleted
                                 ? model.renderer.string(forKey: "exams.status.done") : texts.when(row.when))
                                .font(.headline)
                        } icon: {
                            Image(systemName: exam.isCompleted ? "checkmark.circle.fill" : row.urgency.symbolName)
                                .foregroundStyle(exam.isCompleted ? Color.green : row.urgency.tint)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: texts.accessibilityLabel(row, facts: facts)))
            }
            Section {
                fact("exams.detail.date", texts.fullDate(exam.date))
                if let time = texts.time(exam) { fact("exams.detail.time", time) }
                fact("exams.detail.kind", texts.kind(exam.kind))
                if let subject { fact("exams.detail.subject", subject.name) }
                if let room = facts.room { fact("exams.detail.room", room) }
                if let building = facts.building { fact("exams.detail.building", building) }
            }
            if !facts.topics.isEmpty {
                Section {
                    ForEach(Array(facts.topics.enumerated()), id: \.offset) { _, topic in
                        Label { Text(verbatim: topic) } icon: {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("exams.detail.topics")
                }
            }
            if let notes = facts.notes {
                Section {
                    Text(verbatim: notes)
                } header: {
                    Text("exams.detail.notes")
                }
            }
            Section {
                if exam.isCompleted {
                    Button { ExamActions.reopen(exam.id, model: model) } label: {
                        Text("exams.action.markNotDone").frame(maxWidth: .infinity, minHeight: 44)
                    }
                } else {
                    Button { ExamActions.markDone(exam.id, model: model) } label: {
                        Text("exams.action.markDone").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }

    private func fact(_ key: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).multilineTextAlignment(.trailing)
        } label: {
            Text(key)
        }
    }
}

/// `exams.detail` launch / deep-link route: shows `AppNavigation.presentedItem` (`.exam`), else a sample exam from the
/// seed data (screenshots), else an empty state.
struct ExamDetailRouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        if let id = examID {
            ExamDetailSheet(examID: id)
        } else {
            ExamRouteEmptyView()
        }
    }

    private var examID: Exam.ID? {
        if case .exam(let id)? = navigation.presentedItem { return id }
        return ExamSeedPicker.sample(in: model)?.id
    }
}

/// Picks seed data for the launch routes.
@MainActor
enum ExamSeedPicker {
    /// The next upcoming exam, else the first exam of any kind.
    static func sample(in model: AppModel) -> Exam? {
        guard let database = model.database else { return nil }
        let list = ExamListModel.make(database: database, today: model.today, context: model.calendarContext)
        return list.next?.exam ?? list.history.first?.exam
    }
}

/// Shown by a sheet route when the seed has no exam.
struct ExamRouteEmptyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text("exams.empty.title") } icon: { Image(systemName: "graduationcap") }
            } description: {
                Text("exams.empty.detail")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
        }
    }
}
