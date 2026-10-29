// "Tap an empty cell → pick a subject" (route `timetable.quick-add`): one tap on a subject creates the recurring
// lesson for that slot through `model.apply(.upsert(...))` and closes the sheet; "New subject…" opens the subject
// editor (route `editor.subject`, disabled while it is not registered). The lesson itself is built by
// `QuickAddTarget.makeLesson` (TimetableUI, Linux-tested: day key, cycle week, period/time slot).
// Phase 4U U4 (Opus H14): an opaque grouped background (no grid bleeding through the glass sheet), and a header that
// states the weekly scope, "Every Monday · Week B · Period 7 (13:40–14:25)" (`QuickAddScope`), instead of one date.
// HIG: sheets.md › Mobile (medium detent for progressive disclosure, Cancel on the leading edge).
// APIs: NavigationStack, List, Section(content:header:footer:), Button, ContentUnavailableView,
//       presentationDetents(_:), presentationBackground(_:) (iOS 16.4), sensoryFeedback(_:trigger:) (iOS 17),
//       Environment(\.dismiss).
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
                    Text(verbatim: scopeText)
                        .textCase(nil)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                } footer: {
                    if failed {
                        Label { Text("timetable.quickAdd.failed") } icon: { Image(systemName: "exclamationmark.triangle") }
                    } else if cycleWeek != nil {
                        Text("timetable.quickAdd.cycleWeekOnlyFooter")
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
        // Opaque: the colourful grid must not show through behind the subject list (Opus H14).
        .presentationBackground(Color(.systemGroupedBackground))
        .sensoryFeedback(.success, trigger: added)
        .editorSheet($editor)
    }

    private var subjects: [Subject] {
        guard let database = model.database else { return [] }
        return QuickAddSubjects.list(database, timetableID: target.timetableID, locale: model.formatter.locale)
    }

    /// "Every Monday · Week B · Period 7 (13:40–14:25)": quick add creates a weekly slot (UX plan Q1).
    private var scopeText: String {
        var dayLabel: String?
        if case .cycleDay(let index) = target.dayKey {
            dayLabel = model.resolver(for: target.timetableID)?.rotation.label(forCycleDay: index)
        }
        return QuickAddScope.text(target, cycleWeek: cycleWeek, userDayLabel: dayLabel, renderer: model.renderer)
    }

    private var cycleWeek: CycleLabel? {
        guard let week = target.cycleWeek, let resolver = model.resolver(for: target.timetableID) else { return nil }
        return CycleLabel.week(week, scheme: resolver.timetable.rotation,
                               userLabel: resolver.rotation.label(forCycleWeek: week))
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
