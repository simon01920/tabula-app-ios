// The grid as a list (accessibility text sizes up to AX5, or columns too narrow): one section per day, lessons in
// period order (a double period once), free periods as "add" rows, break/lunch separators only between items.
// Built from `GridPresentation.listSections` (TimetableUI, Linux-tested). U4: the lesson in progress shows the
// highlighter "NOW" tag; today's header tag is ink, not red (red = cancelled / overdue only, UX plan D1).
// APIs: List, Section(content:header:), Button, Label(title:icon:), accessibilityElement(children:),
//       accessibilityHint(_:), listStyle(.insetGrouped).
import SwiftUI
import TimetableCore
import TimetableUI

struct GridListView: View {
    let layout: TimetableCore.GridLayout
    let strip: WeekStripModel
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(GridPresentation.listSections(layout)) { section in
                Section {
                    if section.items.isEmpty {
                        Label { Text(emptyKey(section.column)) } icon: { Image(systemName: emptySymbol(section.column)) }
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.items) { item in
                        row(item, column: section.column)
                    }
                    ForEach(GridPresentation.unplaced(layout, column: section.column)) { lesson in
                        Button { onOpen(lesson) } label: {
                            LessonRowView(lesson: lesson, reasons: reasons[lesson.id] ?? [], visibility: timetable.fieldVisibility)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    header(section.column)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func row(_ item: GridListItem, column: TimetableCore.GridLayout.Column) -> some View {
        switch item {
        case let .lesson(cell, _):
            Button { onOpen(cell.entry) } label: {
                LessonRowView(lesson: cell.entry, reasons: reasons[cell.entry.id] ?? [],
                              visibility: timetable.fieldVisibility, isInConflict: cell.isInConflict,
                              isCurrent: NowLinePresentation.isCurrent(cell.entry, today: today, minuteOfDay: nowMinute))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("timetable.a11y.openHint"))
        case let .free(columnIndex, row):
            Button {
                if let target = QuickAddTarget.make(layout: layout, column: columnIndex, row: row.index, timetable: timetable) {
                    onAdd(target)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("timetable.list.free")
                            .foregroundStyle(Color.primary)
                        Text(verbatim: model.formatter.timeRange(row.start, row.end))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: GridPresentation.freeSlotAccessibilityLabel(column: column, row: row,
                                                                                         renderer: model.renderer)))
            .accessibilityHint(Text("timetable.a11y.addHint"))
            .accessibilityAddTraits(.isButton)
        case let .breakRow(row):
            Label {
                Text(LocalizedStringKey(row.kind == .lunch ? "timetable.list.lunch" : "timetable.list.break"))
            } icon: {
                Image(systemName: row.kind == .lunch ? "fork.knife" : "cup.and.saucer")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func header(_ column: TimetableCore.GridLayout.Column) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: model.formatter.date(column.date, style: .full))
            if let day = strip.days.first(where: { $0.date == column.date }) {
                if day.isToday {
                    Text("timetable.list.todayTag")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .foregroundStyle(TimetableColor.onInk)
                        .background(Capsule().fill(TimetableColor.ink))
                }
                if let cycle = day.cycleDay {
                    Text(verbatim: cycle.text(renderer: model.renderer))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func emptyKey(_ column: TimetableCore.GridLayout.Column) -> LocalizedStringKey {
        if column.activeBreakID != nil { return "timetable.day.holiday" }
        if column.cancellingOverrideID != nil { return "timetable.day.cancelled" }
        return "timetable.day.noLessons"
    }

    private func emptySymbol(_ column: TimetableCore.GridLayout.Column) -> String {
        if column.activeBreakID != nil { return "beach.umbrella" }
        if column.cancellingOverrideID != nil { return "xmark.circle" }
        return "moon.zzz"
    }
}
