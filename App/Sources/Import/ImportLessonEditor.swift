// Editing one imported lesson before approval (Phase 9 I2): what was read (verbatim), why it needs checking, the
// fields (every field is offered, D10), "Apply to all identical cells" when the same text appears elsewhere, Looks
// Right (keeps the reading and clears the flag) and Remove Lesson (e.g. a header read as a lesson).
// The review screen applies the result through `ImportReview` (setValue / confirm / removeLesson).
// HIG: sheets.md (Cancel + Done), entering-data.md, text-fields.md.
import SwiftUI
import TimetableCore
import TimetableUI

struct ImportLessonEditor: View {
    enum Change {
        case values([(ImportField, String?)], applyToIdentical: Bool)
        case confirm(applyToIdentical: Bool)
        case remove(applyToIdentical: Bool)
    }

    let lesson: ImportLesson
    /// Lessons read from cells with the same text, this one included.
    let identicalCount: Int
    let onChange: (Change) -> Void

    static let editableFields: [ImportField] = [.subject, .room, .teacher, .building, .notes]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values: [ImportField: String] = [:]
    @State private var applyToIdentical = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: lesson.sourceText.isEmpty ? " " : lesson.sourceText)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("import.edit.readAs")
                } footer: {
                    Text(verbatim: ImportA11y.position(lesson, renderer: model.renderer, formatter: model.formatter))
                }

                if lesson.needsReview, !lesson.reasons.isEmpty {
                    Section {
                        ForEach(lesson.reasons.sorted(), id: \.self) { reason in
                            Label { Text(LocalizedStringKey(reason.l10nKey)) } icon: {
                                Image(AppSymbol.warning).foregroundStyle(Color.changed)
                            }
                        }
                    } header: {
                        Text("import.edit.why")
                    }
                }

                Section {
                    ForEach(Self.editableFields, id: \.self) { field in
                        TextField(text: binding(field)) { Text(LocalizedStringKey(field.l10nKey)) }
                            .textInputAutocapitalization(field == .room ? .characters : .sentences)
                            .autocorrectionDisabled()
                            .accessibilityLabel(Text(LocalizedStringKey(field.l10nKey)))
                    }
                } header: {
                    Text("import.edit.fields")
                }

                if identicalCount > 1 {
                    Section {
                        Toggle(isOn: $applyToIdentical) {
                            Text(verbatim: model.renderer.format(key: "import.edit.applyToIdentical",
                                                                 arguments: [.integer(Int64(identicalCount))]))
                        }
                    } footer: {
                        Text("import.edit.applyToIdentical.footer")
                    }
                }

                Section {
                    if lesson.needsReview {
                        Button {
                            onChange(.confirm(applyToIdentical: identicalCount > 1 && applyToIdentical))
                            dismiss()
                        } label: {
                            Label { Text("import.edit.looksRight") } icon: { Image(systemName: "checkmark.circle") }
                        }
                    }
                    Button(role: .destructive) {
                        onChange(.remove(applyToIdentical: identicalCount > 1 && applyToIdentical))
                        dismiss()
                    } label: {
                        Label { Text("import.edit.remove") } icon: { Image(AppSymbol.delete) }
                    }
                }
            }
            .navigationTitle(Text("import.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("editor.common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text("editor.common.done") }
                        .disabled((values[.subject] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            for field in Self.editableFields { values[field] = lesson[field] ?? "" }
        }
    }

    private func binding(_ field: ImportField) -> Binding<String> {
        Binding(get: { values[field] ?? "" }, set: { values[field] = $0 })
    }

    private func save() {
        let changed = Self.editableFields.compactMap { field -> (ImportField, String?)? in
            let value = (values[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value == (lesson[field] ?? "") ? nil : (field, value.isEmpty ? nil : value)
        }
        if !changed.isEmpty { onChange(.values(changed, applyToIdentical: identicalCount > 1 && applyToIdentical)) }
        dismiss()
    }
}
