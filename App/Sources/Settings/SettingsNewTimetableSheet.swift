// Settings → "Add Another Timetable…" (R3): the one CREATE flow Settings presents as a sheet. Name, emoji and what the new
// timetable's time structure starts from; the new timetable becomes the active one.
//
// This mirrors `NewTimetableSheet`, which is `private` to App/Sources/Editors/TimetablesManager.swift (stage U5b owns that
// file, so it is not touched here). It uses the same `TimetableManagement` planning, the same `EditorScaffold` and the same
// catalog keys, so behaviour and wording are identical. Adopt U5b: when that sheet becomes non-private, delete this file
// and present it instead.
// APIs: sheet, Picker (inline), EditorScaffold, TimetableManagement.addMutation.
import SwiftUI
import TimetableCore
import TimetableUI

private enum NewStructure: String, CaseIterable, Equatable {
    case template, copyActive, freeForm
}

private struct NewTimetableDraft: Equatable {
    var name = ""
    var emoji = ""
    var structure: NewStructure = .template
}

struct SettingsNewTimetableSheet: View {
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
                        Text("editor.timetables.new.template").tag(NewStructure.template)
                        if activeUsesBellSchedule {
                            Text("editor.timetables.new.copy").tag(NewStructure.copyActive)
                        }
                        Text("editor.timetables.new.free").tag(NewStructure.freeForm)
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
