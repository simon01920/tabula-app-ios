// The terms & holidays editor (`editor.terms`): terms (semesters) and holidays (`CalendarBreak`: holiday / vacation /
// exam period / no school) of one timetable, add / edit / delete. A term that lessons are limited to cannot be deleted.
//
// UX overhaul U5b (M19, D11): the UI says "Holidays" (days off) so "break" only means the gap between lessons; the
// model keeps its names (`CalendarBreak`, `breaks`). Deleting is a swipe (or the VoiceOver "Delete" action from
// `onDelete`) instead of a permanent red ⊖ inside the name row; a term in use says so in its row ("Used by lessons")
// instead of an unexplained lock, and cannot be swiped away (`deleteDisabled`).
// Logic: Packages/TimetableUI/.../Editors/TermsDraft.swift (Linux-tested).
// HIG: lists-and-tables.md › "Let people edit a table when it makes sense"; entering-data.md › validation.
// APIs: Form, Section, ForEach.onDelete(perform:), deleteDisabled(_:), Picker, DatePicker through DateRow.
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the terms & holidays editor for `timetableID` (default: the active timetable): as sheet content, or
/// `embedded` in a parent navigation stack (Settings; no own stack, Back leaves while nothing is edited).
struct TermsEditorView: View {
    var timetableID: Timetable.ID?
    var embedded = false
    @Environment(AppModel.self) private var model

    var body: some View {
        if let database = model.database,
           let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            EmbeddableEditorScaffold(
                embedded: embedded,
                titleKey: "editor.terms.title",
                initial: TermsDraft(timetableID: timetable.id, database: database),
                canSave: { $0.canSave },
                save: { draft in model.apply(.batch(draft.mutations(), label: "terms and breaks")) },
                content: { draft in
                    TermsFormContent(draft: draft, locked: TermsDraft.lockedTerms(lessons: database.lessons, timetableID: timetable.id))
                })
        } else {
            EmbeddableUnavailableView(embedded: embedded, messageKey: "editor.terms.unavailable")
        }
    }
}

private struct TermsFormContent: View {
    @Binding var draft: TermsDraft
    let locked: Set<Term.ID>
    @Environment(AppModel.self) private var model

    var body: some View {
        termsSection
        holidaysSection
    }

    private func termBinding(_ id: Term.ID) -> Binding<Term> {
        Binding(
            get: { draft.terms.first { $0.id == id } ?? placeholderTerm(id) },
            set: { newValue in
                if let index = draft.terms.firstIndex(where: { $0.id == id }) { draft.terms[index] = newValue }
            })
    }

    private func holidayBinding(_ id: CalendarBreak.ID) -> Binding<CalendarBreak> {
        Binding(
            get: { draft.breaks.first { $0.id == id } ?? placeholderHoliday(id) },
            set: { newValue in
                if let index = draft.breaks.firstIndex(where: { $0.id == id }) { draft.breaks[index] = newValue }
            })
    }

    private func placeholderTerm(_ id: Term.ID) -> Term {
        Term(id: id, meta: EditorEntities.placeholderMeta, timetableID: draft.timetableID, name: "",
             range: LocalDateRange(day: model.today))
    }

    private func placeholderHoliday(_ id: CalendarBreak.ID) -> CalendarBreak {
        CalendarBreak(id: id, meta: EditorEntities.placeholderMeta, timetableID: draft.timetableID, name: "",
                      range: LocalDateRange(day: model.today))
    }

    // MARK: Terms

    private var termsSection: some View {
        Section {
            ForEach(draft.terms) { term in
                let binding = termBinding(term.id)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledTextField(titleKey: "editor.terms.name", text: binding.name)
                    DateRow(titleKey: "editor.terms.start", date: binding.range.start)
                    DateRow(titleKey: "editor.terms.end", date: binding.range.end)
                    if binding.wrappedValue.range.isEmpty {
                        ValidationMessage(key: "editor.terms.issue.range")
                    }
                    if locked.contains(term.id) {
                        // Informational, not a control: why this row has no Delete.
                        Label { Text("editor.terms.inUse") } icon: { Image(systemName: "info.circle") }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .deleteDisabled(locked.contains(term.id))
            }
            .onDelete { offsets in
                let ids = offsets.map { draft.terms[$0].id }.filter { !locked.contains($0) }
                draft.terms.removeAll { ids.contains($0.id) }
            }
            Button {
                let start = draft.terms.map(\.range.end).max().map { $0.adding(days: 1) } ?? model.today
                draft.addTerm(name: model.renderer.string(forKey: "editor.terms.defaultName"), start: start, id: Term.ID(UUID()))
            } label: {
                Label { Text("editor.terms.add") } icon: { Image(systemName: "plus.circle") }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("editor.terms.header")
        } footer: {
            if draft.terms.isEmpty { Text("editor.terms.empty.footer") }
        }
    }

    // MARK: Holidays (CalendarBreak in the model)

    private var holidaysSection: some View {
        Section {
            ForEach(draft.breaks) { item in
                let binding = holidayBinding(item.id)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledTextField(titleKey: "editor.breaks.name", text: binding.name)
                    Picker(selection: binding.kind) {
                        ForEach(BreakKind.knownValues, id: \.self) { kind in
                            Text(LocalizedStringKey(DynamicL10nKeys.breakKind(kind))).tag(kind)
                        }
                        if !item.kind.isKnown { Text(verbatim: item.kind.rawValue).tag(item.kind) }
                    } label: {
                        Text("editor.breaks.kind")
                    }
                    DateRow(titleKey: "editor.terms.start", date: binding.range.start)
                    DateRow(titleKey: "editor.terms.end", date: binding.range.end)
                    if binding.wrappedValue.range.isEmpty {
                        ValidationMessage(key: "editor.terms.issue.range")
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                let ids = offsets.map { draft.breaks[$0].id }
                draft.breaks.removeAll { ids.contains($0.id) }
            }
            Button {
                let start = draft.breaks.map(\.range.end).max().map { $0.adding(days: 1) } ?? model.today
                draft.addBreak(name: model.renderer.string(forKey: "editor.breaks.defaultName"), kind: .holiday,
                               start: start, id: CalendarBreak.ID(UUID()))
            } label: {
                Label { Text("editor.breaks.add") } icon: { Image(systemName: "plus.circle") }
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("editor.breaks.header")
        } footer: {
            Text("editor.breaks.footer")
        }
    }
}
