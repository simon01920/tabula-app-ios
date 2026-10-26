// Embedded mode of the Save/Cancel editors (U5a hand-off): Settings pushes TimetableEditorView, BellScheduleEditorView
// and TermsEditorView inside its own NavigationStack (`SettingsPushedEditor`). Embedded, an editor has no
// NavigationStack of its own and no Cancel/Done while nothing is edited: the parent's Back button pops it. Save works
// as in the sheet and pops after saving.
//
// Data-loss rule (HIG modality.md › "help people avoid data loss by getting confirmation before closing"): while the
// draft has unsaved edits the Back button (and the swipe-back gesture with it) is replaced by Cancel with the same
// discard confirmation as the sheet, so leaving can never drop edits silently.
//
// `EditorScaffold` (EditorSupport.swift) is shared and owned by stage U1, so this is a separate view with the same
// behaviour rather than a change to it. Adopt U1: when U1 adds an embedded mode to `EditorScaffold`, replace
// `EmbeddableEditorScaffold` with it.
import SwiftUI
import TimetableCore
import TimetableUI

/// `EditorScaffold` as a sheet, or the embedded variant inside a parent navigation stack.
struct EmbeddableEditorScaffold<Draft: Equatable, Content: View>: View {
    let embedded: Bool
    let titleKey: LocalizedStringKey
    let initial: Draft
    let canSave: (Draft) -> Bool
    let save: (Draft) -> ApplyResult?
    @ViewBuilder let content: (Binding<Draft>) -> Content

    var body: some View {
        if embedded {
            EmbeddedEditorScaffold(titleKey: titleKey, initial: initial, canSave: canSave, save: save, content: content)
        } else {
            EditorScaffold(titleKey: titleKey, initial: initial, canSave: canSave, save: save, content: content)
        }
    }
}

/// `EditorUnavailableView` as a sheet (with Close), or just the message when embedded (Back leaves).
struct EmbeddableUnavailableView: View {
    let embedded: Bool
    let messageKey: LocalizedStringKey

    var body: some View {
        if embedded {
            ContentUnavailableView {
                Label { Text("editor.unavailable.title") } icon: { Image(systemName: "square.and.pencil") }
            } description: {
                Text(messageKey)
            }
        } else {
            EditorUnavailableView(messageKey: messageKey)
        }
    }
}

/// The scaffold without its own NavigationStack: Save on the trailing side; Cancel only while there are edits.
private struct EmbeddedEditorScaffold<Draft: Equatable, Content: View>: View {
    let titleKey: LocalizedStringKey
    let initial: Draft
    let canSave: (Draft) -> Bool
    let save: (Draft) -> ApplyResult?
    @ViewBuilder let content: (Binding<Draft>) -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var edited: Draft?
    @State private var result: ApplyResult?
    @State private var confirmingDiscard = false
    @State private var warningLines: [ApplyWarningLine] = []
    @State private var showingWarnings = false

    private var current: Draft { edited ?? initial }
    private var isDirty: Bool { edited != nil && edited != initial }

    var body: some View {
        Form {
            if let result {
                ApplyResultSection(result: result)
            }
            content(Binding(get: { edited ?? initial }, set: { edited = $0 }))
        }
        .navigationTitle(titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .cancellationAction) {
                    Button { confirmingDiscard = true } label: { Text("editor.common.cancel") }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { commit() } label: { Text("editor.common.save") }
                    .disabled(!isDirty || !canSave(current))
            }
        }
        .confirmationDialog("editor.common.discard.title", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("editor.common.discard", role: .destructive) { dismiss() }
            Button("editor.common.keepEditing", role: .cancel) {}
        } message: {
            Text("editor.common.discard.message")
        }
        .alert("editor.warnings.title", isPresented: $showingWarnings) {
            Button("editor.warnings.ok") { dismiss() }
        } message: {
            Text(verbatim: warningText)
        }
        .protectsUnsavedWork(isDirty)
    }

    private var warningText: String {
        warningLines.map { line -> String in
            if line.takesCount {
                return model.renderer.format(key: line.messageKey, arguments: [.integer(Int64(line.count))])
            }
            let message = model.renderer.string(forKey: line.messageKey)
            guard let entityKey = line.entityKey else { return message }
            return model.renderer.format(key: "editor.warnings.line",
                                         arguments: [.text(model.renderer.string(forKey: entityKey)), .text(message)])
        }.joined(separator: "\n")
    }

    private func commit() {
        guard let outcome = save(current) else { return }
        if case .applied(let warnings) = outcome {
            let lines = ApplyWarnings.lines(from: warnings)
            if lines.isEmpty {
                dismiss()
            } else {
                warningLines = lines
                showingWarnings = true
            }
        } else {
            result = outcome
        }
    }
}
