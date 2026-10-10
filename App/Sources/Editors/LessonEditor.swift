// The lesson editor (`editor.lesson`, `editor.lesson-new`): subject, day / cycle day, period(s) or times, cycle weeks
// (week rotation only), validity (always / terms / date range), the optional fields the timetable shows, live overlap
// warnings (warn, never block) and delete with confirmation.
//
// Field rule: only fields enabled in `Timetable.fieldVisibility` appear; hidden fields keep their stored value
// (LessonDraft.makeLesson). Logic: Packages/TimetableUI/Sources/TimetableUI/Editors/LessonDraft.swift (Linux-tested).
// APIs: Picker(selection:content:label:), Toggle(isOn:), ForEach, Section(content:header:footer:), sheet(isPresented:),
//   onChange(of:initial:_:) (iOS 17 two-parameter closure), swipe-free explicit remove buttons.
import SwiftUI
import TimetableCore
import TimetableUI

/// What the lesson editor opens.
enum LessonEditorTarget: Equatable {
    case existing(Lesson.ID)
    case new(NewLessonContext)
}

/// Opens the lesson editor as the content of a sheet. B2 presents it with
/// `.sheet(item:) { LessonEditorView(target: .existing(id)) }` or `.new(NewLessonContext(day:slot:))` for an empty cell.
struct LessonEditorView: View {
    let target: LessonEditorTarget
    var timetableID: Timetable.ID?
    @Environment(AppModel.self) private var model
    @State private var newID = Lesson.ID(UUID())

    var body: some View {
        switch resolved() {
        case .some(let (timetable, draft)):
            LessonEditorBody(timetable: timetable, initial: draft)
        case .none:
            EditorUnavailableView(messageKey: "editor.lesson.unavailable")
        }
    }

    private func resolved() -> (Timetable, LessonDraft)? {
        guard let database = model.database else { return nil }
        switch target {
        case .existing(let id):
            guard let lesson = database.lessons.first(where: { $0.id == id && !$0.isDeleted }),
                  let timetable = model.timetables.first(where: { $0.id == lesson.timetableID }) else { return nil }
            return (timetable, LessonDraft(lesson: lesson, timetable: timetable))
        case .new(let context):
            let timetable = timetableID.flatMap { id in model.timetables.first { $0.id == id } } ?? model.activeTimetable
            guard let timetable else { return nil }
            let subject = context.subjectID.flatMap { id in database.subjects.first { $0.id == id && !$0.isDeleted } }
            let draft = LessonDraft(newIn: timetable, context: context, schedule: defaultSchedule(of: timetable, in: database),
                                    subject: subject, firstWeekday: model.calendarContext.firstWeekday, id: newID)
            return (timetable, draft)
        }
    }

    private func defaultSchedule(of timetable: Timetable, in database: TabulaDatabase) -> BellSchedule? {
        guard case .bellSchedule(let id, _) = timetable.timeStructure else { return nil }
        return database.bellSchedules.first { $0.id == id && !$0.isDeleted }
    }
}

private struct LessonEditorBody: View {
    let timetable: Timetable
    let initial: LessonDraft
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorScaffold(
            titleKey: initial.isNew ? "editor.lesson.title.new" : "editor.lesson.title.edit",
            initial: initial,
            canSave: { $0.canSave(in: timetable) },
            save: { draft in
                guard let lesson = draft.makeLesson(in: timetable) else { return nil }
                return model.apply(.upsert(lesson))
            },
            content: { draft in LessonFormContent(draft: draft, timetable: timetable) })
    }
}

private struct LessonFormContent: View {
    @Binding var draft: LessonDraft
    let timetable: Timetable
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var creatingSubject = false
    @State private var confirmingDelete = false
    @State private var deleteFailed = false

    private var database: TabulaDatabase? { model.database }
    private var labels: EditorLabels { EditorLabels(model: model) }

    private var subjects: [Subject] {
        (database?.subjects ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private var terms: [Term] {
        (database?.terms ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }
            .sorted { ($0.range.start, $0.id) < ($1.range.start, $1.id) }
    }

    private var defaultSchedule: BellSchedule? {
        guard case .bellSchedule(let id, _) = timetable.timeStructure else { return nil }
        return database?.bellSchedules.first { $0.id == id && !$0.isDeleted }
    }

    var body: some View {
        subjectSection
        daySection
        if case .weekCycle(let cycle) = timetable.rotation { weeksSection(cycle) }
        slotSection
        validitySection
        detailsSection
        conflictSection
        if !draft.isNew { deleteSection }
    }

    // MARK: Subject

    /// Picker row: emoji + name as one text (a menu-style picker shows only plain text/Label content, which is
    /// also what the selected value displays), or SF Symbol + name; just the name without a symbol.
    @ViewBuilder
    private func subjectPickerItem(_ subject: Subject) -> some View {
        switch subject.symbol {
        case .emoji(let emoji)?:
            Text(verbatim: emoji + " " + subject.name)
        case .systemImage(let name)?:
            Label { Text(verbatim: subject.name) } icon: { Image(systemName: name) }
        case nil:
            Text(verbatim: subject.name)
        }
    }

    private var subjectSection: some View {
        Section {
            Picker(selection: $draft.subjectID) {
                if draft.subjectID == nil { Text("editor.lesson.subject.choose").tag(Subject.ID?.none) }
                ForEach(subjects) { subject in
                    subjectPickerItem(subject).tag(Subject.ID?.some(subject.id))
                }
            } label: {
                Text("editor.lesson.subject")
            }
            .onChange(of: draft.subjectID) { _, newValue in
                guard draft.isNew, let newValue, let subject = subjects.first(where: { $0.id == newValue }) else { return }
                draft.applySubjectDefaults(subject, visibility: timetable.fieldVisibility)
            }
            Button {
                creatingSubject = true
            } label: {
                Label { Text("editor.lesson.subject.new") } icon: { Image(systemName: "plus.circle") }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } footer: {
            if let issue = draft.issues(in: timetable).first(where: { $0 == .noSubject }) {
                Text(LocalizedStringKey(issue.l10nKey))
            }
        }
        .sheet(isPresented: $creatingSubject) {
            SubjectEditorView(subjectID: nil, timetableID: timetable.id) { newID in draft.subjectID = newID }
        }
    }

    // MARK: Day, weeks, slot

    private var dayChoices: [DayKey] {
        let keys = DayChoices.keys(for: timetable, firstWeekday: model.calendarContext.firstWeekday)
        return keys.contains(draft.day) ? keys : keys + [draft.day]
    }

    private var daySection: some View {
        Section {
            Picker(selection: $draft.day) {
                ForEach(dayChoices, id: \.self) { key in
                    Text(verbatim: labels.day(key, in: timetable)).tag(key)
                }
            } label: {
                Text("editor.lesson.day")
            }
        }
    }

    private func weeksSection(_ cycle: WeekCycle) -> some View {
        Section {
            ForEach(1...max(1, cycle.length), id: \.self) { week in
                Toggle(isOn: Binding(
                    get: { draft.cycleWeeks.contains(week) },
                    set: { isOn in
                        if isOn { draft.cycleWeeks.insert(week) } else { draft.cycleWeeks.remove(week) }
                    })) {
                    Text(verbatim: labels.week(week, in: timetable))
                }
            }
        } header: {
            Text("editor.lesson.weeks")
        } footer: {
            Text("editor.lesson.weeks.footer")
        }
    }

    private var slotSection: some View {
        Section {
            SlotEditorRows(slot: $draft.slot, schedule: defaultSchedule, timetable: timetable)
        } header: {
            Text("editor.slot.header")
        } footer: {
            ForEach(draft.slotIssues, id: \.self) { issue in
                Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
            }
        }
    }

    // MARK: Validity

    private var validitySection: some View {
        Section {
            if draft.validityMode == .unknown {
                Label { Text("editor.validity.unknown") } icon: { Image(systemName: "questionmark.circle") }
            } else {
                Picker(selection: $draft.validityMode) {
                    Text("editor.validity.always").tag(ValidityMode.always)
                    Text("editor.validity.terms").tag(ValidityMode.terms)
                    Text("editor.validity.range").tag(ValidityMode.range)
                } label: {
                    Text("editor.validity")
                }
            }
            switch draft.validityMode {
            case .terms:
                if terms.isEmpty {
                    Text("editor.validity.terms.none").foregroundStyle(.secondary)
                }
                ForEach(terms) { term in
                    Toggle(isOn: Binding(
                        get: { draft.termIDs.contains(term.id) },
                        set: { isOn in
                            if isOn { draft.termIDs.insert(term.id) } else { draft.termIDs.remove(term.id) }
                        })) {
                        VStack(alignment: .leading) {
                            Text(verbatim: term.name)
                            Text(verbatim: model.renderer.format(key: "editor.range.dates", arguments: [
                                .text(model.formatter.date(term.range.start)), .text(model.formatter.date(term.range.end))]))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .range:
                DateRow(titleKey: "editor.validity.from", date: $draft.rangeStart)
                DateRow(titleKey: "editor.validity.to", date: $draft.rangeEnd)
            case .always, .unknown:
                EmptyView()
            }
        } header: {
            Text("editor.validity.header")
        } footer: {
            ForEach(draft.issues(in: timetable).filter { $0 != .noSubject }, id: \.self) { issue in
                Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
            }
        }
    }

    // MARK: Optional fields (field rule: only enabled fields are offered)

    @ViewBuilder
    private var detailsSection: some View {
        let shown = EditorFieldPolicy.shownFields(timetable.fieldVisibility)
        if !shown.isEmpty {
            Section {
                if shown.contains(.room) { LabeledTextField(titleKey: "editor.field.room", text: $draft.room) }
                if shown.contains(.building) { LabeledTextField(titleKey: "editor.field.building", text: $draft.building) }
                if shown.contains(.teacher) { LabeledTextField(titleKey: "editor.field.teacher", text: $draft.teacher) }
                if shown.contains(.lessonType) { lessonTypePicker }
                if shown.contains(.notes) { LabeledTextField(titleKey: "editor.field.notes", text: $draft.notes, axis: .vertical) }
            } header: {
                Text("editor.lesson.details")
            }
            if shown.contains(.bringList) { bringListSection }
        }
    }

    private var lessonTypePicker: some View {
        Picker(selection: $draft.lessonType) {
            Text("editor.lessonType.none").tag(LessonType?.none)
            ForEach(LessonType.knownValues, id: \.self) { type in
                Text(LocalizedStringKey(VisibleLessonFields.nameKey(of: type) ?? type.rawValue)).tag(LessonType?.some(type))
            }
            if let current = draft.lessonType, !current.isKnown {
                Text(verbatim: current.rawValue).tag(LessonType?.some(current))
            }
        } label: {
            Text("editor.field.lessonType")
        }
    }

    private var bringListSection: some View {
        Section {
            ForEach(Array(draft.bringList.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField(text: itemBinding(index), prompt: Text(emptyPrompt)) { Text("editor.field.bringItem") }
                    Button {
                        if draft.bringList.indices.contains(index) { draft.bringList.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("editor.field.bringItem.remove"))
                }
            }
            Button {
                draft.bringList.append("")
            } label: {
                Label { Text("editor.field.bringItem.add") } icon: { Image(systemName: "plus.circle") }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("editor.field.bringList")
        }
    }

    private func itemBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft.bringList.indices.contains(index) ? draft.bringList[index] : "" },
                set: { if draft.bringList.indices.contains(index) { draft.bringList[index] = $0 } })
    }

    // MARK: Conflicts (warn, never block)

    private var conflicts: [LessonConflictInfo] {
        guard let lesson = draft.makeLesson(in: timetable), let database else { return [] }
        return LessonConflicts.conflicts(for: lesson, in: database, context: model.calendarContext)
    }

    @ViewBuilder
    private var conflictSection: some View {
        let found = conflicts
        if !found.isEmpty {
            Section {
                ForEach(Array(found.enumerated()), id: \.offset) { _, conflict in
                    Label {
                        Text(verbatim: conflictText(conflict))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("editor.lesson.conflicts")
            } footer: {
                Text("editor.lesson.conflicts.footer")
            }
        }
    }

    private func conflictText(_ conflict: LessonConflictInfo) -> String {
        var when = labels.day(conflict.dayKey, in: timetable)
        if let week = conflict.cycleWeek {
            when = model.renderer.format(key: "editor.lesson.conflict.dayWeek",
                                         arguments: [.text(when), .text(labels.week(week, in: timetable))])
        }
        let others = model.formatter.list(Array(Set(conflict.otherSubjectNames)).sorted())
        if others.isEmpty {
            return model.renderer.format(key: "editor.lesson.conflict.generic", arguments: [.text(when)])
        }
        return model.renderer.format(key: "editor.lesson.conflict.overlap", arguments: [.text(others), .text(when)])
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("editor.lesson.delete").frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            if deleteFailed { Text("editor.error.failed").foregroundStyle(.red) }
        }
        .sheet(isPresented: $confirmingDelete) {
            let changes = database.map { TimetableManagement.lessonChangeCount(draft.lessonID, in: $0) } ?? 0
            ImpactConfirmation(
                title: "editor.lesson.delete.title", subjectName: subjectName,
                rows: [ImpactRow(id: "changes", key: "editor.impact.dayChanges", count: changes)],
                note: "editor.lesson.delete.note", action: "editor.lesson.delete") {
                    guard let database else { return }
                    if case .applied = model.apply(TimetableManagement.deleteLessonMutation(draft.lessonID, in: database)) {
                        dismiss()
                    } else {
                        deleteFailed = true
                    }
                }
        }
    }

    private var subjectName: String {
        subjects.first { $0.id == draft.subjectID }?.name ?? ""
    }
}
