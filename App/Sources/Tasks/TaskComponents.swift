// Shared building blocks of the Tasks screens: the neutral completion control, the priority badge, the row, the
// grouped-list section header and the undo message. State and meaning come from the Linux-tested models in
// TimetableUI/Tasks (TaskRowModel, TaskListModel); these views only draw them.
// Rules: meaning is never carried by colour alone (checkmark shape, strikethrough, icon + text badges), every control
// is at least 44 pt, texts wrap at accessibility Dynamic Type sizes. Correction red marks overdue only (D1).
// HIG (apple-design references): lists-and-tables.md (a row is one selectable unit; secondary info is subordinate),
// toggles.md (a state is not shown by colour alone), buttons.md (44 pt targets).
// APIs: Button, ZStack, Circle().strokeBorder, @ScaledMetric (property wrapper), Label, Capsule().fill(.regularMaterial),
//       accessibilityAddTraits(.isHeader), accessibilityValue(_:).
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

/// The round completion control (Phase 4U U1, Opus review H7 / C2): a neutral ring in the secondary-label colour when
/// open (≥ 3:1 non-text contrast on white and dark cards, DesignTokensTests), a filled disc with a checkmark in the
/// tint (ink) when done. The subject is not drawn on the ring: a red, green or yellow ring read as "overdue",
/// "done" or nothing (yellow measured 1.74:1); the row shows the subject as its own tile. `subject` is kept for callers.
struct TaskCompletionControl: View {
    let isCompleted: Bool
    let subject: SubjectSummary?
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 28

    var body: some View {
        Button(action: action) {
            ZStack {
                if isCompleted {
                    Circle().fill(.tint)
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.45, weight: .bold))
                        .foregroundStyle(Color.onInk)
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 2)
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(catalogKey: isCompleted ? "tasks.action.reopen" : "tasks.action.complete"))
    }
}

/// "High" / "Urgent": icon + text in a capsule (shape and words carry the meaning; the outline is ink for urgent, grey
/// for high, because red is reserved for overdue).
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
            .overlay(Capsule().strokeBorder(row.priority == .urgent ? Color.ink : Color.secondary, lineWidth: 1.5))
            .foregroundStyle(.primary)
        }
    }
}

/// The subject as the small tile of the widgets plus its name (H7). The tile scales with text up to a cap.
private struct TaskSubjectLine: View {
    let subject: SubjectSummary
    @ScaledMetric(relativeTo: .subheadline) private var tile: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            SubjectBadge(subject: subject, size: min(tile, 28))
            Text(verbatim: subject.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The text part of a task row (title, subject, due, indicators). Hidden fields are absent, not dashed. `section`:
/// the list section the row sits in; a due label that equals it ("Today" under Today) is left out (M10).
struct TaskRowText: View {
    let row: TaskRowModel
    var section: TaskSection?
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
                TaskSubjectLine(subject: subject)
            }
            dueLine
            indicators
        }
    }

    @ViewBuilder
    private var dueLine: some View {
        switch row.dueLine(in: section) {
        case .full(let due)?:
            Label {
                Text(verbatim: due.text(renderer: model.renderer))
            } icon: {
                Image(row.isOverdue ? AppSymbol.overdue : AppSymbol.date)
            }
            .font(.subheadline)
            .foregroundStyle(row.isOverdue ? Color.correction : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .timeOnly(let time)?:
            Label {
                Text(verbatim: model.formatter.time(time))
            } icon: {
                Image(AppSymbol.time)
            }
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
        case nil:
            EmptyView()
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
                        Image(AppSymbol.subtasks)
                    }
                }
                if row.attachmentCount > 0 {
                    Image(AppSymbol.attachment)
                }
                if row.repeats {
                    Image(AppSymbol.repeats)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// One list row: completion control + the text. The control completes the task, the rest of the row opens the detail
/// (two sibling buttons, never nested: F15). VoiceOver reads the whole row as one sentence; the list adds the custom
/// actions (open, complete / reopen, delete).
struct TaskRowView: View {
    let row: TaskRowModel
    var section: TaskSection?
    let onOpen: () -> Void
    let onToggle: () -> Void

    init(row: TaskRowModel, section: TaskSection? = nil, onOpen: @escaping () -> Void, onToggle: @escaping () -> Void) {
        self.row = row
        self.section = section
        self.onOpen = onOpen
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            TaskCompletionControl(isCompleted: row.isCompleted, subject: row.subject, action: onToggle)
                .accessibilityHidden(true)
            Button(action: onOpen) {
                TaskRowText(row: row, section: section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }
}

/// Header of a list section: the title and the count (the count is a number in its own `Text`, never glued to the
/// translated word). Overdue is the only one in correction red, with its triangle so colour is not the only cue.
struct TaskSectionHeader: View {
    let section: TaskSection
    let count: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let isOverdue = section == .overdue
        HStack(spacing: 6) {
            if isOverdue { Image(AppSymbol.overdue) }
            Text(LocalizedStringKey(section.titleKey))
            Text(verbatim: count.formatted())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isOverdue ? Color.correction : Color.secondary)
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(section.titleKey)))
        .accessibilityValue(Text(verbatim: model.renderer.format(key: "tasks.section.count", arguments: [.integer(Int64(count))])))
        .accessibilityAddTraits(.isHeader)
    }
}

/// "Marked as done · Undo" at the bottom of the list after a completion (F15: undo for an accidental tap).
struct TaskUndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("tasks.toast.completed")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("tasks.toast.undo")
                    .fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}
