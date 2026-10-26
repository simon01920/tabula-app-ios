// The lesson editor (`editor.lesson`, `editor.lesson-new`): subject, day / cycle day, period(s) or times, weeks
// (week rotation only), validity (always / terms / date range), every optional field under "More details", live
// overlap warnings (warn, never block) and delete with confirmation.
//
// UX overhaul U5b:
// - H8/D9: weeks are "Every week | Week A | Week B" (segmented, two-week cycles) or a checklist with "Every week"
//   first (longer cycles), mapped onto the unchanged model by `CycleWeekSelection` (no explanatory footer).
// - F06/D10: every optional field is offered under "More details" whatever `Timetable.fieldVisibility` says (that
//   setting only affects summaries); the group starts expanded when a field holds a value.
// - M1: no section header repeating its row label ("Applies"). M5: red errors only after the first edit.
// Logic: Packages/TimetableUI/Sources/TimetableUI/Editors/LessonDraft.swift, CycleWeekSelection.swift (Linux-tested).
// APIs: Picker(selection:content:label:) with .segmented / .inline, DisclosureGroup(isExpanded:content:label:),
//   Section(content:header:footer:), sheet(isPresented:), onChange(of:initial:_:) (iOS 17 two-parameter closure).
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
            return (timetable, LessonDraft(lesson: lesson, timetable: timetable, today: model.today))
        case .new(let context):
            let timetable = timetableID.flatMap { id in model.timetables.first { $0.id == id } } ?? model.activeTimetable
            guard let timetable else { return nil }
            let subject = context.subjectID.flatMap { id in database.subjects.first { $0.id == id && !$0.isDeleted } }
            let draft = LessonDraft(newIn: timetable, context: context, schedule: defaultSchedule(of: timetable, in: database),
                                    subject: subject, firstWeekday: model.calendarContext.firstWeekday, id: newID,
                                    today: model.today)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var creatingSubject = false
    @State private var confirmingDelete = false
    @State private var deleteFailed = false
    /// Set by the first edit: red errors wait for it (M5); the disabled Save says enough before that.
    @State private var touched = false
    /// `nil` until the user opens or closes "More details" (then it starts from `draft.hasOptionalDetails`).
    @State private var detailsExpanded: Bool?

    private var database: TabulaDatabase? { model.database }
    private var labels: EditorLabels { EditorLabels(model: model) }

    /// The timetable's subjects in display order (manual order, then name; `SubjectOrder`).
    private var subjects: [Subject] {
        database.map { SubjectOrder.live($0, timetableID: timetable.id, locale: model.formatter.locale) } ?? []
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
        moreDetailsSection
        if isDetailsExpanded { bringListSection }
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
            Text(verbatim: model.renderer.format(key: "editor.subject.emojiName", arguments: [.text(emoji), .text(subject.name)]))
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
                draft.applySubjectDefaults(subject)
            }
            .onChange(of: draft) { _, _ in touched = true }
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

    /// "Week A" / "Odd" / "Week 2" as one full phrase (D11: no "Week " + label concatenation).
    private func weekName(_ week: Int, in cycle: WeekCycle) -> String {
        EditorWeekNames.name(week, in: timetable, renderer: model.renderer)
    }

    @ViewBuilder
    private func weeksSection(_ cycle: WeekCycle) -> some View {
        switch CycleWeekSelection.style(length: cycle.length) {
        case .segmented?:
            Section {
                weekSegments(cycle)
            } header: {
                Text("editor.lesson.weeks")
            }
        case .list?:
            Section {
                weekRow(Text("editor.lesson.weeks.every"),
                        checked: CycleWeekSelection.isEveryWeek(draft.cycleWeeks, length: cycle.length)) {
                    draft.cycleWeeks = CycleWeekSelection.selectingEveryWeek()
                }
                ForEach(1...cycle.length, id: \.self) { week in
                    weekRow(Text(verbatim: weekName(week, in: cycle)),
                            checked: CycleWeekSelection.isChecked(week, in: draft.cycleWeeks, length: cycle.length)) {
                        draft.cycleWeeks = CycleWeekSelection.toggling(week, in: draft.cycleWeeks, length: cycle.length)
                    }
                }
            } header: {
                Text("editor.lesson.weeks")
            }
        case nil:
            EmptyView()
        }
    }

    /// Two-week cycle: one segmented choice (an inline list at accessibility sizes, where segments would truncate).
    @ViewBuilder
    private func weekSegments(_ cycle: WeekCycle) -> some View {
        let selection = Binding(
            get: { CycleWeekSelection.segment(of: draft.cycleWeeks, length: cycle.length) },
            set: { draft.cycleWeeks = CycleWeekSelection.weeks(for: $0) })
        let picker = Picker(selection: selection) {
            ForEach(CycleWeekSelection.segments(length: cycle.length), id: \.self) { segment in
                switch segment {
                case .everyWeek: Text("editor.lesson.weeks.every.segment").tag(segment)
                case .week(let week): Text(verbatim: weekName(week, in: cycle)).tag(segment)
                }
            }
        } label: {
            Text("editor.lesson.weeks")
        }
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.inline).labelsHidden()
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    /// A checklist row (multi-select): the whole row is the target, the checkmark shows the state.
    private func weekRow(_ title: Text, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title.foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(checked ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    private var slotSection: some View {
        Section {
            SlotEditorRows(slot: $draft.slot, schedule: defaultSchedule, timetable: timetable)
        } header: {
            Text("editor.slot.header")
        } footer: {
            if touched {
                ForEach(draft.slotIssues, id: \.self) { issue in
                    Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
                }
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
        } footer: {
            if touched {
                ForEach(draft.issues(in: timetable).filter { $0 != .noSubject }, id: \.self) { issue in
                    Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: Optional fields (D10: all of them, under "More details")

    private var isDetailsExpanded: Bool { detailsExpanded ?? draft.hasOptionalDetails }

    private var moreDetailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(get: { isDetailsExpanded }, set: { detailsExpanded = $0 })) {
                LabeledTextField(titleKey: "editor.field.room", text: $draft.room)
                LabeledTextField(titleKey: "editor.field.building", text: $draft.building)
                LabeledTextField(titleKey: "editor.field.teacher", text: $draft.teacher)
                lessonTypePicker
                LabeledTextField(titleKey: "editor.field.notes", text: $draft.notes, axis: .vertical)
            } label: {
                Text("editor.lesson.moreDetails").frame(minHeight: 44, alignment: .leading)
            }
        } footer: {
            if !isDetailsExpanded { Text("editor.lesson.moreDetails.footer") }
        }
    }

    /// Known types show their translated name; an unknown one shows its raw text, never a catalog key.
    @ViewBuilder
    private func lessonTypeName(_ type: LessonType) -> some View {
        if let key = VisibleLessonFields.nameKey(of: type) {
            Text(LocalizedStringKey(key))
        } else {
            Text(verbatim: type.rawValue)
        }
    }

    private var lessonTypePicker: some View {
        Picker(selection: $draft.lessonType) {
            Text("editor.lessonType.none").tag(LessonType?.none)
            ForEach(LessonType.knownValues, id: \.self) { type in
                lessonTypeName(type).tag(LessonType?.some(type))
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
                                         arguments: [.text(when), .text(EditorWeekNames.name(week, in: timetable,
                                                                                             renderer: model.renderer))])
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
