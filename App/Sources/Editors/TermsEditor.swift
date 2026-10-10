// The terms & breaks editor (`editor.terms`): terms (semesters) and breaks (holiday / vacation / exam period / no
// school) of one timetable, add / edit / remove. A term that lessons are limited to cannot be removed.
// Logic: Packages/TimetableUI/.../Editors/TermsDraft.swift (Linux-tested).
// APIs: Form, Section, Picker, DatePicker through DateRow, Button(role:).
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the terms & breaks editor as sheet content for `timetableID` (default: the active timetable).
struct TermsEditorView: View {
    var timetableID: Timetable.ID?
    @Environment(AppModel.self) private var model

    var body: some View {
        if let database = model.database,
           let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            EditorScaffold(
                titleKey: "editor.terms.title",
                initial: TermsDraft(timetableID: timetable.id, database: database),
                canSave: { $0.canSave },
                save: { draft in model.apply(.batch(draft.mutations(), label: "terms and breaks")) },
                content: { draft in
                    TermsFormContent(draft: draft, locked: TermsDraft.lockedTerms(lessons: database.lessons, timetableID: timetable.id))
                })
        } else {
            EditorUnavailableView(messageKey: "editor.terms.unavailable")
        }
    }
}

private struct TermsFormContent: View {
    @Binding var draft: TermsDraft
    let locked: Set<Term.ID>
    @Environment(AppModel.self) private var model

    var body: some View {
        termsSection
        breaksSection
    }

    private func termBinding(_ id: Term.ID) -> Binding<Term> {
        Binding(
            get: { draft.terms.first { $0.id == id } ?? placeholderTerm(id) },
            set: { newValue in
                if let index = draft.terms.firstIndex(where: { $0.id == id }) { draft.terms[index] = newValue }
            })
    }

    private func breakBinding(_ id: CalendarBreak.ID) -> Binding<CalendarBreak> {
        Binding(
            get: { draft.breaks.first { $0.id == id } ?? placeholderBreak(id) },
            set: { newValue in
                if let index = draft.breaks.firstIndex(where: { $0.id == id }) { draft.breaks[index] = newValue }
            })
    }

    private func placeholderTerm(_ id: Term.ID) -> Term {
        Term(id: id, meta: EditorEntities.placeholderMeta, timetableID: draft.timetableID, name: "",
             range: LocalDateRange(day: model.today))
    }

    private func placeholderBreak(_ id: CalendarBreak.ID) -> CalendarBreak {
        CalendarBreak(id: id, meta: EditorEntities.placeholderMeta, timetableID: draft.timetableID, name: "",
                      range: LocalDateRange(day: model.today))
    }

    // MARK: Terms

    private var termsSection: some View {
        Section {
            ForEach(draft.terms) { term in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        LabeledTextField(titleKey: "editor.terms.name", text: Binding(
                            get: { termBinding(term.id).wrappedValue.name },
                            set: { termBinding(term.id).wrappedValue.name = $0 }))
                        if locked.contains(term.id) {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel(Text("editor.terms.inUse"))
                        } else {
                            Button(role: .destructive) {
                                draft.terms.removeAll { $0.id == term.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("editor.terms.remove"))
                        }
                    }
                    DateRow(titleKey: "editor.terms.start", date: Binding(
                        get: { termBinding(term.id).wrappedValue.range.start },
                        set: { termBinding(term.id).wrappedValue.range.start = $0 }))
                    DateRow(titleKey: "editor.terms.end", date: Binding(
                        get: { termBinding(term.id).wrappedValue.range.end },
                        set: { termBinding(term.id).wrappedValue.range.end = $0 }))
                    if termBinding(term.id).wrappedValue.range.isEmpty {
                        Label { Text("editor.terms.issue.range") } icon: { Image(systemName: "xmark.octagon.fill") }
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(.vertical, 4)
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
            if draft.terms.isEmpty { Text("editor.terms.empty.footer") } else { Text("editor.terms.footer") }
        }
    }

    // MARK: Breaks

    private var breaksSection: some View {
        Section {
            ForEach(draft.breaks) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        LabeledTextField(titleKey: "editor.breaks.name", text: Binding(
                            get: { breakBinding(item.id).wrappedValue.name },
                            set: { breakBinding(item.id).wrappedValue.name = $0 }))
                        Button(role: .destructive) {
                            draft.breaks.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("editor.breaks.remove"))
                    }
                    Picker(selection: Binding(
                        get: { breakBinding(item.id).wrappedValue.kind },
                        set: { breakBinding(item.id).wrappedValue.kind = $0 })) {
                        ForEach(BreakKind.knownValues, id: \.self) { kind in
                            Text(LocalizedStringKey(DynamicL10nKeys.breakKind(kind))).tag(kind)
                        }
                        if !item.kind.isKnown { Text(verbatim: item.kind.rawValue).tag(item.kind) }
                    } label: {
                        Text("editor.breaks.kind")
                    }
                    DateRow(titleKey: "editor.terms.start", date: Binding(
                        get: { breakBinding(item.id).wrappedValue.range.start },
                        set: { breakBinding(item.id).wrappedValue.range.start = $0 }))
                    DateRow(titleKey: "editor.terms.end", date: Binding(
                        get: { breakBinding(item.id).wrappedValue.range.end },
                        set: { breakBinding(item.id).wrappedValue.range.end = $0 }))
                    if breakBinding(item.id).wrappedValue.range.isEmpty {
                        Label { Text("editor.terms.issue.range") } icon: { Image(systemName: "xmark.octagon.fill") }
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(.vertical, 4)
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
