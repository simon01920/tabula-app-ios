// The import preview (PHASE7_PLAN decision 4): what arrives, then the choice. Shared text is the sender's data and is
// shown verbatim (never as a key or format). Field rule: rows without content are absent (no tasks → no tasks row,
// no conflicts → no conflicts section, a schedule without lesson periods → just its name).
// Buttons live in the bottom safe-area inset: "Add as New Timetable" (prominent, the default) and "Replace “…”"
// (destructive role → an alert that names what goes and where the backup copy is kept).
// APIs: View.safeAreaInset(edge:), Button(role: .destructive), View.alert(_:isPresented:actions:message:),
//       LabeledContent, Label(title:icon:).
// Phase 10 WP3 (B4): one import at a time. `isImporting` is set before the backup copy and the apply, both buttons
// are disabled while it is set, and a second tap (or the Replace alert confirming late) does nothing; it is cleared
// only when the import fails, so the sheet closing after a success cannot be followed by a duplicate.
import SwiftUI
import TimetableCore
import TimetableUI

struct ShareImportPreview: View {
    let resolved: ResolvedShare
    let profile: UserProfile?
    /// Called after a successful import (`true`) — the caller closes the sheet.
    let onFinish: (Bool) -> Void

    @Environment(AppModel.self) private var model
    @State private var confirmingReplace = false
    @State private var problemKey: String?
    @State private var isImporting = false

    private var summary: ShareImportSummary { resolved.summary }

    /// The timetable "Replace" would remove (the active one); `nil` when there is none (first launch, onboarding).
    private var replaceTarget: Timetable? { model.activeTimetable }

    private var canAdd: Bool {
        guard let database = model.database else { return true }
        return TimetableManagement.canAdd(to: database, limit: model.entitlements.limit(.maxTimetables))
    }

    private var title: String {
        guard let emoji = summary.emoji, !emoji.isEmpty else { return summary.name }
        return model.renderer.format(key: "timetable.title.withEmoji", arguments: [.text(emoji), .text(summary.name)])
    }

    var body: some View {
        Form {
            Section {
                Text(verbatim: title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Label {
                    Text(verbatim: count("share.preview.lessons", summary.lessonCount))
                } icon: { Image(AppSymbol.time) }
                if summary.includesTasks, summary.taskCount > 0 {
                    Label { Text(verbatim: count("share.preview.tasks", summary.taskCount)) } icon: { Image(AppSymbol.task) }
                }
                if summary.includesTasks, summary.examCount > 0 {
                    Label { Text(verbatim: count("share.preview.exams", summary.examCount)) } icon: { Image(AppSymbol.exam) }
                }
            }

            if summary.conflictCount > 0 || !summary.warnings.isEmpty {
                Section {
                    if summary.conflictCount > 0 {
                        Label {
                            Text(verbatim: count("share.preview.conflicts", summary.conflictCount))
                        } icon: { Image(AppSymbol.warning).foregroundStyle(Color.correction) }
                    }
                    ForEach(summary.warnings, id: \.self) { warning in
                        Label { Text(verbatim: model.renderer.string(warning.message)) } icon: { Image(AppSymbol.info) }
                    }
                } header: {
                    Text("share.preview.attention")
                }
            }

            if !summary.subjectNames.isEmpty {
                Section {
                    ForEach(Array(summary.subjectNames.enumerated()), id: \.offset) { _, name in
                        Text(verbatim: name)
                    }
                } header: {
                    Text(verbatim: count("share.preview.subjects", summary.subjectNames.count))
                }
            }

            ForEach(Array(summary.bellSchedules.enumerated()), id: \.offset) { _, schedule in
                Section {
                    ForEach(Array(schedule.periods.enumerated()), id: \.offset) { index, period in
                        LabeledContent {
                            Text(verbatim: model.formatter.timeRange(period.start, period.end)).monospacedDigit()
                        } label: {
                            Text(verbatim: (index + 1).formatted(.number.locale(model.formatter.locale)))
                        }
                    }
                } header: {
                    Text(verbatim: model.renderer.format(key: "share.preview.bellSchedule", arguments: [.text(schedule.name)]))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actions }
        .alert(Text(verbatim: replaceText("share.preview.replace.title")), isPresented: $confirmingReplace) {
            Button(role: .destructive) { importShared(replacing: replaceTarget?.id) } label: {
                Text("share.preview.replace.confirm")
            }
            Button(role: .cancel) { } label: { Text("editor.common.cancel") }
        } message: {
            Text(verbatim: replaceText("share.preview.replace.message"))
        }
        .alert(Text("share.import.error.title"), isPresented: Binding(get: { problemKey != nil }, set: { if !$0 { problemKey = nil } })) {
            Button { } label: { Text("editor.warnings.ok") }
        } message: {
            if let problemKey { Text(LocalizedStringKey(problemKey)) }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { importShared(replacing: nil) } label: {
                Text("share.preview.add")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .onInkLabel()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd || model.isReadOnly || isImporting)
            if let target = replaceTarget {
                Button(role: .destructive) { confirmingReplace = true } label: {
                    Text(verbatim: model.renderer.format(key: "share.preview.replace", arguments: [.text(target.name)]))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.isReadOnly || isImporting)
            }
            if !canAdd, let target = replaceTarget {
                Text(verbatim: model.renderer.format(key: "share.preview.freeLimit", arguments: [.text(target.name)]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Import

    private func importShared(replacing: Timetable.ID?) {
        guard !isImporting else { return }   // B4: a second tap must not add a second copy
        isImporting = true
        if replacing != nil {
            // The automatic copy comes first; no copy → nothing is replaced (same rule as Settings › Backup).
            guard let current = model.database,
                  (try? BackupFolder.write(.make(from: current, createdAt: model.now), label: "pre-import",
                                           in: model.environment.backupDirectory)) != nil else {
                problemKey = "settings.backup.error.copyFailed"
                isImporting = false
                return
            }
        }
        let mutation = DatabaseMutation.importShared(resolved.payload, replacing: replacing, profile: profile,
                                                     startsFromScratch: model.database == nil)
        switch model.apply(mutation) {
        case .applied:
            onFinish(true)   // stays `isImporting`: the sheet is closing
        case .rejected, .readOnly, .failed:
            problemKey = "share.preview.error.apply"
            isImporting = false
        }
    }

    // MARK: Text

    private func count(_ key: String, _ value: Int) -> String {
        model.renderer.format(key: key, arguments: [.integer(Int64(value))])
    }

    private func replaceText(_ key: String) -> String {
        model.renderer.format(key: key, arguments: [.text(replaceTarget?.name ?? "")])
    }
}
