// "Change for this day" (`editor.day-change`): creates one `ScheduleOverride` for one date: cancel a lesson, change a
// lesson (substitute subject or teacher, room, building, a note, or move it to another time that day), no school,
// shortened lessons through another bell schedule, "use another day's timetable", or an extra lesson. Changes that
// already exist on the date are listed and can be undone.
//
// UX overhaul U5b: the date is shown once (M20); "Use another day's timetable" / "Shortened lessons" (M20); hints and
// errors follow U1's `ValidationMessage` rule (M5, the disabled Save explains the rest); the kind picker has no repeated label (M1);
// D10: every optional field is offered whatever the display setting; M15: "Change a lesson" can move the lesson
// (`LessonPatch.slot`), matching the lesson detail's "Cancel, Move or Substitute…".
// Logic: Packages/TimetableUI/.../Editors/DayChangeDraft.swift (Linux-tested).
// APIs: Picker (.inline, labelsHidden), Toggle, Section, Label, ScheduleResolver.resolution(for:) (core), DateRow.
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
                canSave: { $0.canSave },
                save: { draft in
                    guard let override = draft.makeOverride() else { return nil }
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

    /// The regular slot of the chosen lesson (where a move starts).
    private var selectedLessonSlot: LessonSlot? {
        draft.lessonID.flatMap { id in database?.lessons.first { $0.id == id }?.slot }
    }

    var body: some View {
        dateSection
        kindSection
        detailSection
        existingSection
    }

    // MARK: Date and kind

    /// The date once (M20): the picker row only, no repeated full date underneath.
    private var dateSection: some View {
        Section {
            DateRow(titleKey: "editor.dayChange.date", date: $draft.date)
                .onChange(of: draft.date) { _, _ in
                    if let current = draft.lessonID, !entries.contains(where: { $0.lessonID == current }) {
                        draft.selectLesson(entries.first?.lessonID)
                    }
                }
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
            .labelledBySectionHeader()   // M1: the header already says "What changes"
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
            changeLessonSections
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
                            Text(verbatim: EditorWeekNames.name(week, in: timetable, renderer: model.renderer))
                                .tag(Int?.some(week))
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
                LabeledTextField(titleKey: "editor.field.room", text: $draft.extraRoom)
                LabeledTextField(titleKey: "editor.field.building", text: $draft.extraBuilding)
                LabeledTextField(titleKey: "editor.field.teacher", text: $draft.extraTeacher)
                LabeledTextField(titleKey: "editor.field.notes", text: $draft.extraNotes, axis: .vertical)
            } footer: {
                issueFooter
            }
            Section {
                SlotEditorRows(slot: $draft.extraSlot, schedule: defaultSchedule, timetable: timetable)
            } header: {
                Text("editor.slot.header")
            } footer: {
                slotIssueFooter
            }
        }
    }

    /// "Change a lesson": which lesson, then substitute / room / building / teacher / note, then an optional move.
    @ViewBuilder
    private var changeLessonSections: some View {
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
            LabeledTextField(titleKey: "editor.field.room", text: $draft.room)
            LabeledTextField(titleKey: "editor.field.building", text: $draft.building)
            LabeledTextField(titleKey: "editor.field.teacher", text: $draft.teacher)
            LabeledTextField(titleKey: "editor.field.notes", text: $draft.lessonNote, axis: .vertical)
        } header: {
            Text("editor.dayChange.changes")
        } footer: {
            Text("editor.dayChange.changes.footer")
        }
        Section {
            Toggle(isOn: Binding(get: { draft.moves }, set: { draft.setMoves($0, lessonSlot: selectedLessonSlot) })) {
                Text("editor.dayChange.move")
            }
            if draft.moves {
                SlotEditorRows(slot: $draft.movedSlot, schedule: defaultSchedule, timetable: timetable)
            }
        } footer: {
            slotIssueFooter
        }
    }

    private var lessonPicker: some View {
        Picker(selection: Binding(get: { draft.lessonID }, set: { draft.selectLesson($0) })) {
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

    /// What blocks saving: missing choices are hints from the start, errors wait for the first edit (M5, U1).
    private var issueFooter: some View {
        ForEach(draft.issues, id: \.self) { issue in
            ValidationMessage(key: issue.l10nKey, severity: issue.severity)
        }
    }

    private var slotIssueFooter: some View {
        ForEach(draft.slotIssues, id: \.self) { issue in
            ValidationMessage(key: issue.l10nKey)
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
                        Spacer(minLength: 8)
                        // A labelled button (no icon-only arrow that needed a footer to explain it, M5). It applies at
                        // once, like the undo it is; the draft of this sheet is not affected.
                        Button {
                            model.apply(.delete(item.id))
                        } label: {
                            Text("editor.dayChange.existing.remove").frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                    .accessibilityElement(children: .contain)
                }
            } header: {
                Text("editor.dayChange.existing")
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
