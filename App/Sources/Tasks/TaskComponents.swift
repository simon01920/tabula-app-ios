// Shared building blocks of the Tasks screens: the subject-coloured completion control, the priority badge, the
// segment chips and the row. State and meaning come from the Linux-tested models in TimetableUI/Tasks
// (TaskRowModel, TaskSegmentCounts); these views only draw them.
// Rules: meaning is never carried by colour alone (checkmark shape, strikethrough, icon + text badges), every control
// is at least 44 pt, texts wrap at accessibility Dynamic Type sizes.
// APIs: Button, ZStack, Circle().strokeBorder, @ScaledMetric (property wrapper), ScrollView(.horizontal),
//       buttonStyle(.bordered/.borderedProminent), buttonBorderShape(.capsule), controlSize(.large), Label,
//       Capsule().fill(.regularMaterial), accessibilityAddTraits(.isSelected).
import SwiftUI
import TimetableCore
import TimetableUI

extension Text {
    /// A localized text for a catalog key chosen at runtime (for example by a ternary). `Text(cond ? "a" : "b")`
    /// may type the literals as `String` and show them verbatim, so keys picked at runtime go through here.
    init(catalogKey key: String) {
        self.init(LocalizedStringKey(key))
    }
}

/// The round completion control in the subject colour: an outline when open, a filled disc with a checkmark when done.
struct TaskCompletionControl: View {
    let isCompleted: Bool
    let subject: SubjectSummary?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 28

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(tint, lineWidth: 2.5)
                if needsOutline {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1).padding(-1.5)
                }
                if isCompleted {
                    Circle().fill(tint)
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.45, weight: .bold))
                        .foregroundStyle(checkColor)
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(catalogKey: isCompleted ? "tasks.action.reopen" : "tasks.action.complete"))
    }

    private var style: LessonTileStyle? { subject.map { LessonTileStyle(color: $0.color) } }
    private var tint: Color { subject.map { Color($0.color) } ?? Color.secondary }
    private var checkColor: Color { style.map { Color($0.foreground) } ?? Color.white }
    private var needsOutline: Bool { style?.needsOutline(isDark: colorScheme == .dark) ?? false }
}

/// "High" / "Urgent": icon + text in a capsule (shape and words carry the meaning, the tint is secondary).
struct TaskPriorityBadge: View {
    let row: TaskRowModel

    var body: some View {
        if let key = row.priorityBadgeKey {
            Label {
                Text(LocalizedStringKey(key))
            } icon: {
                Image(systemName: row.prioritySymbolName)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(row.priority == .urgent ? Color.red : Color.orange, lineWidth: 1.5))
            .foregroundStyle(.primary)
        }
    }
}

/// The text part of a task row (title, subject, relative due, indicators). Hidden fields are absent, not dashed.
struct TaskRowText: View {
    let row: TaskRowModel
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: row.title)
                .font(.body)
                .strikethrough(row.isCompleted)
                .foregroundStyle(row.isCompleted ? Color.secondary : Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subject = row.subject {
                Text(verbatim: subject.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let due = row.due {
                Label {
                    Text(verbatim: due.text(renderer: model.renderer))
                } icon: {
                    Image(systemName: row.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                }
                .font(.subheadline)
                .foregroundStyle(row.isOverdue ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            indicators
        }
    }

    @ViewBuilder
    private var indicators: some View {
        if row.showsPriorityBadge || row.subtasksTotal > 0 || row.attachmentCount > 0 || row.repeats {
            HStack(spacing: 10) {
                TaskPriorityBadge(row: row)
                if row.subtasksTotal > 0 {
                    Label {
                        Text(verbatim: model.renderer.format(key: "tasks.row.subtasks", arguments: [
                            .integer(Int64(row.subtasksDone)), .integer(Int64(row.subtasksTotal)),
                        ]))
                    } icon: {
                        Image(systemName: "checklist")
                    }
                }
                if row.attachmentCount > 0 {
                    Image(systemName: "paperclip")
                }
                if row.repeats {
                    Image(systemName: "repeat")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// One list row: completion control + the text (tapping the text opens the detail). VoiceOver reads the whole row as
/// one sentence; the list adds the custom actions (open, complete / reopen, delete).
struct TaskRowView: View {
    let row: TaskRowModel
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            TaskCompletionControl(isCompleted: row.isCompleted, subject: row.subject, action: onToggle)
                .accessibilityHidden(true)
            Button(action: onOpen) {
                TaskRowText(row: row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }
}

/// Today / Upcoming / Overdue / Completed as capsule buttons with counts; Overdue turns red and gets a warning icon
/// while it has tasks. Scrolls horizontally when the labels do not fit (long languages, large Dynamic Type).
struct TaskSegmentBar: View {
    let counts: TaskSegmentCounts
    @Binding var selection: TaskSegment
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskSegment.allCases, id: \.self) { segment in
                    chip(segment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(_ segment: TaskSegment) -> some View {
        let isSelected = segment == selection
        let isAlert = segment == .overdue && counts.overdue > 0
        let title = model.renderer.format(key: segment.countedTitleKey, arguments: [.integer(Int64(counts[segment]))])
        let button = Button {
            selection = segment
        } label: {
            if isAlert {
                Label { Text(verbatim: title) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            } else {
                Text(verbatim: title)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(isAlert ? Color.red : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
