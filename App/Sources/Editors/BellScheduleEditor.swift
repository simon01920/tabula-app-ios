// The bell schedule editor (`editor.bell`, UX overhaul C1 + R6): one schedule at a time, chosen with a picker
// (Regular, weekday variants, schedules for single dates such as "Shortened"), one row per period ("1  08:00–08:45 ›")
// with the computed break before the next period, a period detail page, Add Period, "Regenerate from Lesson Length…"
// (the onboarding generator `BellScheduleTemplate`), New Schedule and Delete Schedule.
//
// C1 root cause: the old content put `.toolbar { EditButton() }` on a `Group` of sections. A modifier on `Group`
// applies to EACH child, so every section added its own Edit button ("Edit Edit Edit Edit •••") and pushed Save and
// the title into the overflow. Now the only toolbar is the scaffold's (Cancel / "Bell Schedule" / Save); nothing in
// here adds toolbar items, and there is no reorder mode (periods are always shown in time order).
//
// Rules shown to the user: a period used by lessons can't be deleted (the detail page says "Used by N lessons");
// a schedule used by day changes can't be deleted; an end time at or before the start blocks saving; overlapping
// periods only warn. Logic: Packages/TimetableUI/.../Editors/BellSetDraft.swift (Linux-tested, EditorU5bTests).
// HIG: toolbars.md › Make sure the meaning of each control is clear; modality.md › "provide a single path through
//   the hierarchy"; lists-and-tables.md › disclosure indicator to drill into a row.
// APIs: Form, NavigationLink(destination:label:), Picker, DatePicker through TimeRow, Stepper through ValueStepper.
import SwiftUI
import TimetableCore
import TimetableUI

/// Opens the bell schedule editor for `timetableID` (default: the active timetable): as sheet content, or `embedded`
/// in a parent navigation stack (Settings; no own stack, Back leaves while nothing is edited).
struct BellScheduleEditorView: View {
    var timetableID: Timetable.ID?
    var embedded = false
    /// Opens the first period's detail page on appear (DEBUG screenshot route `editor.bell-period`).
    var opensFirstPeriod = false
    @Environment(AppModel.self) private var model
    @State private var defaultID = BellSchedule.ID(UUID())

    var body: some View {
        if let database = model.database,
           let timetable = timetableID.flatMap({ id in model.timetables.first { $0.id == id } }) ?? model.activeTimetable {
            BellEditorBody(timetable: timetable, database: database, fallbackID: defaultID, embedded: embedded,
                           opensFirstPeriod: opensFirstPeriod)
        } else {
            EmbeddableUnavailableView(embedded: embedded, messageKey: "editor.bell.unavailable")
        }
    }
}

private struct BellEditorBody: View {
    let timetable: Timetable
    let database: TabulaDatabase
    let fallbackID: BellSchedule.ID
    let embedded: Bool
    let opensFirstPeriod: Bool
    @Environment(AppModel.self) private var model

    private var initial: BellSetDraft {
        BellSetDraft(timetable: timetable, schedules: database.bellSchedules,
                     defaultScheduleName: model.renderer.string(forKey: "editor.bell.defaultName"), ids: { fallbackID })
    }

    var body: some View {
        let periodUsage = BellSetDraft.periodUsage(lessons: database.lessons, overrides: database.overrides,
                                                   timetableID: timetable.id)
        let scheduleUsage = BellSetDraft.scheduleUsage(overrides: database.overrides, timetableID: timetable.id)
        EmbeddableEditorScaffold(
            embedded: embedded,
            titleKey: "editor.bell.title",
            initial: initial,
            canSave: { !$0.hasBlockingIssues && !$0.defaultHasNoLessons },
            save: { draft in model.apply(.batch(draft.mutations(for: timetable), label: "bell schedule")) },
            content: { draft in
                BellFormContent(draft: draft, timetable: timetable, periodUsage: periodUsage, scheduleUsage: scheduleUsage,
                                opensFirstPeriod: opensFirstPeriod)
            })
    }
}

private struct BellFormContent: View {
    @Binding var draft: BellSetDraft
    let timetable: Timetable
    let periodUsage: [Period.ID: Int]
    let scheduleUsage: [BellSchedule.ID: Int]
    let opensFirstPeriod: Bool
    @Environment(AppModel.self) private var model
    /// The schedule shown (UI state only; `nil` = the default schedule).
    @State private var selectedID: BellSchedule.ID?
    /// `opensFirstPeriod`: pushed once on appear.
    @State private var showingFirstPeriod = false
    @State private var openedFirstPeriod = false

    private var currentID: BellSchedule.ID { selectedID.flatMap { draft.entry($0)?.id } ?? draft.defaultEntry.id }
    private var current: BellSetDraft.Entry { draft.entry(currentID) ?? draft.defaultEntry }
    private var isDefault: Bool { currentID == draft.defaultEntry.id }
    private var inUse: Set<Period.ID> { Set(periodUsage.keys) }

    var body: some View {
        scheduleSection
        if !isDefault { usedOnSection }
        periodsSection
        manageSection
    }

    // MARK: Schedule choice and name

    private func displayName(_ entry: BellSetDraft.Entry) -> String {
        EditorText.trimmedOrNil(entry.name) ?? model.renderer.string(forKey: "editor.bell.untitled")
    }

    private var scheduleSection: some View {
        Section {
            if draft.entries.count > 1 {
                Picker(selection: Binding(get: { currentID }, set: { selectedID = $0 })) {
                    ForEach(draft.entries) { entry in
                        Text(verbatim: displayName(entry)).tag(entry.id)
                    }
                } label: {
                    Text("editor.bell.schedule")
                }
            }
            LabeledTextField(titleKey: "editor.bell.name", text: Binding(
                get: { current.name },
                set: { draft.rename(currentID, to: $0) }))
        } footer: {
            if EditorText.trimmedOrNil(current.name) == nil {
                ValidationMessage(key: "editor.bell.issue.noName", severity: .hint)
            } else if isDefault {
                Text("editor.bell.default.footer")
            } else if current.weekdays.isEmpty {
                Text("editor.bell.occasional.footer")
            }
        }
    }

    private var usedOnSection: some View {
        Section {
            WeekdayChips(
                days: Weekday.week(startingAt: model.calendarContext.firstWeekday).filter { timetable.enabledDays.contains($0) },
                isOn: { current.weekdays.contains($0) },
                setOn: { day, isOn in
                    var days = current.weekdays
                    if isOn { days.insert(day) } else { days.remove(day) }
                    draft.assign(days, to: currentID)
                })
        } header: {
            Text("editor.bell.usedOn")
        }
    }

    // MARK: Periods

    private var periodsSection: some View {
        let entry = current
        let issues = BellSetDraft.issues(of: entry)
        return Section {
            ForEach(BellSetDraft.rows(of: entry)) { row in
                NavigationLink {
                    PeriodDetailView(draft: $draft, entryID: entry.id, periodID: row.id,
                                     usage: periodUsage[row.id] ?? 0)
                } label: {
                    PeriodRowLabel(row: row, issue: issues[row.id])
                }
                if let gap = row.gapAfterMinutes {
                    Text(verbatim: model.renderer.format(key: "editor.bell.breakLine", arguments: [.integer(Int64(gap))]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 40)
                }
            }
            Button {
                draft.addPeriod(to: entry.id, id: Period.ID(UUID()))
            } label: {
                Label { Text("editor.bell.addPeriod") } icon: { Image(systemName: "plus.circle") }
                    .frame(minHeight: 44, alignment: .leading)
            }
            NavigationLink {
                RegenerateView(draft: $draft, entryID: entry.id, inUse: inUse)
            } label: {
                Text("editor.bell.regenerate").frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("editor.bell.periods")
        } footer: {
            periodsFooter(issues: issues)
        }
        // On this one section, never on a group of sections (C1: a modifier on Group repeats per child).
        .navigationDestination(isPresented: $showingFirstPeriod) {
            if let first = BellSetDraft.rows(of: entry).first {
                PeriodDetailView(draft: $draft, entryID: entry.id, periodID: first.id, usage: periodUsage[first.id] ?? 0)
            }
        }
        .onAppear {
            guard opensFirstPeriod, !openedFirstPeriod else { return }
            openedFirstPeriod = true
            showingFirstPeriod = true
        }
    }

    private func periodsFooter(issues: [Period.ID: BellSetDraft.PeriodIssue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isDefault && draft.defaultHasNoLessons { Text("editor.bell.issue.noLessons") }
            if issues.values.contains(.endBeforeStart) {
                ValidationMessage(key: "editor.bell.issue.endBeforeStart")
            }
            if issues.values.contains(.overlaps) {
                Label { Text("editor.bell.issue.overlap") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            }
        }
    }

    // MARK: New / delete schedule

    private var manageSection: some View {
        let usedByChanges = scheduleUsage[currentID] ?? 0
        return Section {
            Button {
                let id = BellSchedule.ID(UUID())
                let name = model.renderer.format(key: "editor.bell.newName", arguments: [.integer(Int64(draft.entries.count + 1))])
                draft.addSchedule(copying: currentID, name: name, id: id)
                selectedID = id
            } label: {
                Label { Text("editor.bell.newSchedule") } icon: { Image(systemName: "plus.square.on.square") }
                    .frame(minHeight: 44, alignment: .leading)
            }
            if !isDefault {
                Button(role: .destructive) {
                    draft.removeVariant(currentID)
                    selectedID = nil
                } label: {
                    Label { Text("editor.bell.deleteSchedule") } icon: { Image(systemName: "trash") }
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(usedByChanges > 0)
            }
        } footer: {
            if isDefault {
                Text("editor.bell.newSchedule.footer")
            } else if usedByChanges > 0 {
                Text(verbatim: model.renderer.format(key: "editor.bell.schedule.inUse", arguments: [.integer(Int64(usedByChanges))]))
            }
        }
    }
}

// MARK: - Period row

/// "1   08:00–08:45   ›" with the period's name (or "Lunch" / "Break") underneath. One VoiceOver element.
private struct PeriodRowLabel: View {
    let row: BellSetDraft.Row
    let issue: BellSetDraft.PeriodIssue?
    @Environment(AppModel.self) private var model

    private var subtitle: Text? {
        if let label = row.period.label.flatMap(EditorText.trimmedOrNil) { return Text(verbatim: label) }
        if row.period.kind != .lesson { return Text(LocalizedStringKey(DynamicL10nKeys.periodKind(row.period.kind))) }
        return nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: row.ordinal.map { $0.formatted() } ?? "")
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(minWidth: 28, alignment: .leading)
                .accessibilityHidden(row.ordinal == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.formatter.timeRange(row.period.start, row.period.end))
                    .font(.body.monospacedDigit())
                if let subtitle {
                    subtitle.font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            switch issue {
            case .endBeforeStart?:
                Image(AppSymbol.error).foregroundStyle(Color.correction)
                    .accessibilityLabel(Text("editor.bell.issue.endBeforeStart.row"))
            case .overlaps?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .accessibilityLabel(Text("editor.bell.issue.overlap.row"))
            case nil:
                EmptyView()
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Period detail

/// Name, kind, start and end of one period; "Used by N lessons"; Delete Period (disabled with the reason while used).
private struct PeriodDetailView: View {
    @Binding var draft: BellSetDraft
    let entryID: BellSchedule.ID
    let periodID: Period.ID
    let usage: Int
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var entry: BellSetDraft.Entry? { draft.entry(entryID) }
    private var row: BellSetDraft.Row? { entry.flatMap { BellSetDraft.rows(of: $0).first { $0.id == periodID } } }

    private var period: Binding<Period> {
        Binding(
            get: { entry?.periods.first { $0.id == periodID }
                ?? Period(id: periodID, start: SlotDraft.defaultStart, end: SlotDraft.defaultEnd) },
            set: { draft.setPeriod($0, in: entryID) })
    }

    private var title: String {
        if let label = row?.period.label.flatMap(EditorText.trimmedOrNil) { return label }
        if let ordinal = row?.ordinal {
            return model.renderer.format(key: "editor.period.number", arguments: [.integer(Int64(ordinal))])
        }
        return model.renderer.string(forKey: DynamicL10nKeys.periodKind(period.wrappedValue.kind))
    }

    var body: some View {
        let issue = entry.flatMap { BellSetDraft.issues(of: $0)[periodID] }
        Form {
            Section {
                LabeledTextField(titleKey: "editor.bell.name", text: Binding(
                    get: { period.wrappedValue.label ?? "" },
                    set: { period.wrappedValue.label = EditorText.trimmedOrNil($0) == nil ? nil : $0 }))
                Picker(selection: period.kind) {
                    ForEach(PeriodKind.knownValues, id: \.self) { kind in
                        Text(LocalizedStringKey(DynamicL10nKeys.periodKind(kind))).tag(kind)
                    }
                    if !period.wrappedValue.kind.isKnown {
                        Text(verbatim: period.wrappedValue.kind.rawValue).tag(period.wrappedValue.kind)
                    }
                } label: {
                    Text("editor.bell.kind")
                }
            } footer: {
                Text("editor.bell.name.footer")
            }
            Section {
                TimeRow(titleKey: "editor.slot.start", time: period.start)
                TimeRow(titleKey: "editor.slot.end", time: period.end)
            } footer: {
                switch issue {
                case .endBeforeStart?:
                    ValidationMessage(key: "editor.bell.issue.endBeforeStart")
                case .overlaps?:
                    Label { Text("editor.bell.issue.overlap.row") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                case nil:
                    EmptyView()
                }
            }
            if usage > 0 {
                Section {
                    Label {
                        Text(verbatim: model.renderer.format(key: "editor.bell.usedByLessons", arguments: [.integer(Int64(usage))]))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    draft.removePeriod(periodID, from: entryID, locked: usage > 0 ? [periodID] : [])
                    dismiss()
                } label: {
                    Text("editor.bell.deletePeriod").frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(usage > 0)
            } footer: {
                if usage > 0 { Text("editor.bell.deletePeriod.inUse") }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Regenerate

/// "Regenerate from Lesson Length…": first start, lesson length, breaks and count (the onboarding generator), a
/// preview, then Replace Periods. Lessons keep their periods (IDs are reused in order); periods in use are kept.
private struct RegenerateView: View {
    @Binding var draft: BellSetDraft
    let entryID: BellSchedule.ID
    let inUse: Set<Period.ID>
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var edited: BellRegeneration?

    private var entry: BellSetDraft.Entry { draft.entry(entryID) ?? draft.defaultEntry }
    private var values: BellRegeneration { edited ?? BellRegeneration(entry: entry) }

    private func binding<Value>(_ path: WritableKeyPath<BellRegeneration, Value>) -> Binding<Value> {
        Binding(get: { values[keyPath: path] }, set: { newValue in
            var next = values
            next[keyPath: path] = newValue
            edited = next
        })
    }

    var body: some View {
        let minimum = BellRegeneration.minimumCount(of: entry, inUse: inUse)
        Form {
            Section {
                TimeRow(titleKey: "editor.bell.regenerate.firstStart", time: binding(\.firstStart))
                ValueStepper(titleKey: "editor.bell.regenerate.lessonMinutes", value: binding(\.lessonMinutes),
                             range: BellRegeneration.lessonMinutesRange)
                ValueStepper(titleKey: "editor.bell.regenerate.shortBreak", value: binding(\.shortBreakMinutes),
                             range: BellRegeneration.breakMinutesRange)
                ValueStepper(titleKey: "editor.bell.regenerate.longBreak", value: binding(\.longBreakMinutes),
                             range: BellRegeneration.breakMinutesRange)
                ValueStepper(titleKey: "editor.bell.regenerate.count", value: binding(\.lessonCount),
                             range: max(minimum, BellRegeneration.lessonCountRange.lowerBound)...BellRegeneration.lessonCountRange.upperBound)
            } footer: {
                if minimum > BellRegeneration.lessonCountRange.lowerBound { Text("editor.bell.regenerate.minimum.footer") }
            }
            Section {
                ForEach(Array(values.preview.enumerated()), id: \.offset) { index, time in
                    HStack(spacing: 12) {
                        Text(verbatim: (index + 1).formatted())
                            .font(.body.weight(.semibold).monospacedDigit())
                            .frame(minWidth: 28, alignment: .leading)
                        Text(verbatim: model.formatter.timeRange(time.start, time.end)).font(.body.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("editor.bell.regenerate.preview")
            }
            Section {
                Button {
                    draft.regenerate(entryID, with: values, inUse: inUse, newID: { Period.ID(UUID()) })
                    dismiss()
                } label: {
                    Text("editor.bell.regenerate.apply").frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(values.preview.isEmpty)
            } footer: {
                Text("editor.bell.regenerate.footer")
            }
        }
        .navigationTitle(Text("editor.bell.regenerate.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
