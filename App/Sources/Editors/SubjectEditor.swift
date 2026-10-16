// Subject editing: `editor.subject` (one subject: name, short name, colour from palette packs or a custom colour, emoji
// or SF Symbol, default room / building / teacher, live tile preview with contrast information) and `editor.subjects`
// (the list: add, edit, delete with an impact confirmation, reorder).
//
// Order (P3-2, Phase 4 C1): subjects have a manual order (`Subject.sortIndex`) shown everywhere through `SubjectOrder`.
// The list reorders in reorder mode (toolbar "Reorder", drag handles, `onMove`) and, for VoiceOver, with the "Move up" /
// "Move down" accessibility actions on each row, which announce the new position. New subjects are added at the end; the editor never changes the order
// (`TimetableManagement.saveSubjectMutation` keeps the stored index). Changes apply immediately, like the timetables
// manager.
// APIs: ColorPicker(_:selection:supportsOpacity:), LazyVGrid(columns:) with GridItem(.adaptive(minimum:)), Menu, Label,
//   sheet(item:), swipeActions(edge:allowsFullSwipe:content:), accessibilityAddTraits(.isSelected), List, EditButton,
//   onMove(perform:), environment(\.editMode), accessibilityActions(_:) (iOS 16+) and
//   AccessibilityNotification.Announcement(_:).post() (iOS 17+), both verified in Apple's documentation JSON 2026-10-16.
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the subject editor as sheet content. `subjectID == nil` creates a subject in `timetableID` (default: the
/// active timetable); `onSaved` receives the ID of the saved subject (the lesson editor selects it).
struct SubjectEditorView: View {
    let subjectID: Subject.ID?
    var timetableID: Timetable.ID?
    var onSaved: ((Subject.ID) -> Void)?
    @Environment(AppModel.self) private var model
    @State private var newID = Subject.ID(UUID())

    var body: some View {
        if let draft = initialDraft(), let timetable = timetable(for: draft) {
            SubjectEditorBody(timetable: timetable, initial: draft, onSaved: onSaved)
        } else {
            EditorUnavailableView(messageKey: "editor.subject.unavailable")
        }
    }

    private func timetable(for draft: SubjectDraft) -> Timetable? {
        model.timetables.first { $0.id == draft.timetableID }
    }

    private func initialDraft() -> SubjectDraft? {
        guard let database = model.database else { return nil }
        if let subjectID {
            guard let subject = database.subjects.first(where: { $0.id == subjectID && !$0.isDeleted }) else { return nil }
            return SubjectDraft(subject: subject)
        }
        guard let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable
        else { return nil }
        let used = database.subjects.filter { !$0.isDeleted && $0.timetableID == timetable.id }.map(\.color)
        let pack = timetable.palettePackID ?? model.settings.palettePackID
        return SubjectDraft(newIn: timetable, pack: pack, usedColors: used, id: newID)
    }
}

private struct SubjectEditorBody: View {
    let timetable: Timetable
    let initial: SubjectDraft
    let onSaved: ((Subject.ID) -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorScaffold(
            titleKey: initial.isNew ? "editor.subject.title.new" : "editor.subject.title.edit",
            initial: initial,
            canSave: { $0.canSave },
            save: { draft in
                guard let subject = draft.makeSubject(), let database = model.database else { return nil }
                let result = model.apply(TimetableManagement.saveSubjectMutation(subject, in: database,
                                                                                 locale: model.formatter.locale))
                if case .applied = result { onSaved?(subject.id) }
                return result
            },
            content: { draft in SubjectFormContent(draft: draft, timetable: timetable) })
    }
}

private struct SubjectFormContent: View {
    @Binding var draft: SubjectDraft
    let timetable: Timetable
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var browsingPack: PalettePackID?
    @State private var confirmingDelete = false
    @State private var deleteFailed = false

    private var visibility: FieldVisibility { timetable.fieldVisibility }
    private var activePack: PalettePack {
        let id = browsingPack ?? currentPaletteChoice ?? timetable.palettePackID ?? model.settings.palettePackID
        return PalettePack.pack(id) ?? .classic
    }

    private var currentPaletteChoice: PalettePackID? {
        if case .palette(let pack, _) = draft.colorChoice { return pack }
        return nil
    }

    var body: some View {
        previewSection
        nameSection
        colorSection
        symbolSection
        defaultsSection
        if !draft.isNew { deleteSection }
    }

    // MARK: Preview

    private var previewSection: some View {
        let style = draft.tileStyle
        let name = EditorText.trimmedOrNil(draft.name) ?? ""
        let summary = SubjectSummary(id: draft.subjectID, name: name, shortName: EditorText.trimmedOrNil(draft.shortName),
                                     color: draft.color, symbol: draft.symbol)
        return Section {
            HStack(spacing: 12) {
                SubjectBadge(subject: summary, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    if !name.isEmpty { Text(verbatim: name).font(.headline) }
                    if let short = summary.shortName { Text(verbatim: short).font(.subheadline) }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(style.foreground))
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(style.background)))
            .overlay {
                if style.needsOutline(isDark: colorScheme == .dark) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("editor.subject.preview"))
            .accessibilityValue(Text(verbatim: [name, summary.shortName ?? ""].filter { !$0.isEmpty }.joined(separator: model.renderer.string(forKey: "a11y.separator"))))
        } header: {
            Text("editor.subject.preview")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: model.renderer.format(key: "editor.subject.contrast",
                                                     arguments: [.text(draft.contrastRatio.formatted(.number.precision(.fractionLength(1))))]))
                if draft.hasLowContrast {
                    Label { Text("editor.subject.contrast.low") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .foregroundStyle(.orange)
                }
                if draft.blendsIntoBackground(isDark: colorScheme == .dark) {
                    Label { Text("editor.subject.contrast.blends") } icon: { Image(systemName: "info.circle") }
                }
            }
        }
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            LabeledTextField(titleKey: "editor.subject.name", text: $draft.name)
            LabeledTextField(titleKey: "editor.subject.shortName", text: $draft.shortName)
        } footer: {
            if let issue = draft.issues.first { Text(LocalizedStringKey(issue.l10nKey)).foregroundStyle(.red) }
        }
    }

    // MARK: Colour

    private var colorSection: some View {
        Section {
            packMenu
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 12)], spacing: 12) {
                ForEach(activePack.colors) { colour in swatch(colour, in: activePack) }
            }
            .padding(.vertical, 4)
            ColorPicker(selection: Binding(
                get: { Color(draft.color) },
                set: { draft.colorChoice = .custom(ColorBridge.value(of: $0)) }),
                        supportsOpacity: false) {
                Text("editor.subject.color.custom")
            }
            .frame(minHeight: 44)
        } header: {
            Text("editor.subject.color")
        }
    }

    private var packMenu: some View {
        Menu {
            ForEach(PalettePack.all) { pack in
                let locked = pack.requiresPro && !model.entitlements.isAllowed(.themePacks)
                Button {
                    browsingPack = pack.id
                } label: {
                    if locked {
                        Label { Text(LocalizedStringKey(pack.nameKey)) } icon: { Image(systemName: "lock.fill") }
                    } else if pack.id == activePack.id {
                        Label { Text(LocalizedStringKey(pack.nameKey)) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(LocalizedStringKey(pack.nameKey))
                    }
                }
                .disabled(locked)
            }
        } label: {
            LabeledContent {
                Text(LocalizedStringKey(activePack.nameKey))
            } label: {
                Text("editor.subject.palette")
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("editor.subject.palette"))
        .accessibilityValue(Text(LocalizedStringKey(activePack.nameKey)))
    }

    private func swatch(_ colour: PaletteColor, in pack: PalettePack) -> some View {
        let selected = draft.colorChoice == .palette(pack: pack.id, colorID: colour.id)
        return Button {
            draft.colorChoice = .palette(pack: pack.id, colorID: colour.id)
        } label: {
            ZStack {
                Circle().fill(Color(colour.value))
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                if selected {
                    Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(Color(colour.textColor))
                }
            }
            .frame(width: 44, height: 44)
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(colour.nameKey)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Symbol

    private var symbolSection: some View {
        Section {
            Picker(selection: $draft.symbolKind) {
                Text("editor.subject.symbol.none").tag(SubjectDraft.SymbolKind.none)
                Text("editor.subject.symbol.emoji").tag(SubjectDraft.SymbolKind.emoji)
                Text("editor.subject.symbol.system").tag(SubjectDraft.SymbolKind.systemImage)
            } label: {
                Text("editor.subject.symbol")
            }
            .pickerStyle(.segmented)
            switch draft.symbolKind {
            case .none:
                EmptyView()
            case .emoji:
                LabeledTextField(titleKey: "editor.subject.symbol.emoji.field", text: $draft.emoji)
                    .onChange(of: draft.emoji) { _, newValue in
                        if let first = EditorText.firstCharacter(newValue), first != newValue { draft.emoji = first }
                    }
            case .systemImage:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                    ForEach(SubjectDraft.symbolSuggestions, id: \.self) { name in
                        let selected = draft.systemImage == name
                        Button {
                            draft.systemImage = name
                        } label: {
                            Image(systemName: name)
                                .font(.title3)
                                .frame(width: 48, height: 48)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.2) : Color.clear))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: name.replacingOccurrences(of: ".", with: " ")))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                LabeledTextField(titleKey: "editor.subject.symbol.system.field", text: $draft.systemImage)
            }
        } header: {
            Text("editor.subject.symbol")
        }
    }

    // MARK: Defaults (field rule)

    @ViewBuilder
    private var defaultsSection: some View {
        let shown = EditorFieldPolicy.shownFields(visibility).filter { [.room, .building, .teacher, .notes].contains($0) }
        if !shown.isEmpty {
            Section {
                if shown.contains(.room) { LabeledTextField(titleKey: "editor.field.room", text: $draft.defaultRoom) }
                if shown.contains(.building) { LabeledTextField(titleKey: "editor.field.building", text: $draft.defaultBuilding) }
                if shown.contains(.teacher) { LabeledTextField(titleKey: "editor.field.teacher", text: $draft.defaultTeacher) }
                if shown.contains(.notes) { LabeledTextField(titleKey: "editor.field.notes", text: $draft.notes, axis: .vertical) }
            } header: {
                Text("editor.subject.defaults")
            } footer: {
                Text("editor.subject.defaults.footer")
            }
        }
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Text("editor.subject.delete").frame(maxWidth: .infinity, minHeight: 44)
            }
        } footer: {
            if deleteFailed { Text("editor.error.failed").foregroundStyle(.red) }
        }
        .sheet(isPresented: $confirmingDelete) {
            SubjectDeleteConfirmation(subjectID: draft.subjectID, name: draft.name) { dismiss() } onFailure: { deleteFailed = true }
        }
    }
}

/// The confirmation (with impact counts) shared by the subject editor and the subjects list.
struct SubjectDeleteConfirmation: View {
    let subjectID: Subject.ID
    let name: String
    let onDeleted: () -> Void
    var onFailure: () -> Void = {}
    @Environment(AppModel.self) private var model

    var body: some View {
        let impact: (lessons: Int, changes: Int, linkedItems: Int) =
            model.database.map { TimetableManagement.subjectImpact(of: subjectID, in: $0) } ?? (lessons: 0, changes: 0, linkedItems: 0)
        ImpactConfirmation(
            title: "editor.subject.delete.title", subjectName: name,
            rows: [ImpactRow(id: "lessons", key: "editor.impact.lessons", count: impact.lessons),
                   ImpactRow(id: "changes", key: "editor.impact.dayChanges", count: impact.changes),
                   ImpactRow(id: "linked", key: "editor.impact.linkedItems", count: impact.linkedItems)],
            note: "editor.subject.delete.note", action: "editor.subject.delete") {
                guard let database = model.database else { return }
                if case .applied = model.apply(TimetableManagement.deleteSubjectMutation(subjectID, in: database)) {
                    onDeleted()
                } else {
                    onFailure()
                }
            }
    }
}

// MARK: - List

/// What the subjects list edits: `subjectID == nil` creates a new subject.
private struct SubjectEditTarget: Identifiable {
    let id = UUID()
    let subjectID: Subject.ID?
}

/// `editor.subjects`: all subjects of a timetable in display order: add, edit, delete, reorder.
struct SubjectsListView: View {
    var timetableID: Timetable.ID?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SubjectEditTarget?
    @State private var deleting: Subject?
    @State private var failure: ApplyResult?
    /// Reorder mode (drag handles). Driven by our own toggle, not `EditButton`: the system button turns into a second
    /// "Done" next to the sheet's Done (QA C1), so the sheet's Done is hidden while reordering and the toggle has a
    /// distinct VoiceOver label.
    @State private var editMode: EditMode = .inactive

    private var timetable: Timetable? {
        timetableID.flatMap { id in model.timetables.first { $0.id == id } } ?? model.activeTimetable
    }

    private var subjects: [Subject] {
        guard let timetable, let database = model.database else { return [] }
        return TimetableManagement.subjects(of: timetable.id, in: database, locale: model.formatter.locale)
    }

    var body: some View {
        NavigationStack {
            Group {
                if timetable == nil {
                    ContentUnavailableView {
                        Label { Text("editor.unavailable.title") } icon: { Image(systemName: "books.vertical") }
                    } description: {
                        Text("editor.subject.unavailable")
                    }
                } else if subjects.isEmpty {
                    ContentUnavailableView {
                        Label { Text("editor.subjects.empty.title") } icon: { Image(systemName: "books.vertical") }
                    } description: {
                        Text("editor.subjects.empty.message")
                    } actions: {
                        Button { editing = SubjectEditTarget(subjectID: nil) } label: { Text("editor.subjects.add") }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: subjects.count) { _, count in if count < 2 { editMode = .inactive } }
            .navigationTitle(Text("editor.subjects.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !editMode.isEditing {
                        Button { dismiss() } label: { Text("editor.common.done") }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    // Reorder mode shows the drag handles (nothing to order with fewer than two subjects).
                    if editMode.isEditing {
                        Button { withAnimation { editMode = .inactive } } label: { Text("editor.common.done") }
                            .fontWeight(.semibold)
                            .accessibilityLabel(Text("editor.subjects.reorder.done"))
                    } else {
                        Button { withAnimation { editMode = .active } } label: { Text("editor.subjects.reorder") }
                            .disabled(subjects.count < 2)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = SubjectEditTarget(subjectID: nil) } label: {
                        Label { Text("editor.subjects.add") } icon: { Image(systemName: "plus") }
                    }
                    .disabled(timetable == nil)
                }
            }
        }
        .sheet(item: $editing) { target in
            SubjectEditorView(subjectID: target.subjectID, timetableID: timetable?.id)
        }
        .sheet(item: $deleting) { subject in
            SubjectDeleteConfirmation(subjectID: subject.id, name: subject.name) {}
        }
    }

    private var list: some View {
        let ordered = subjects
        return List {
            if let failure { ApplyResultSection(result: failure) }
            Section {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { position, subject in
                    Button {
                        editing = SubjectEditTarget(subjectID: subject.id)
                    } label: {
                        HStack(spacing: 12) {
                            SubjectBadge(subject: SubjectSummary(subject), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: subject.name).font(.body).foregroundStyle(.primary)
                                if let short = subject.shortName, !short.isEmpty {
                                    Text(verbatim: short).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleting = subject } label: { Text("editor.common.delete") }
                    }
                    .contextMenu {
                        Button(role: .destructive) { deleting = subject } label: {
                            Label { Text("editor.common.delete") } icon: { Image(systemName: "trash") }
                        }
                    }
                    // VoiceOver: reorder without dragging (rotor "Actions").
                    .accessibilityActions {
                        if position > 0 {
                            Button { step(subject.id, by: -1) } label: { Text("editor.subjects.moveUp") }
                        }
                        if position < ordered.count - 1 {
                            Button { step(subject.id, by: 1) } label: { Text("editor.subjects.moveDown") }
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                // The reorder hint only when reordering is possible (two or more subjects).
                if ordered.count > 1 {
                    Text("editor.subjects.footer")
                } else {
                    Text("editor.subjects.footer.single")
                }
            }
        }
    }

    // MARK: Reorder (applied immediately, like the timetables manager)

    /// Applies `mutation`; `true` when it was applied.
    @discardableResult
    private func run(_ mutation: DatabaseMutation) -> Bool {
        let result = model.apply(mutation)
        if case .applied = result {
            failure = nil
            return true
        }
        failure = result
        return false
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let database = model.database, let timetable else { return }
        var order = subjects.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        // A row dropped where it was changes nothing: no apply (no save, no change notification).
        guard let mutation = TimetableManagement.reorderSubjectsMutation(order, timetableID: timetable.id, in: database,
                                                                        locale: model.formatter.locale) else { return }
        run(mutation)
    }

    /// The VoiceOver "Move up" / "Move down" actions: move, then announce the new position (`editor.subjects.moved`).
    private func step(_ id: Subject.ID, by offset: Int) {
        guard let database = model.database,
              let mutation = TimetableManagement.moveSubjectMutation(id, by: offset, in: database, locale: model.formatter.locale)
        else { return }
        guard run(mutation) else { return }
        let order = subjects.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let text = model.renderer.format(key: "editor.subjects.moved",
                                         arguments: [.integer(Int64(index + 1)), .integer(Int64(order.count))])
        AccessibilityNotification.Announcement(text).post()
    }
}
