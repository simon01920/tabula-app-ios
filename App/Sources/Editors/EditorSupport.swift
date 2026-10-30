// Shared building blocks of the editors (stage B3): the Cancel/Save sheet scaffold with dirty-state confirmation,
// the inline result of `AppModel.apply`, labelled inputs, date/time rows and the impact-confirmation sheet.
// Phase 4U U1: Save stays disabled until the draft can be saved; hints (what is missing) show from the start, errors
// (a wrong value) after the first edit (M5, `ValidationMessage`, `\.editorErrorsVisible`, `ValidationVisibility`);
// the title field of an editor is `EditorTitleField` (M6).
//
// Draft pattern (no `State(initialValue:)` in initialisers, which is unverified with the Xcode 27 macro-based
// @State): the scaffold keeps `edited: Draft?`, `nil` meaning "unchanged = initial". Content edits through a
// Binding whose getter falls back to `initial`. Dirty = `edited != nil && edited != initial`.
//
// APIs: NavigationStack, Form, Section, toolbar(content:), ToolbarItem(placement: .cancellationAction /
//   .confirmationAction), interactiveDismissDisabled(_:), confirmationDialog(_:isPresented:titleVisibility:actions:),
//   Binding(get:set:), LabeledContent(_:content:), DatePicker(selection:displayedComponents:label:),
//   environment(\.timeZone / \.calendar), presentationDetents(_:), ContentUnavailableView.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

/// An empty prompt: inputs show their label next to the field and never placeholder text (field rule).
var emptyPrompt: LocalizedStringKey { "" }

// MARK: - Scaffold

/// A sheet with Cancel / Save, a Form for `content` and a discard confirmation when there are unsaved edits.
struct EditorScaffold<Draft: Equatable, Content: View>: View {
    let titleKey: LocalizedStringKey
    let initial: Draft
    let canSave: (Draft) -> Bool
    /// Applies the draft; `nil` = nothing to apply. `.applied` dismisses the sheet (after an acknowledgement when the
    /// change introduced validation warnings).
    let save: (Draft) -> ApplyResult?
    /// Work outside the draft is still running (e.g. an attachment copy): Save and swipe-to-dismiss are disabled.
    var isBusy = false
    /// The initial draft already holds typed input (a quick-entry draft handed over): treat it as edited.
    var startsDirty = false
    /// The confirmation button's label: "Save", or "Add" for the quick-entry sheet.
    var confirmKey: LocalizedStringKey = "editor.common.save"
    @ViewBuilder let content: (Binding<Draft>) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var edited: Draft?
    @State private var result: ApplyResult?
    @State private var confirmingDiscard = false
    @State private var warningLines: [ApplyWarningLine] = []
    @State private var showingWarnings = false
    @Environment(AppModel.self) private var model

    private var current: Draft { edited ?? initial }
    private var isDirty: Bool { startsDirty || (edited != nil && edited != initial) }
    /// M5 (Phase 4U U1; HIG entering-data.md "Dynamically validate field values"): hints (what is missing) show from
    /// the start next to the disabled Save; errors (a wrong value) only after the first edit (`ValidationVisibility`).
    private var errorsVisible: Bool { ValidationVisibility.errorsVisible(hasEdited: edited != nil) }

    private var binding: Binding<Draft> {
        Binding(get: { edited ?? initial }, set: { edited = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    ApplyResultSection(result: result)
                }
                content(binding)
            }
            .environment(\.editorErrorsVisible, errorsVisible)
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if isDirty { confirmingDiscard = true } else { dismiss() }
                    } label: {
                        Text("editor.common.cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Disabled until the draft can be saved; the always-visible hints say what is missing (Opus §3).
                    Button {
                        commit()
                    } label: {
                        Text(confirmKey)
                    }
                    .disabled(isBusy || !canSave(current))
                }
            }
            .confirmationDialog("editor.common.discard.title", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("editor.common.discard", role: .destructive) { dismiss() }
                Button("editor.common.keepEditing", role: .cancel) {}
            } message: {
                Text("editor.common.discard.message")
            }
        }
        .alert("editor.warnings.title", isPresented: $showingWarnings) {
            Button("editor.warnings.ok") { dismiss() }
        } message: {
            Text(verbatim: warningText)
        }
        // A swipe-down would lose edits silently: while dirty, only Cancel (with confirmation) or Save leave the sheet.
        .interactiveDismissDisabled(isDirty || isBusy)
        // Same rule for notification deep links (QA fix Q6): an editor with unsaved edits or a running copy is never
        // closed for one; the link is shown after the user saves or cancels (RootPresentation.swift).
        .protectsUnsavedWork(isDirty || isBusy)
    }

    private var warningText: String {
        let lines = warningLines.map { line -> String in
            if line.takesCount {
                return model.renderer.format(key: line.messageKey, arguments: [.integer(Int64(line.count))])
            }
            let message = model.renderer.string(forKey: line.messageKey)
            guard let entityKey = line.entityKey else { return message }
            return model.renderer.format(key: "editor.warnings.line",
                                         arguments: [.text(model.renderer.string(forKey: entityKey)), .text(message)])
        }
        return lines.joined(separator: "\n")
    }

    private func commit() {
        guard !isBusy, canSave(current), let outcome = save(current) else { return }
        if case .applied(let warnings) = outcome {
            // The change is stored; warnings never block (spec), but the user sees them before the sheet closes.
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

// MARK: - Result and unavailable states

/// The inline error of a refused `apply` (errors block; the sheet stays open so nothing is lost).
struct ApplyResultSection: View {
    let result: ApplyResult
    @Environment(AppModel.self) private var model

    var body: some View {
        switch result {
        case .applied:
            EmptyView()
        case .rejected(let errors):
            Section {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.renderer.string(issue.entityTypeName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: model.renderer.string(issue.message))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Label { Text("editor.error.rejected.title") } icon: { Image(systemName: "exclamationmark.octagon.fill") }
                    .foregroundStyle(.red)
            }
        case .readOnly:
            Section {
                Label { Text("editor.error.readOnly") } icon: { Image(systemName: "lock.fill") }
            }
        case .failed:
            Section {
                Label { Text("editor.error.failed") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundStyle(.red)
            }
        }
    }
}

/// An editor opened for something that does not exist (e.g. no timetable yet): a message and Close.
struct EditorUnavailableView: View {
    let messageKey: LocalizedStringKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text("editor.unavailable.title") } icon: { Image(systemName: "square.and.pencil") }
            } description: {
                Text(messageKey)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
        }
    }
}

// MARK: - Validation (M5)

private struct EditorErrorsVisibleKey: EnvironmentKey {
    /// Outside an `EditorScaffold` errors always show (the previous behaviour).
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `false` until the user edits the draft (set by `EditorScaffold` from `ValidationVisibility`). Gates `.error`
    /// messages only; hints are always visible. Editors with custom message views can read it too.
    var editorErrorsVisible: Bool {
        get { self[EditorErrorsVisibleKey.self] }
        set { self[EditorErrorsVisibleKey.self] = newValue }
    }
}

/// One inline validation message (icon + text, never colour alone; M5, `ValidationVisibility`).
/// `.hint` = what is still missing ("Enter a title to save"): footnote in `pencil`, visible from the moment the editor
/// opens, next to the disabled Save. `.error` = a value that is wrong ("The end is before the start"): correction red,
/// shown after the first edit.
struct ValidationMessage: View {
    let key: String
    var severity: ValidationSeverity = .error
    @Environment(\.editorErrorsVisible) private var errorsVisible

    var body: some View {
        if ValidationVisibility.isShown(severity, hasEdited: errorsVisible) {
            Label {
                Text(LocalizedStringKey(key))
            } icon: {
                Image(severity == .error ? AppSymbol.warning : AppSymbol.info)
            }
            .font(.footnote)
            .foregroundStyle(severity == .error ? Color.correction : Color.pencil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Inputs

/// The main title / name field of an editor (M6, Phase 4U U1): a leading-aligned `TextField` in `.title3` that looks
/// like a field, with a prompt in the system placeholder colour (HIG text-fields.md "Show a hint in a text field to
/// help communicate its purpose") and its missing-title hint directly under it in footnote `pencil` text, visible from
/// the moment the editor opens while the title is empty (it explains the disabled Save, M5). The prompt is the field's purpose ("Exam title"), not data, so the
/// PRODUCT.md field rule ("no placeholders" for empty optional values in summaries) is untouched: titles are required.
/// VoiceOver reads the prompt key as the field's label.
struct EditorTitleField: View {
    /// Catalog key of the prompt and accessibility label ("Exam title").
    let promptKey: LocalizedStringKey
    @Binding var text: String
    var axis: Axis = .horizontal
    /// Catalog key of the hint shown while the title is missing (`nil` = no hint).
    var missingHintKey: String?
    /// Focus binding of the quick-entry sheet (the title is focused on open); `nil` elsewhere.
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field
            if let missingHintKey, EditorText.trimmedOrNil(text) == nil {
                ValidationMessage(key: missingHintKey, severity: .hint)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(text: $text, prompt: Text(promptKey), axis: axis) { Text(promptKey) }
            .font(.title3)
            .multilineTextAlignment(.leading)
        if let focus { base.focused(focus) } else { base }
    }
}

/// A text input with a visible label (right-aligned value, stacks at large Dynamic Type sizes). No placeholder text:
/// an empty enabled field is simply an empty input.
struct LabeledTextField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        LabeledContent {
            TextField(text: $text, prompt: Text(emptyPrompt), axis: axis) { Text(titleKey) }
                .multilineTextAlignment(.trailing)
        } label: {
            Text(titleKey)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A time-of-day row (hour and minute) bridged to `LocalTime`.
struct TimeRow: View {
    let titleKey: LocalizedStringKey
    @Binding var time: LocalTime
    @Environment(AppModel.self) private var model

    var body: some View {
        DatePicker(selection: Binding(
            get: { LocalDateBridge.instant(LocalDate(year: 2001, month: 1, day: 1) ?? .earliest, time) },
            set: { time = LocalDateBridge.time($0) }
        ), displayedComponents: .hourAndMinute) {
            Text(titleKey)
        }
        .environment(\.timeZone, LocalDateBridge.timeZone)
        .environment(\.calendar, LocalDateBridge.calendar(locale: model.formatter.locale))
        .hourCycleLocale(model.formatter.locale)   // D4 / H1: the picker shows the app's 12/24-hour clock
    }
}

/// A date row bridged to `LocalDate`.
struct DateRow: View {
    let titleKey: LocalizedStringKey
    @Binding var date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        DatePicker(selection: Binding(
            get: { LocalDateBridge.instant(date) },
            set: { date = LocalDateBridge.date($0, fallback: date) }
        ), displayedComponents: .date) {
            Text(titleKey)
        }
        .environment(\.timeZone, LocalDateBridge.timeZone)
        .environment(\.calendar, LocalDateBridge.calendar(locale: model.formatter.locale))
    }
}

/// A stepper whose value is shown next to the title (44 pt target from the system control).
struct ValueStepper: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            LabeledContent {
                Text(verbatim: value.formatted())
            } label: {
                Text(titleKey)
            }
        }
        .accessibilityValue(Text(verbatim: value.formatted()))
    }
}

// MARK: - Slot rows

/// The rows of a time slot (period picker + span, or start / end times) for the lesson and extra-lesson editors.
/// `schedule` is the timetable's default bell schedule (`nil` for free-form timetables: times only).
struct SlotEditorRows: View {
    @Binding var slot: SlotDraft
    let schedule: BellSchedule?
    let timetable: Timetable
    @Environment(AppModel.self) private var model

    private var labels: EditorLabels { EditorLabels(model: model) }

    var body: some View {
        if schedule != nil {
            Picker(selection: Binding(get: { slot.mode }, set: { slot.setMode($0, schedule: schedule) })) {
                Text("editor.slot.mode.period").tag(SlotDraft.Mode.period)
                Text("editor.slot.mode.time").tag(SlotDraft.Mode.time)
            } label: {
                Text("editor.slot.mode")
            }
            .pickerStyle(.segmented)
        }
        switch slot.mode {
        case .period:
            let periods = SlotDraft.lessonPeriods(of: schedule)
            Picker(selection: $slot.periodID) {
                if slot.periodID == nil { Text("editor.slot.period.choose").tag(Period.ID?.none) }
                ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                    Text(verbatim: labels.period(period, ordinal: index + 1)).tag(Period.ID?.some(period.id))
                }
            } label: {
                Text("editor.slot.period")
            }
            let maxSpan = slot.maxSpan(in: schedule)
            if maxSpan > 1 {
                ValueStepper(titleKey: "editor.slot.span", value: $slot.span, range: 1...maxSpan)
            }
        case .time:
            TimeRow(titleKey: "editor.slot.start", time: $slot.start)
            TimeRow(titleKey: "editor.slot.end", time: $slot.end)
        }
    }
}

// MARK: - Names

/// Display names of days, weeks and periods of one timetable.
@MainActor
struct EditorLabels {
    let renderer: LocalizedTextRenderer

    init(model: AppModel) { renderer = model.renderer }

    func day(_ key: DayKey, in timetable: Timetable) -> String {
        switch key {
        case .weekday(let weekday):
            return renderer.formatter.weekdayName(weekday)
        case .cycleDay(let index):
            if case .dayCycle(let cycle) = timetable.rotation, let label = DayChoices.label(at: index, in: cycle.labels) {
                return label
            }
            return renderer.format(key: "editor.cycleDay.name", arguments: [.integer(Int64(index))])
        }
    }

    func week(_ index: Int, in timetable: Timetable) -> String {
        if case .weekCycle(let cycle) = timetable.rotation, let label = DayChoices.label(at: index, in: cycle.labels) {
            return label
        }
        return renderer.format(key: "editor.cycleWeek.name", arguments: [.integer(Int64(index))])
    }

    /// "Period 3 · 9:55 – 10:40" (label instead of the number when the period has one).
    func period(_ period: Period, ordinal: Int?) -> String {
        let times = renderer.formatter.timeRange(period.start, period.end)
        let name: String
        if let label = EditorText.trimmedOrNil(period.label ?? "") {
            name = label
        } else if let ordinal {
            name = renderer.format(key: "editor.period.number", arguments: [.integer(Int64(ordinal))])
        } else {
            return times
        }
        return renderer.format(key: "editor.period.withTimes", arguments: [.text(name), .text(times)])
    }
}

// MARK: - Colour bridge

enum ColorBridge {
    /// The sRGB `ColorValue` of a SwiftUI colour from the colour picker.
    static func value(of color: Color) -> ColorValue {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ component: CGFloat) -> UInt8 { UInt8(max(0, min(255, (component * 255).rounded()))) }
        return ColorValue(red: byte(red), green: byte(green), blue: byte(blue), alpha: byte(alpha))
    }
}

// MARK: - Impact confirmation

/// What a destructive action removes, as counted rows ("12 lessons").
struct ImpactRow: Identifiable {
    let id: String
    /// Catalog key with one `%lld` (plural variations).
    let key: String
    let count: Int
}

/// A confirmation sheet that lists what will be removed (a plain confirmation dialog cannot show a list).
struct ImpactConfirmation: View {
    let title: LocalizedStringKey
    let subjectName: String
    let rows: [ImpactRow]
    let note: LocalizedStringKey?
    let action: LocalizedStringKey
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: subjectName).font(.headline)
                }
                let visibleRows = rows.filter { $0.count > 0 }
                if !visibleRows.isEmpty {
                    Section {
                        ForEach(visibleRows) { row in
                            Text(verbatim: model.renderer.format(key: row.key, arguments: [.integer(Int64(row.count))]))
                        }
                    } header: {
                        Text("editor.impact.removes")
                    }
                }
                if let note {
                    Section { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Button(role: .destructive) {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text(action).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("editor.common.cancel") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Seed helpers for launch routes

/// Picks seed data for routes opened without ids (`-TabulaScreen editor.…`).
@MainActor
enum EditorSeedPicker {
    static func firstLesson(in model: AppModel) -> Lesson? {
        guard let timetable = model.activeTimetable else { return nil }
        let lessons = (model.database?.lessons ?? []).filter { !$0.isDeleted && $0.timetableID == timetable.id }
        return lessons.sorted { ($0.occurrence.day, $0.id) < ($1.occurrence.day, $1.id) }.first
    }

    static func firstSubject(in model: AppModel) -> Subject? {
        guard let timetable = model.activeTimetable else { return nil }
        guard let database = model.database else { return nil }
        return SubjectOrder.live(database, timetableID: timetable.id, locale: model.formatter.locale).first
    }
}
