// The timetable settings editor (`editor.timetable`): name, emoji, school days, rotation (none / day cycle / week cycle
// with strict or continuous ISO parity or a reference week, length, labels, rotation week start), time structure,
// lesson fields, default view, density and palette; links to the bell schedule and terms editors.
//
// Guards (see TimetableDraft): the rotation cannot switch between a day cycle and weekdays while lessons exist, and a
// cycle cannot be shorter than what lessons already use; both would otherwise be rejected by validation.
// UX overhaul U5b: identity (name, emoji) and school days are separate sections, and the days are weekday chips in
// the user's week order (M16); no header repeats a row label (M1); the lesson-details copy says the setting only
// affects summaries (D10); "Reset Timetable…" lives here too, so the last timetable (which can't be deleted) can be
// cleared without a hidden menu (M17). Embedded mode (Settings) pushes the bell schedule and terms editors instead of
// stacking sheets.
// Logic: Packages/TimetableUI/.../Editors/TimetableDraft.swift (Linux-tested).
// APIs: Picker, Toggle (.button style through WeekdayChips), Stepper (ValueStepper), sheet(isPresented:),
//   NavigationLink(destination:label:), Section footers, RotationResolver (core).
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the timetable settings for `timetableID` (default: the active timetable): as sheet content, or `embedded` in
/// a parent navigation stack (Settings, the timetables manager in Settings; no own stack, Back leaves while nothing
/// is edited).
struct TimetableEditorView: View {
    var timetableID: Timetable.ID?
    var embedded = false
    @Environment(AppModel.self) private var model

    var body: some View {
        if let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            TimetableEditorBody(timetable: timetable, embedded: embedded)
        } else {
            EmbeddableUnavailableView(embedded: embedded, messageKey: "editor.timetable.unavailable")
        }
    }
}

private struct TimetableEditorBody: View {
    let timetable: Timetable
    let embedded: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let initial = TimetableDraft(timetable: timetable, today: model.today)
        let lessonCount = (model.database?.lessons ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }.count
        EmbeddableEditorScaffold(
            embedded: embedded,
            titleKey: "editor.timetable.title",
            initial: initial,
            canSave: { $0.canSave },
            save: { draft in
                guard let database = model.database else { return nil }
                // The bell-schedule and terms sheets save while this editor is open: build on the timetable as stored
                // NOW, not on the one captured when this editor opened (a stale copy would drop their changes).
                let stored = database.timetables.first { $0.id == timetable.id && !$0.isDeleted } ?? timetable
                var ids = SystemIDGenerator()
                let resolved = draft.resolveTimeStructure(
                    existingSchedules: database.bellSchedules,
                    scheduleName: model.renderer.string(forKey: "editor.bell.defaultName"), ids: &ids, current: stored)
                guard let edited = draft.makeTimetable(timeStructure: resolved.structure, onto: stored) else { return nil }
                return model.apply(.batch(resolved.extra + [.upsert(edited)], label: "timetable settings"))
            },
            content: { draft in
                TimetableFormContent(draft: draft, timetable: timetable, originalKind: initial.rotationKind,
                                     lessonCount: lessonCount, lessons: model.database?.lessons ?? [], embedded: embedded)
            })
    }
}

private struct TimetableFormContent: View {
    @Binding var draft: TimetableDraft
    let timetable: Timetable
    let originalKind: TimetableDraft.RotationKind
    let lessonCount: Int
    let lessons: [Lesson]
    let embedded: Bool
    @Environment(AppModel.self) private var model
    @State private var editingBell = false
    @State private var editingTerms = false
    @State private var confirmingReset = false
    @State private var resetFailed = false

    private var weekdays: [Weekday] { Weekday.week(startingAt: model.calendarContext.firstWeekday) }

    var body: some View {
        identitySection
        schoolDaysSection
        rotationSection
        switch draft.rotationKind {
        case .none: EmptyView()
        case .weekCycle: weekCycleSection
        case .dayCycle: dayCycleSection
        }
        timeSection
        fieldsSection
        appearanceSection
        termsSection
        resetSection
    }

    // MARK: Identity and school days (M16: split, chips in week order)

    private var identitySection: some View {
        Section {
            EditorTitleField(promptKey: "editor.timetable.name.prompt", text: $draft.name,
                             missingHintKey: TimetableDraft.Issue.noName.l10nKey)
            LabeledTextField(titleKey: "editor.timetable.emoji", text: $draft.emoji)
                .onChange(of: draft.emoji) { _, newValue in
                    if let first = EditorText.firstCharacter(newValue), first != newValue { draft.emoji = first }
                }
        }
    }

    private var schoolDaysSection: some View {
        Section {
            WeekdayChips(
                days: weekdays,
                isOn: { draft.enabledDays.contains($0) },
                setOn: { day, isOn in
                    if isOn { draft.enabledDays.insert(day) } else { draft.enabledDays.remove(day) }
                })
        } header: {
            Text("editor.timetable.days")
        } footer: {
            ForEach(draft.issues.filter { $0 != .noName }, id: \.self) { issue in
                ValidationMessage(key: issue.l10nKey)
            }
        }
    }

    // MARK: Rotation

    private var allowedKinds: [TimetableDraft.RotationKind] {
        TimetableDraft.RotationKind.allCases.filter { kind in
            TimetableDraft.canChangeRotationFamily(lessonCount: lessonCount)
                || !TimetableDraft.isFamilyChange(from: originalKind, to: kind)
        }
    }

    private var rotationSection: some View {
        Section {
            Picker(selection: Binding(
                get: { draft.rotationKind },
                set: { newKind in
                    draft.rotationKind = newKind
                    // A day cycle runs on the days the timetable shows; start from them (fewer mismatches).
                    if newKind == .dayCycle && originalKind != .dayCycle { draft.daySchoolDays = draft.enabledDays }
                })) {
                ForEach(allowedKinds, id: \.self) { kind in
                    Text(LocalizedStringKey(DynamicL10nKeys.rotationKind(kind))).tag(kind)
                }
            } label: {
                Text("editor.rotation")
            }
        } footer: {
            if !TimetableDraft.canChangeRotationFamily(lessonCount: lessonCount) {
                Text("editor.rotation.locked.footer")
            } else {
                Text("editor.rotation.footer")
            }
        }
    }

    private var minimumWeekLength: Int {
        TimetableDraft.minimumWeekCycleLength(lessons: lessons, timetableID: timetable.id)
    }

    private var weekCycleSection: some View {
        Section {
            ValueStepper(titleKey: "editor.rotation.week.length", value: $draft.weekLength,
                         range: minimumWeekLength...WeekCycle.validLengths.upperBound)
            Picker(selection: $draft.anchorKind) {
                Text("editor.rotation.anchor.strict").tag(TimetableDraft.AnchorKind.strictParity)
                Text("editor.rotation.anchor.continuous").tag(TimetableDraft.AnchorKind.continuousParity)
                Text("editor.rotation.anchor.reference").tag(TimetableDraft.AnchorKind.referenceWeek)
            } label: {
                Text("editor.rotation.anchor")
            }
            switch draft.anchorKind {
            case .strictParity, .continuousParity:
                ValueStepper(titleKey: "editor.rotation.offset", value: $draft.parityOffset,
                             range: 0...max(0, draft.weekLength - 1))
            case .referenceWeek:
                DateRow(titleKey: "editor.rotation.referenceDate", date: $draft.referenceDate)
                Picker(selection: $draft.referenceWeek) {
                    ForEach(1...max(1, draft.weekLength), id: \.self) { week in
                        Text(verbatim: labelText(week, labels: draft.weekLabels, key: "editor.cycleWeek.name")).tag(week)
                    }
                } label: {
                    Text("editor.rotation.referenceWeek")
                }
            }
            weekLabelFields
            Picker(selection: $draft.rotationWeekStart) {
                ForEach(weekdays, id: \.self) { day in Text(verbatim: model.formatter.weekdayName(day)).tag(day) }
            } label: {
                Text("editor.rotation.weekStart")
            }
            currentPosition
        } header: {
            Text("editor.rotation.week.header")
        } footer: {
            Text("editor.rotation.week.footer")
        }
    }

    @ViewBuilder
    private var weekLabelFields: some View {
        ForEach(1...max(1, draft.weekLength), id: \.self) { week in
            LabeledContent {
                TextField(text: weekLabelBinding(week), prompt: Text(emptyPrompt)) { Text("editor.rotation.label") }
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(verbatim: model.renderer.format(key: "editor.rotation.week.label", arguments: [.integer(Int64(week))]))
            }
        }
    }

    private func weekLabelBinding(_ week: Int) -> Binding<String> {
        Binding(
            get: { draft.weekLabels.indices.contains(week - 1) ? draft.weekLabels[week - 1] : "" },
            set: { value in
                while draft.weekLabels.count < week { draft.weekLabels.append("") }
                draft.weekLabels[week - 1] = value
            })
    }

    private func labelText(_ index: Int, labels: [String], key: String) -> String {
        if let label = DayChoices.label(at: index, in: labels) { return label }
        return model.renderer.format(key: key, arguments: [.integer(Int64(index))])
    }

    /// "Today is week B" for week cycles / "Today is day 3" for day cycles, from the edited values.
    @ViewBuilder
    private var currentPosition: some View {
        let resolver = RotationResolver(scheme: draft.rotation, firstWeekday: draft.rotationWeekStart,
                                        breaks: breakRanges)
        switch draft.rotationKind {
        case .weekCycle:
            if let week = resolver.cycleWeek(on: model.today) {
                Text(verbatim: model.renderer.format(key: "editor.rotation.today.week", arguments: [
                    .text(resolver.label(forCycleWeek: week).flatMap(EditorText.trimmedOrNil)
                        ?? model.renderer.format(key: "editor.cycleWeek.name", arguments: [.integer(Int64(week))]))]))
                    .foregroundStyle(.secondary)
            }
        case .dayCycle:
            if let day = resolver.cycleDay(on: model.today) {
                Text(verbatim: model.renderer.format(key: "editor.rotation.today.day", arguments: [
                    .text(resolver.label(forCycleDay: day).flatMap(EditorText.trimmedOrNil)
                        ?? model.renderer.format(key: "editor.cycleDay.name", arguments: [.integer(Int64(day))]))]))
                    .foregroundStyle(.secondary)
            }
        case .none:
            EmptyView()
        }
    }

    private var breakRanges: [LocalDateRange] {
        (model.database?.breaks ?? []).filter { !$0.isDeleted && ($0.timetableID == nil || $0.timetableID == timetable.id) }.map(\.range)
    }

    // MARK: Day cycle

    private var minimumDayLength: Int {
        TimetableDraft.minimumDayCycleLength(lessons: lessons, timetableID: timetable.id)
    }

    private var dayCycleSection: some View {
        Section {
            ValueStepper(titleKey: "editor.rotation.day.length", value: $draft.dayLength,
                         range: minimumDayLength...DayCycle.validLengths.upperBound)
            DateRow(titleKey: "editor.rotation.day.anchorDate", date: $draft.dayAnchorDate)
            Picker(selection: $draft.dayAnchorIndex) {
                ForEach(1...max(1, draft.dayLength), id: \.self) { index in
                    Text(verbatim: labelText(index, labels: draft.dayLabels, key: "editor.cycleDay.name")).tag(index)
                }
            } label: {
                Text("editor.rotation.day.anchorIndex")
            }
            Toggle(isOn: $draft.daySkipsBreaks) { Text("editor.rotation.day.skipsBreaks") }
            ForEach(1...max(1, draft.dayLength), id: \.self) { index in
                LabeledContent {
                    TextField(text: dayLabelBinding(index), prompt: Text(emptyPrompt)) { Text("editor.rotation.label") }
                        .multilineTextAlignment(.trailing)
                } label: {
                    Text(verbatim: model.renderer.format(key: "editor.rotation.day.label", arguments: [.integer(Int64(index))]))
                }
            }
            currentPosition
        } header: {
            Text("editor.rotation.day.header")
        } footer: {
            Text("editor.rotation.day.footer")
        }
        .onChange(of: draft.dayLength) { _, newValue in
            if draft.dayAnchorIndex > newValue { draft.dayAnchorIndex = newValue }
        }
    }

    private func dayLabelBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.dayLabels.indices.contains(index - 1) ? draft.dayLabels[index - 1] : "" },
            set: { value in
                while draft.dayLabels.count < index { draft.dayLabels.append("") }
                draft.dayLabels[index - 1] = value
            })
    }

    // MARK: Time structure

    private var timeSection: some View {
        Section {
            Picker(selection: $draft.timeKind) {
                Text("editor.time.bell").tag(TimetableDraft.TimeKind.bellSchedule)
                Text("editor.time.free").tag(TimetableDraft.TimeKind.freeForm)
            } label: {
                Text("editor.time")
            }
            switch draft.timeKind {
            case .bellSchedule:
                if case .bellSchedule = timetable.timeStructure {
                    if embedded {
                        NavigationLink {
                            BellScheduleEditorView(timetableID: timetable.id, embedded: true)
                        } label: {
                            Label { Text("editor.time.editBell") } icon: { Image(systemName: "bell") }
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    } else {
                        Button { editingBell = true } label: {
                            Label { Text("editor.time.editBell") } icon: { Image(systemName: "bell") }
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                }
            case .freeForm:
                ValueStepper(titleKey: "editor.time.freeMinutes", value: $draft.freeMinutes, range: 5...240)
            }
        } header: {
            Text("editor.time.header")
        } footer: {
            if draft.timeKind == .bellSchedule, case .freeForm = timetable.timeStructure {
                Text("editor.time.switchFooter")
            } else {
                Text("editor.time.footer")
            }
        }
        .sheet(isPresented: $editingBell) { BellScheduleEditorView(timetableID: timetable.id) }
    }

    // MARK: Fields

    private var fieldsSection: some View {
        Section {
            ForEach(LessonField.knownValues, id: \.self) { field in
                Toggle(isOn: Binding(
                    get: { draft.visibleFields.contains(field) },
                    set: { isOn in
                        if isOn { draft.visibleFields.insert(field) } else { draft.visibleFields.remove(field) }
                    })) {
                    Text(LocalizedStringKey(DynamicL10nKeys.lessonField(field)))
                }
            }
        } header: {
            Text("editor.fields.header")
        } footer: {
            Text("editor.fields.footer")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker(selection: $draft.defaultView) {
                ForEach(viewChoices, id: \.self) { kind in
                    Text(LocalizedStringKey(DynamicL10nKeys.defaultView(kind))).tag(kind)
                }
            } label: {
                Text("editor.view")
            }
            Picker(selection: $draft.density) {
                Text("editor.density.comfortable").tag(Density.comfortable)
                Text("editor.density.compact").tag(Density.compact)
            } label: {
                Text("editor.density")
            }
            .pickerStyle(.segmented)
            Picker(selection: $draft.palettePackID) {
                Text("editor.palette.appDefault").tag(PalettePackID?.none)
                ForEach(PalettePack.all) { pack in
                    let locked = pack.requiresPro && !model.entitlements.isAllowed(.themePacks)
                    if !locked || draft.palettePackID == pack.id {
                        Text(LocalizedStringKey(pack.nameKey)).tag(PalettePackID?.some(pack.id))
                    }
                }
            } label: {
                Text("editor.palette")
            }
        } header: {
            Text("editor.appearance.header")
        }
    }

    private var viewChoices: [TimetableViewKind] {
        var kinds: [TimetableViewKind] = [.grid, .timeBlocks, .day, .tiles]
        if !kinds.contains(draft.defaultView) { kinds.append(draft.defaultView) }
        return kinds
    }

    // MARK: Terms

    private var termsSection: some View {
        Section {
            if embedded {
                NavigationLink {
                    TermsEditorView(timetableID: timetable.id, embedded: true)
                } label: {
                    Label { Text("editor.terms.open") } icon: { Image(systemName: "calendar.badge.clock") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            } else {
                Button { editingTerms = true } label: {
                    Label { Text("editor.terms.open") } icon: { Image(systemName: "calendar.badge.clock") }
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        } footer: {
            Text("editor.terms.open.footer")
        }
        .sheet(isPresented: $editingTerms) { TermsEditorView(timetableID: timetable.id) }
    }

    // MARK: Reset (applies at once, with an impact confirmation, like Delete Lesson in the lesson editor)

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Text("editor.timetables.reset.action").frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(lessonCount == 0)
        } footer: {
            if resetFailed {
                Text("editor.error.failed").foregroundStyle(.red)
            } else if lessonCount == 0 {
                Text("editor.timetable.reset.empty.footer")
            }
        }
        .sheet(isPresented: $confirmingReset) {
            if let database = model.database {
                let impact = TimetableManagement.resetImpact(of: timetable.id, in: database)
                ImpactConfirmation(
                    title: "editor.timetables.reset.title", subjectName: timetable.name,
                    rows: [ImpactRow(id: "lessons", key: "editor.impact.lessons", count: impact.lessons),
                           ImpactRow(id: "changes", key: "editor.impact.dayChanges", count: impact.changes)],
                    note: "editor.timetables.reset.note", action: "editor.timetables.reset") {
                        guard let database = model.database else { return }
                        if case .applied = model.apply(TimetableManagement.resetMutation(timetable.id, in: database)) {
                            resetFailed = false
                        } else {
                            resetFailed = true
                        }
                    }
            }
        }
    }
}
