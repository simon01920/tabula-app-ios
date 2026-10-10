// "Tap an empty cell → pick a subject" (route `timetable.quick-add`): one tap on a subject creates the recurring
// lesson for that slot through `model.apply(.upsert(...))` and closes the sheet; "New subject…" opens the subject
// editor (route `editor.subject`, disabled while it is not registered). The lesson itself is built by
// `QuickAddTarget.makeLesson` (TimetableUI, Linux-tested: day key, cycle week, period/time slot).
// APIs: NavigationStack, List, Section(content:header:footer:), Button, ContentUnavailableView,
//       presentationDetents(_:), sensoryFeedback(_:trigger:) (iOS 17), Environment(\.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

struct QuickAddSheet: View {
    let target: QuickAddTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorPresentation?
    @State private var failed = false
    @State private var added = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if subjects.isEmpty {
                        ContentUnavailableView {
                            Label { Text("timetable.quickAdd.noSubjects") } icon: { Image(systemName: "books.vertical") }
                        } description: {
                            EmptyView()
                        } actions: {
                            EmptyView()
                        }
                    }
                    ForEach(subjects) { subject in
                        Button {
                            add(subject)
                        } label: {
                            HStack(spacing: 12) {
                                SubjectBadge(subject: SubjectSummary(subject), size: 36)
                                Text(verbatim: subject.name)
                                    .foregroundStyle(Color.primary)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint(Text("timetable.quickAdd.subjectHint"))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.formatter.date(target.date, style: .full))
                        Text(verbatim: slotText)
                    }
                } footer: {
                    if failed {
                        Label { Text("timetable.quickAdd.failed") } icon: { Image(systemName: "exclamationmark.triangle") }
                    } else if let week = cycleWeekText {
                        Text(verbatim: model.renderer.format(key: "timetable.quickAdd.cycleWeekFooter", arguments: [.text(week)]))
                    }
                }
                Section {
                    Button {
                        editor = EditorPresentation.make(EditorContext.RouteID.subject,
                                                         context: EditorContext(timetableID: target.timetableID, target: .newSubject))
                    } label: {
                        Label { Text("timetable.quickAdd.newSubject") } icon: { Image(systemName: "plus") }
                    }
                    .disabled(!EditorRouteLookup.isAvailable(EditorContext.RouteID.subject))
                }
            }
            .navigationTitle(Text("timetable.quickAdd.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("timetable.action.cancel") }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: added)
        .editorSheet($editor)
    }

    private var subjects: [Subject] {
        guard let database = model.database else { return [] }
        return QuickAddSubjects.list(database, timetableID: target.timetableID, locale: model.formatter.locale)
    }

    /// "Period 3 · 9:50 – 10:35", or the time range for free-form rows.
    private var slotText: String {
        let range = model.formatter.timeRange(target.start, target.end)
        guard let number = target.lessonNumber, target.periodID != nil else { return range }
        return model.renderer.format(key: "timetable.quickAdd.period", arguments: [.integer(Int64(number)), .text(range)])
    }

    private var cycleWeekText: String? {
        guard let week = target.cycleWeek, let timetable = model.resolver(for: target.timetableID) else { return nil }
        return CycleLabel.week(week, scheme: timetable.timetable.rotation,
                               userLabel: timetable.rotation.label(forCycleWeek: week))?.text(renderer: model.renderer)
    }

    private func add(_ subject: Subject) {
        let lesson = target.makeLesson(id: Lesson.ID(UUID()), subjectID: subject.id)
        switch model.apply(.upsert(lesson)) {
        case .applied:
            added += 1
            dismiss()
        case .rejected, .readOnly, .failed:
            failed = true
        }
    }
}
