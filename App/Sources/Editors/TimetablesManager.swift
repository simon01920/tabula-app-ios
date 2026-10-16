// The timetables manager (`editor.timetables`): add, duplicate, reorder, set active, edit, reset and delete timetables.
//
// Data-loss guard (Stage A QA finding): when no live timetable exists the shell routes to onboarding, so the LAST
// remaining timetable can never be deleted here (the action is disabled with an explanation; "Reset timetable" clears
// its lessons instead, with confirmation). Deleting another timetable states exactly what is removed and, when it was
// the active one, makes another active in the same atomic batch. All planning is in TimetableManagement (Linux-tested).
// Changes apply immediately (this is a manager, not a Save/Cancel form).
// APIs: List, Menu, EditButton, onMove(perform:), sheet(item:), ContentUnavailableView.
import SwiftUI
import TimetableCore
import TimetableUI

private struct TimetableTarget: Identifiable, Equatable {
    let id: Timetable.ID
}

/// What a new timetable starts from.
private enum NewStructureChoice: String, CaseIterable, Equatable {
    case template, copyActive, freeForm
}

private struct NewTimetableDraft: Equatable {
    var name = ""
    var emoji = ""
    var structure: NewStructureChoice = .template
}

struct TimetablesManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TimetableTarget?
    @State private var deleting: TimetableTarget?
    @State private var resetting: TimetableTarget?
    @State private var adding = false
    @State private var failure: ApplyResult?

    private var database: TabulaDatabase? { model.database }
    private var timetables: [Timetable] { model.timetables }
    private var activeID: Timetable.ID? { model.activeTimetable?.id }
    private var limit: Int? { model.entitlements.limit(.maxTimetables) }
    private var canAdd: Bool { database.map { TimetableManagement.canAdd(to: $0, limit: limit) } ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if timetables.isEmpty {
                    ContentUnavailableView {
                        Label { Text("editor.timetables.empty.title") } icon: { Image(systemName: "calendar") }
                    } description: {
                        Text("editor.timetables.empty.message")
                    }
                } else {
                    list
                }
            }
            .navigationTitle(Text("editor.timetables.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("editor.common.done") }
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: {
                        Label { Text("editor.timetables.add") } icon: { Image(systemName: "plus") }
                    }
                    .disabled(!canAdd || database == nil)
                }
            }
        }
        .sheet(item: $editing) { target in TimetableEditorView(timetableID: target.id) }
        .sheet(isPresented: $adding) { NewTimetableSheet() }
        .sheet(item: $deleting) { target in deleteConfirmation(target.id) }
        .sheet(item: $resetting) { target in resetConfirmation(target.id) }
    }

    // MARK: List

    private var list: some View {
        List {
            if let failure { ApplyResultSection(result: failure) }
            Section {
                ForEach(timetables) { timetable in row(timetable) }
                    .onMove(perform: move)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if timetables.count <= 1 { Text("editor.timetables.last.footer") }
                    if !canAdd, let limit {
                        Text(verbatim: model.renderer.format(key: "editor.timetables.limit", arguments: [.integer(Int64(limit))]))
                    }
                    Text("editor.timetables.footer")
                }
            }
        }
    }

    private func row(_ timetable: Timetable) -> some View {
        let isActive = timetable.id == activeID
        let lessons = (database?.lessons ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }.count
        return HStack(spacing: 12) {
            Button {
                editing = TimetableTarget(id: timetable.id)
            } label: {
                HStack(spacing: 12) {
                    if let emoji = timetable.emoji { Text(verbatim: emoji).font(.title2) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: timetable.name).font(.body).foregroundStyle(.primary)
                        Text(verbatim: model.renderer.format(key: "editor.impact.lessons.count", arguments: [.integer(Int64(lessons))]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if isActive {
                            Label { Text("editor.timetables.active") } icon: { Image(systemName: "checkmark.circle.fill") }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button { editing = TimetableTarget(id: timetable.id) } label: {
                    Label { Text("editor.timetables.edit") } icon: { Image(systemName: "pencil") }
                }
                if !isActive {
                    Button { setActive(timetable) } label: {
                        Label { Text("editor.timetables.setActive") } icon: { Image(systemName: "checkmark.circle") }
                    }
                }
                Button { duplicate(timetable) } label: {
                    Label { Text("editor.timetables.duplicate") } icon: { Image(systemName: "plus.square.on.square") }
                }
                .disabled(!canAdd)
                Button(role: .destructive) { resetting = TimetableTarget(id: timetable.id) } label: {
                    Label { Text("editor.timetables.reset") } icon: { Image(systemName: "arrow.counterclockwise") }
                }
                Button(role: .destructive) { deleting = TimetableTarget(id: timetable.id) } label: {
                    Label { Text("editor.timetables.delete") } icon: { Image(systemName: "trash") }
                }
                .disabled(isLast(timetable))
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("editor.timetables.actions"))
        }
        .accessibilityElement(children: .contain)
    }

    private func isLast(_ timetable: Timetable) -> Bool {
        database.map { TimetableManagement.deletionGuard(timetable.id, in: $0) != .allowed } ?? true
    }

    // MARK: Actions

    private func run(_ mutation: DatabaseMutation) {
        let result = model.apply(mutation)
        if case .applied = result { failure = nil } else { failure = result }
    }

    private func setActive(_ timetable: Timetable) {
        run(TimetableManagement.setActiveMutation(timetable.id))
    }

    private func duplicate(_ timetable: Timetable) {
        guard let database else { return }
        var ids = SystemIDGenerator()
        let name = model.renderer.format(key: "editor.timetables.copyName", arguments: [.text(timetable.name)])
        guard let plan = TimetableManagement.duplicateMutation(timetable.id, name: name, in: database, ids: &ids) else { return }
        run(plan.mutation)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let database else { return }
        var order = timetables.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        // A row dropped where it was changes nothing: no apply (no save, no change notification).
        guard !TimetableManagement.reorderIsNoOp(order, in: database) else { return }
        run(TimetableManagement.reorderMutation(order, in: database))
    }

    // MARK: Confirmations

    @ViewBuilder
    private func deleteConfirmation(_ id: Timetable.ID) -> some View {
        if let database, let timetable = timetables.first(where: { $0.id == id }),
           TimetableManagement.deletionGuard(id, in: database) == .allowed {
            let impact = TimetableManagement.impact(of: id, in: database)
            ImpactConfirmation(
                title: "editor.timetables.delete.title", subjectName: timetable.name,
                rows: [ImpactRow(id: "lessons", key: "editor.impact.lessons", count: impact.lessons),
                       ImpactRow(id: "subjects", key: "editor.impact.subjects", count: impact.subjects),
                       ImpactRow(id: "bells", key: "editor.impact.bellSchedules", count: impact.bellSchedules),
                       ImpactRow(id: "terms", key: "editor.impact.terms", count: impact.terms),
                       ImpactRow(id: "breaks", key: "editor.impact.breaks", count: impact.breaks),
                       ImpactRow(id: "changes", key: "editor.impact.dayChanges", count: impact.overrides),
                       ImpactRow(id: "tasks", key: "editor.impact.linkedTasks", count: impact.linkedTasks),
                       ImpactRow(id: "exams", key: "editor.impact.linkedExams", count: impact.linkedExams)],
                note: "editor.timetables.delete.note", action: "editor.timetables.delete") {
                    if let mutation = TimetableManagement.deleteMutation(id, in: database) { run(mutation) }
                }
        } else {
            // The guard refused (last timetable) or the timetable vanished: nothing destructive is offered.
            EditorUnavailableView(messageKey: "editor.timetables.last.footer")
        }
    }

    @ViewBuilder
    private func resetConfirmation(_ id: Timetable.ID) -> some View {
        if let database, let timetable = timetables.first(where: { $0.id == id }) {
            let impact = TimetableManagement.resetImpact(of: id, in: database)
            ImpactConfirmation(
                title: "editor.timetables.reset.title", subjectName: timetable.name,
                rows: [ImpactRow(id: "lessons", key: "editor.impact.lessons", count: impact.lessons),
                       ImpactRow(id: "changes", key: "editor.impact.dayChanges", count: impact.changes)],
                note: "editor.timetables.reset.note", action: "editor.timetables.reset") {
                    run(TimetableManagement.resetMutation(id, in: database))
                }
        }
    }
}

/// "New timetable": name, emoji and what its time structure starts from. The new timetable becomes the active one.
private struct NewTimetableSheet: View {
    @Environment(AppModel.self) private var model

    private var activeUsesBellSchedule: Bool {
        guard let active = model.activeTimetable else { return false }
        if case .bellSchedule = active.timeStructure { return true }
        return false
    }

    var body: some View {
        EditorScaffold(
            titleKey: "editor.timetables.new.title",
            initial: NewTimetableDraft(),
            canSave: { EditorText.trimmedOrNil($0.name) != nil },
            save: { draft in
                guard let database = model.database, let name = EditorText.trimmedOrNil(draft.name) else { return nil }
                var ids = SystemIDGenerator()
                let scheduleName = model.renderer.string(forKey: "editor.bell.defaultName")
                let structure: NewTimetableStructure
                switch draft.structure {
                case .template: structure = .template(.secondary, scheduleName: scheduleName)
                case .copyActive:
                    if let active = model.activeTimetable {
                        structure = NewTimetableStructure.copyBellSchedule(of: active.id, scheduleName: scheduleName)
                    } else {
                        structure = NewTimetableStructure.template(.secondary, scheduleName: scheduleName)
                    }
                case .freeForm: structure = .freeForm(minutes: 45)
                }
                let plan = TimetableManagement.addMutation(
                    name: name, emoji: EditorText.firstCharacter(draft.emoji), structure: structure,
                    like: model.activeTimetable, in: database, ids: &ids)
                return model.apply(.batch([plan.mutation, TimetableManagement.setActiveMutation(plan.timetableID)],
                                          label: "add timetable"))
            },
            content: { draft in
                Section {
                    LabeledTextField(titleKey: "editor.timetable.name", text: draft.name)
                    LabeledTextField(titleKey: "editor.timetable.emoji", text: draft.emoji)
                }
                Section {
                    Picker(selection: draft.structure) {
                        Text("editor.timetables.new.template").tag(NewStructureChoice.template)
                        if activeUsesBellSchedule {
                            Text("editor.timetables.new.copy").tag(NewStructureChoice.copyActive)
                        }
                        Text("editor.timetables.new.free").tag(NewStructureChoice.freeForm)
                    } label: {
                        Text("editor.time")
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("editor.time.header")
                } footer: {
                    Text("editor.timetables.new.footer")
                }
            })
    }
}
