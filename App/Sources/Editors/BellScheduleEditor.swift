// The bell schedule editor (`editor.bell`): the periods of the default schedule (label, start, end, kind), add / remove /
// reorder, per-weekday variants ("copy from" the default) and overlap validation.
//
// Rules shown to the user: a period used by a lesson cannot be removed; an end time at or before the start blocks
// saving; overlapping periods only warn. Logic: Packages/TimetableUI/.../Editors/BellSetDraft.swift (Linux-tested).
// APIs: List/Form with onMove (EditMode via EditButton), Menu, Toggle, Picker, DatePicker through TimeRow.
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the bell schedule editor as sheet content for `timetableID` (default: the active timetable).
struct BellScheduleEditorView: View {
    var timetableID: Timetable.ID?
    @Environment(AppModel.self) private var model
    @State private var defaultID = BellSchedule.ID(UUID())

    var body: some View {
        if let database = model.database,
           let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            BellEditorBody(timetable: timetable, database: database, fallbackID: defaultID)
        } else {
            EditorUnavailableView(messageKey: "editor.bell.unavailable")
        }
    }
}

private struct BellEditorBody: View {
    let timetable: Timetable
    let database: TabulaDatabase
    let fallbackID: BellSchedule.ID
    @Environment(AppModel.self) private var model

    private var initial: BellSetDraft {
        BellSetDraft(timetable: timetable, schedules: database.bellSchedules,
                     defaultScheduleName: model.renderer.string(forKey: "editor.bell.defaultName"), ids: { fallbackID })
    }

    var body: some View {
        EditorScaffold(
            titleKey: "editor.bell.title",
            initial: initial,
            canSave: { !$0.hasBlockingIssues && !$0.defaultHasNoLessons },
            save: { draft in model.apply(.batch(draft.mutations(for: timetable), label: "bell schedule")) },
            content: { draft in BellFormContent(draft: draft, timetable: timetable, lessons: database.lessons) })
    }
}

private struct BellFormContent: View {
    @Binding var draft: BellSetDraft
    let timetable: Timetable
    let lessons: [Lesson]
    @Environment(AppModel.self) private var model

    private var locked: Set<Period.ID> {
        BellSetDraft.lockedPeriods(lessons: lessons, timetableID: timetable.id)
    }

    var body: some View {
        Group {
            scheduleSections(for: draft.defaultEntry.id, isDefault: true)
            ForEach(draft.variants) { variant in
                scheduleSections(for: variant.id, isDefault: false)
            }
            variantsSection
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
    }

    // MARK: One schedule

    private func entry(_ id: BellSchedule.ID) -> BellSetDraft.Entry? { draft.entries.first { $0.id == id } }

    @ViewBuilder
    private func scheduleSections(for id: BellSchedule.ID, isDefault: Bool) -> some View {
        if let entry = entry(id) {
            let issues = BellSetDraft.issues(of: entry)
            Section {
                nameField(id)
                if !isDefault { weekdayToggles(id) }
            } header: {
                Text(isDefault ? "editor.bell.default" : "editor.bell.variant")
            } footer: {
                if isDefault && draft.defaultHasNoLessons { Text("editor.bell.issue.noLessons").foregroundStyle(.red) }
            }
            Section {
                ForEach(Array(entry.periods.enumerated()), id: \.element.id) { index, period in
                    PeriodRow(period: periodBinding(period.id, in: id), issue: issues[period.id],
                              isLocked: locked.contains(period.id)) {
                        draft.removePeriod(period.id, from: id, locked: locked)
                    }
                }
                .onMove { source, destination in
                    movePeriods(in: id, from: source, to: destination)
                }
                Button {
                    draft.addPeriod(to: id, id: Period.ID(UUID()))
                } label: {
                    Label { Text("editor.bell.addPeriod") } icon: { Image(systemName: "plus.circle") }
                        .frame(minHeight: 44, alignment: .leading)
                }
                Button {
                    draft.sortByTime(id)
                } label: {
                    Label { Text("editor.bell.sort") } icon: { Image(systemName: "arrow.up.arrow.down") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            } header: {
                Text("editor.bell.periods")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if issues.values.contains(.endBeforeStart) {
                        Text("editor.bell.issue.endBeforeStart").foregroundStyle(.red)
                    }
                    if issues.values.contains(.overlaps) {
                        Label { Text("editor.bell.issue.overlap") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .foregroundStyle(.orange)
                    }
                    if entry.periods.contains(where: { locked.contains($0.id) }) { Text("editor.bell.locked.footer") }
                }
            }
        }
    }

    private func nameField(_ id: BellSchedule.ID) -> some View {
        LabeledTextField(titleKey: "editor.bell.name", text: Binding(
            get: { entry(id)?.name ?? "" },
            set: { newValue in updateName(id, newValue) }))
    }

    private func updateName(_ id: BellSchedule.ID, _ name: String) {
        if draft.defaultEntry.id == id {
            draft.defaultEntry.name = name
        } else if let index = draft.variants.firstIndex(where: { $0.id == id }) {
            draft.variants[index].name = name
        }
    }

    private func periodBinding(_ periodID: Period.ID, in entryID: BellSchedule.ID) -> Binding<Period> {
        Binding(
            get: {
                entry(entryID)?.periods.first { $0.id == periodID }
                    ?? Period(id: periodID, start: SlotDraft.defaultStart, end: SlotDraft.defaultEnd)
            },
            set: { draft.setPeriod($0, in: entryID) })
    }

    private func movePeriods(in id: BellSchedule.ID, from source: IndexSet, to destination: Int) {
        guard var periods = entry(id)?.periods else { return }
        periods.move(fromOffsets: source, toOffset: destination)
        if draft.defaultEntry.id == id {
            draft.defaultEntry.periods = periods
        } else if let index = draft.variants.firstIndex(where: { $0.id == id }) {
            draft.variants[index].periods = periods
        }
    }

    private func weekdayToggles(_ id: BellSchedule.ID) -> some View {
        ForEach(Weekday.week(startingAt: model.calendarContext.firstWeekday).filter { timetable.enabledDays.contains($0) }, id: \.self) { day in
            Toggle(isOn: Binding(
                get: { entry(id)?.weekdays.contains(day) ?? false },
                set: { isOn in
                    var days = entry(id)?.weekdays ?? []
                    if isOn { days.insert(day) } else { days.remove(day) }
                    draft.assign(days, to: id)
                })) {
                Text(verbatim: model.formatter.weekdayName(day))
            }
        }
    }

    // MARK: Variants

    private var variantsSection: some View {
        Section {
            let free = draft.freeWeekdays(enabledDays: timetable.enabledDays)
            if free.isEmpty {
                Text("editor.bell.variants.allUsed").foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(free, id: \.self) { day in
                        Button {
                            let name = model.renderer.format(key: "editor.bell.variantName",
                                                             arguments: [.text(model.formatter.weekdayName(day))])
                            draft.addVariant(copying: draft.defaultEntry.id, weekdays: [day], name: name,
                                             id: BellSchedule.ID(UUID()))
                        } label: {
                            Text(verbatim: model.formatter.weekdayName(day))
                        }
                    }
                } label: {
                    Label { Text("editor.bell.addVariant") } icon: { Image(systemName: "plus.circle") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            ForEach(draft.variants) { variant in
                Button(role: .destructive) {
                    draft.removeVariant(variant.id)
                } label: {
                    Label {
                        Text(verbatim: model.renderer.format(key: "editor.bell.removeVariant", arguments: [.text(variant.name)]))
                    } icon: { Image(systemName: "trash") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        } header: {
            Text("editor.bell.variants")
        } footer: {
            Text("editor.bell.variants.footer")
        }
    }
}

/// One period: label, kind, start and end. Layout stacks vertically so it stays usable at AX5.
private struct PeriodRow: View {
    @Binding var period: Period
    let issue: BellSetDraft.PeriodIssue?
    let isLocked: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LabeledTextField(titleKey: "editor.bell.periodLabel", text: Binding(
                    get: { period.label ?? "" },
                    set: { period.label = EditorText.trimmedOrNil($0) == nil ? nil : $0 }))
                if !isLocked {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("editor.bell.removePeriod"))
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(Text("editor.bell.periodInUse"))
                }
            }
            Picker(selection: $period.kind) {
                ForEach(PeriodKind.knownValues, id: \.self) { kind in
                    Text(LocalizedStringKey(DynamicL10nKeys.periodKind(kind))).tag(kind)
                }
                if !period.kind.isKnown { Text(verbatim: period.kind.rawValue).tag(period.kind) }
            } label: {
                Text("editor.bell.kind")
            }
            TimeRow(titleKey: "editor.slot.start", time: startBinding)
            TimeRow(titleKey: "editor.slot.end", time: $period.end)
            if let issue {
                switch issue {
                case .endBeforeStart:
                    Label { Text("editor.bell.issue.endBeforeStart") } icon: { Image(systemName: "xmark.octagon.fill") }
                        .foregroundStyle(.red).font(.footnote)
                case .overlaps:
                    Label { Text("editor.bell.issue.overlap.row") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(.orange).font(.footnote)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var startBinding: Binding<LocalTime> {
        Binding(get: { period.start }, set: { period.start = $0 })
    }
}
