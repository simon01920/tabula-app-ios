// Read-only detail of one lesson occurrence (route `timetable.lesson-detail`, sheet from every timetable view and
// Today): subject, status, date/time/period, cycle weeks, the visible non-empty fields, what changed on this date
// with the usual value, and two actions: "Edit" (route `editor.lesson`) and "Change for this day"
// (route `editor.day-change`). Both are disabled with an explanation while the editor routes are not registered.
// Data comes from `LessonDetailModel` (TimetableUI, Linux-tested).
// APIs: NavigationStack, List, Section(content:header:footer:), LabeledContent(content:label:), ToolbarItem
//       (.cancellationAction / .primaryAction), Button(action:label:), disabled(_:), ContentUnavailableView,
//       presentationDetents(_:), Environment(\.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

/// Which occurrence a detail sheet shows.
struct LessonDetailTarget: Identifiable, Hashable {
    let timetableID: Timetable.ID
    let occurrenceID: OccurrenceID
    let date: LocalDate
    var id: String { occurrenceID.rawValue }

    init(_ lesson: ResolvedLesson) {
        timetableID = lesson.timetableID
        occurrenceID = lesson.id
        date = lesson.date
    }
}

struct LessonDetailView: View {
    let target: LessonDetailTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorPresentation?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("timetable.detail.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("timetable.action.done") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { openLessonEditor() } label: { Text("timetable.detail.edit") }
                            .disabled(lessonEditorContext == nil || !EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson))
                    }
                }
        }
        .editorSheet($editor)
    }

    private var detail: LessonDetailModel? {
        guard let database = model.database, let resolver = model.resolver(for: target.timetableID) else { return nil }
        return LessonDetailModel.make(occurrenceID: target.occurrenceID, date: target.date, resolver: resolver,
                                      database: database, formatter: model.formatter)
    }

    private var lessonEditorContext: EditorContext? {
        detail?.lessonID.map { EditorContext(timetableID: target.timetableID, target: .lesson($0)) }
    }

    @ViewBuilder
    private var content: some View {
        if let detail, let timetable = model.resolver(for: target.timetableID)?.timetable {
            List {
                headerSection(detail, timetable: timetable)
                whenSection(detail, timetable: timetable)
                if !detail.fields.isEmpty {
                    Section {
                        ForEach(detail.fields) { line in
                            LabeledContent {
                                Text(verbatim: line.text(renderer: model.renderer))
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Label { Text(LocalizedStringKey(Self.fieldNameKey(line.field))) } icon: {
                                    Image(systemName: line.symbolName)
                                }
                            }
                        }
                    }
                }
                if !detail.changes.isEmpty {
                    Section {
                        ForEach(detail.changes) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(change.reason.l10nKey)).font(.body.weight(.semibold))
                                if let usual = change.usualValue {
                                    Text(verbatim: model.renderer.format(key: "timetable.detail.usually",
                                                                         arguments: [.text(usual)]))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("timetable.detail.changes")
                    }
                }
                actionsSection(detail)
            }
        } else {
            ContentUnavailableView {
                Label { Text("timetable.detail.missing") } icon: { Image(systemName: "questionmark.square.dashed") }
            } description: {
                EmptyView()
            } actions: {
                EmptyView()
            }
        }
    }

    private func headerSection(_ detail: LessonDetailModel, timetable: Timetable) -> some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                SubjectBadge(subject: detail.lesson.subject, size: 52)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: detail.lesson.subject.name)
                        .font(.title2.weight(.semibold))
                        .strikethrough(detail.lesson.status == .cancelled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge = LessonStatusBadgeModel.make(status: detail.lesson.status, reasons: detail.reasons) {
                        LessonStatusBadge(badge)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(
                lesson: detail.lesson, visibility: timetable.fieldVisibility, reasons: detail.reasons,
                renderer: model.renderer)))
        }
    }

    private func whenSection(_ detail: LessonDetailModel, timetable: Timetable) -> some View {
        Section {
            Label {
                Text(verbatim: model.formatter.date(detail.lesson.date, style: .full))
            } icon: {
                Image(systemName: "calendar")
            }
            Label {
                Text(verbatim: model.formatter.timeRange(detail.lesson.startTime, detail.lesson.endTime))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "clock")
            }
            if let number = detail.lesson.periodNumber {
                Label {
                    Text(verbatim: model.renderer.format(key: "timetable.detail.period", arguments: [.integer(Int64(number))]))
                } icon: {
                    Image(systemName: "number")
                }
            } else if let label = detail.lesson.periodLabel, !label.trimmingCharacters(in: .whitespaces).isEmpty {
                Label { Text(verbatim: label) } icon: { Image(systemName: "number") }
            }
            if !detail.cycleWeeks.isEmpty {
                let weeks = detail.cycleWeeks.compactMap { week in
                    CycleLabel.week(week, scheme: timetable.rotation,
                                    userLabel: model.resolver(for: timetable.id)?.rotation.label(forCycleWeek: week))
                        .map { $0.text(renderer: model.renderer) }
                }
                Label {
                    Text(verbatim: model.renderer.format(key: "timetable.detail.weeks",
                                                         arguments: [.text(model.formatter.list(weeks))]))
                } icon: {
                    Image(systemName: "repeat")
                }
            }
        }
    }

    private func actionsSection(_ detail: LessonDetailModel) -> some View {
        let dayChangeAvailable = EditorRouteLookup.isAvailable(EditorContext.RouteID.dayChange)
        let lessonEditorAvailable = EditorRouteLookup.isAvailable(EditorContext.RouteID.lesson)
        return Section {
            Button {
                editor = EditorPresentation.make(EditorContext.RouteID.dayChange, context: EditorContext(
                    timetableID: target.timetableID,
                    target: .dayChange(date: target.date, occurrence: target.occurrenceID, lessonID: detail.lessonID)))
            } label: {
                Label { Text("timetable.detail.changeDay") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
            }
            .disabled(!dayChangeAvailable)
        } footer: {
            if detail.lessonID == nil {
                Text("timetable.detail.oneOffFooter")
            } else if !dayChangeAvailable || !lessonEditorAvailable {
                Text("timetable.detail.editorsMissing")
            }
        }
    }

    private func openLessonEditor() {
        guard let context = lessonEditorContext else { return }
        editor = EditorPresentation.make(EditorContext.RouteID.lesson, context: context)
    }

    /// Catalog key of a field's name in the detail list.
    static func fieldNameKey(_ field: LessonField) -> String { DynamicL10nKeys.lessonDetailField(field) }
}
