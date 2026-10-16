// "Change for this day" (`editor.day-change`): creates one `ScheduleOverride` for one date: cancel a lesson, change a
// lesson (substitute subject, room, building, teacher), cancel the whole day, a short day through another bell
// schedule, "follow another day", or an extra lesson. Already existing changes of the date are listed and can be
// removed. Only the fields the timetable shows are offered (field rule).
// Logic: Packages/TimetableUI/.../Editors/DayChangeDraft.swift (Linux-tested).
// APIs: Picker, Section, Label, ScheduleResolver.resolution(for:) (core), DatePicker through DateRow.
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the day-change editor as sheet content. `date` defaults to today, `lessonID` pre-selects a lesson.
struct DayChangeEditorView: View {
    var date: LocalDate?
    var lessonID: Lesson.ID?
    var timetableID: Timetable.ID?
    @Environment(AppModel.self) private var model
    @State private var newID = ScheduleOverride.ID(UUID())

    var body: some View {
        if let database = model.database,
           let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            let day = date ?? model.today
            let entries = DayChangeEditorView.lessonEntries(model: model, timetable: timetable, date: day)
            let draft = DayChangeDraft(
                timetable: timetable, date: day, lessonID: lessonID ?? entries.first?.lessonID,
                schedule: defaultSchedule(of: timetable, in: database), id: newID)
            EditorScaffold(
                titleKey: "editor.dayChange.title",
                initial: draft,
                canSave: { $0.canSave(visibility: timetable.fieldVisibility) },
                save: { draft in
                    guard let override = draft.makeOverride(visibility: timetable.fieldVisibility) else { return nil }
                    return model.apply(.upsert(override))
                },
                content: { draft in DayChangeFormContent(draft: draft, timetable: timetable) })
        } else {
            EditorUnavailableView(messageKey: "editor.dayChange.unavailable")
        }
    }

    private func defaultSchedule(of timetable: Timetable, in database: TabulaDatabase) -> BellSchedule? {
        guard case .bellSchedule(let id, _) = timetable.timeStructure else { return nil }
        return database.bellSchedules.first { $0.id == id && !$0.isDeleted }
    }

    /// The recurring lessons that take place on `date` (candidates for cancel / change).
    @MainActor
    static func lessonEntries(model: AppModel, timetable: Timetable, date: LocalDate) -> [DayLessonEntry] {
        guard let resolver = model.resolver(for: timetable.id) else { return [] }
        return resolver.resolution(for: date).schedule.entries.compactMap { entry in
            guard entry.status != .cancelled, case .lesson(let id) = entry.source else { return nil }
            return DayLessonEntry(lessonID: id, subjectName: entry.subject.name, start: entry.startTime, end: entry.endTime)
        }
    }
}

/// One lesson of the chosen date, for the lesson picker.
struct DayLessonEntry: Identifiable, Equatable {
    var id: Lesson.ID { lessonID }
    let lessonID: Lesson.ID
    let subjectName: String
    let start: LocalTime
    let end: LocalTime
}

private struct DayChangeFormContent: View {
    @Binding var draft: DayChangeDraft
    let timetable: Timetable
    @Environment(AppModel.self) private var model
    @State private var editingBell = false

    private var database: TabulaDatabase? { model.database }
    private var labels: EditorLabels { EditorLabels(model: model) }
    private var visibility: FieldVisibility { timetable.fieldVisibility }

    private var entries: [DayLessonEntry] {
        DayChangeEditorView.lessonEntries(model: model, timetable: timetable, date: draft.date)
    }

    /// The timetable's subjects in display order (manual order, then name; `SubjectOrder`).
    private var subjects: [Subject] {
        database.map { SubjectOrder.live($0, timetableID: timetable.id, locale: model.formatter.locale) } ?? []
    }

    private var schedules: [BellSchedule] {
        (database?.bellSchedules ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private var defaultSchedule: BellSchedule? {
        guard case .bellSchedule(let id, _) = timetable.timeStructure else { return nil }
        return schedules.first { $0.id == id }
    }

    private var availableKinds: [DayChangeDraft.Kind] {
        DayChangeDraft.Kind.allCases.filter { kind in
            !DayChangeDraft.kindsNeedingLesson().contains(kind) || !entries.isEmpty || draft.kind == kind
        }
    }

    var body: some View {
        dateSection
        kindSection
        detailSection
        existingSection
    }

    // MARK: Date and kind

    private var dateSection: some View {
        Section {
            DateRow(titleKey: "editor.dayChange.date", date: $draft.date)
                .onChange(of: draft.date) { _, _ in
                    if let current = draft.lessonID, !entries.contains(where: { $0.lessonID == current }) {
                        draft.lessonID = entries.first?.lessonID
                    }
                }
        } footer: {
            Text(verbatim: model.formatter.date(draft.date, style: .full))
        }
    }

    private var kindSection: some View {
        Section {
            Picker(selection: $draft.kind) {
                ForEach(availableKinds, id: \.self) { kind in
                    Label { Text(LocalizedStringKey(kind.l10nKey)) } icon: { Image(systemName: kind.symbolName) }.tag(kind)
                }
            } label: {
                Text("editor.dayChange.kind")
            }
            .pickerStyle(.inline)
        } header: {
            Text("editor.dayChange.kind")
        } footer: {
            if entries.isEmpty { Text("editor.dayChange.noLessons") }
        }
    }

    // MARK: Per-kind rows

    @ViewBuilder
    private var detailSection: some View {
        switch draft.kind {
        case .cancelLesson:
            Section {
                lessonPicker
            } footer: {
                issueFooter
            }
        case .changeLesson:
            Section {
                lessonPicker
            } footer: {
                issueFooter
            }
            Section {
                Picker(selection: $draft.substituteSubjectID) {
                    Text("editor.dayChange.subject.same").tag(Subject.ID?.none)
                    ForEach(subjects) { subject in
                        Text(verbatim: subject.name).tag(Subject.ID?.some(subject.id))
                    }
                } label: {
                    Text("editor.dayChange.subject")
                }
                if visibility.isVisible(.room) { LabeledTextField(titleKey: "editor.field.room", text: $draft.room) }
                if visibility.isVisible(.building) { LabeledTextField(titleKey: "editor.field.building", text: $draft.building) }
                if visibility.isVisible(.teacher) { LabeledTextField(titleKey: "editor.field.teacher", text: $draft.teacher) }
            } header: {
                Text("editor.dayChange.changes")
            } footer: {
                Text("editor.dayChange.changes.footer")
            }
        case .cancelDay:
            Section {
                LabeledTextField(titleKey: "editor.dayChange.note", text: $draft.note)
            } footer: {
                Text("editor.dayChange.cancelDay.footer")
            }
        case .shortDay:
            Section {
                Picker(selection: $draft.bellScheduleID) {
                    if draft.bellScheduleID == nil { Text("editor.dayChange.bell.choose").tag(BellSchedule.ID?.none) }
                    ForEach(schedules) { schedule in
                        Text(verbatim: schedule.name).tag(BellSchedule.ID?.some(schedule.id))
                    }
                } label: {
                    Text("editor.dayChange.bell")
                }
                Button { editingBell = true } label: {
                    Label { Text("editor.dayChange.bell.edit") } icon: { Image(systemName: "bell") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("editor.dayChange.bell.footer")
                    issueFooter
                }
            }
            .sheet(isPresented: $editingBell) { BellScheduleEditorView(timetableID: timetable.id) }
        case .followDay:
            Section {
                Picker(selection: $draft.followDay) {
                    if draft.followDay == nil { Text("editor.dayChange.follow.choose").tag(DayKey?.none) }
                    ForEach(DayChoices.keys(for: timetable, firstWeekday: model.calendarContext.firstWeekday), id: \.self) { key in
                        Text(verbatim: labels.day(key, in: timetable)).tag(DayKey?.some(key))
                    }
                } label: {
                    Text("editor.dayChange.follow")
                }
                if case .weekCycle(let cycle) = timetable.rotation {
                    Picker(selection: $draft.followCycleWeek) {
                        Text("editor.dayChange.follow.week.natural").tag(Int?.none)
                        ForEach(1...max(1, cycle.length), id: \.self) { week in
                            Text(verbatim: labels.week(week, in: timetable)).tag(Int?.some(week))
                        }
                    } label: {
                        Text("editor.dayChange.follow.week")
                    }
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("editor.dayChange.follow.footer")
                    issueFooter
                }
            }
        case .extraLesson:
            Section {
                Picker(selection: $draft.extraSubjectID) {
                    if draft.extraSubjectID == nil { Text("editor.lesson.subject.choose").tag(Subject.ID?.none) }
                    ForEach(subjects) { subject in
                        HStack {
                            SubjectBadge(subject: SubjectSummary(subject), size: 28)
                            Text(verbatim: subject.name)
                        }
                        .tag(Subject.ID?.some(subject.id))
                    }
                } label: {
                    Text("editor.lesson.subject")
                }
                if visibility.isVisible(.room) { LabeledTextField(titleKey: "editor.field.room", text: $draft.extraRoom) }
                if visibility.isVisible(.teacher) { LabeledTextField(titleKey: "editor.field.teacher", text: $draft.extraTeacher) }
            } footer: {
                issueFooter
            }
            Section {
                SlotEditorRows(slot: $draft.extraSlot, schedule: defaultSchedule, timetable: timetable)
            } header: {
                Text("editor.slot.header")
            } footer: {
                ForEach(draft.extraSlot.issues, id: \.self) { issue in
                    Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
                }
            }
        }
    }

    private var lessonPicker: some View {
        Picker(selection: $draft.lessonID) {
            if draft.lessonID == nil { Text("editor.dayChange.lesson.choose").tag(Lesson.ID?.none) }
            ForEach(entries) { entry in
                Text(verbatim: model.renderer.format(key: "editor.dayChange.lessonRow", arguments: [
                    .text(model.formatter.timeRange(entry.start, entry.end)), .text(entry.subjectName)]))
                    .tag(Lesson.ID?.some(entry.lessonID))
            }
        } label: {
            Text("editor.dayChange.lesson")
        }
    }

    @ViewBuilder
    private var issueFooter: some View {
        ForEach(draft.issues(visibility: visibility), id: \.self) { issue in
            if issue != .nothingChanged || draft.kind == .changeLesson {
                Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
            }
        }
    }

    // MARK: Existing changes of the date

    @ViewBuilder
    private var existingSection: some View {
        let existing = (database?.overrides ?? []).filter {
            !$0.isDeleted && $0.timetableID == timetable.id && $0.date == draft.date
        }
        if !existing.isEmpty {
            Section {
                ForEach(existing) { item in
                    HStack {
                        Label {
                            Text(verbatim: describe(item.change))
                        } icon: {
                            Image(systemName: symbol(of: item.change))
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            model.apply(.delete(item.id))
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("editor.dayChange.existing.remove"))
                    }
                    .accessibilityElement(children: .contain)
                }
            } header: {
                Text("editor.dayChange.existing")
            } footer: {
                Text("editor.dayChange.existing.footer")
            }
        }
    }

    private func subjectName(_ id: Subject.ID) -> String {
        database?.subjects.first { $0.id == id }?.name ?? ""
    }

    private func lessonSubjectName(_ id: Lesson.ID) -> String {
        database?.lessons.first { $0.id == id }.map { subjectName($0.subjectID) } ?? ""
    }

    private func describe(_ change: OverrideChange) -> String {
        let renderer = model.renderer
        switch change {
        case .cancelLesson(let id):
            return renderer.format(key: "editor.dayChange.existing.cancelLesson", arguments: [.text(lessonSubjectName(id))])
        case .modifyLesson(let id, _):
            return renderer.format(key: "editor.dayChange.existing.changeLesson", arguments: [.text(lessonSubjectName(id))])
        case .addLesson(let oneOff):
            return renderer.format(key: "editor.dayChange.existing.extraLesson", arguments: [.text(subjectName(oneOff.subjectID))])
        case .cancelDay(let note):
            if let note, !note.isEmpty {
                return renderer.format(key: "editor.dayChange.existing.cancelDayNote", arguments: [.text(note)])
            }
            return renderer.string(forKey: "editor.dayChange.existing.cancelDay")
        case .useBellSchedule(let id):
            return renderer.format(key: "editor.dayChange.existing.shortDay",
                                   arguments: [.text(schedules.first { $0.id == id }?.name ?? "")])
        case .followDay(let key, _):
            return renderer.format(key: "editor.dayChange.existing.followDay", arguments: [.text(labels.day(key, in: timetable))])
        case .unknown:
            return renderer.string(forKey: "editor.dayChange.existing.unknown")
        }
    }

    private func symbol(of change: OverrideChange) -> String {
        switch change {
        case .cancelLesson: return DayChangeDraft.Kind.cancelLesson.symbolName
        case .modifyLesson: return DayChangeDraft.Kind.changeLesson.symbolName
        case .addLesson: return DayChangeDraft.Kind.extraLesson.symbolName
        case .cancelDay: return DayChangeDraft.Kind.cancelDay.symbolName
        case .useBellSchedule: return DayChangeDraft.Kind.shortDay.symbolName
        case .followDay: return DayChangeDraft.Kind.followDay.symbolName
        case .unknown: return "questionmark.circle"
        }
    }
}
