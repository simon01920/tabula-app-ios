// Classic periods × days grid (route `timetable.grid`), drawn from `GridLayout`:
// - day headers pinned above the scroll view (aligned with the columns, today marker + change dot), the period column
//   on the leading edge with lesson numbers and times (no horizontal scrolling: 5/6/7 columns share the width, so the
//   period column is always visible);
// - cells span rows (double periods include the break between), break/lunch rows are thin bands, holidays shade
//   their column, free lesson slots are dashed and tappable (quick add);
// - short names/emoji in cells (user short name, else the name, scaled down), status icon + conflict icon;
// - at accessibility text sizes, or when the columns would be narrower than `GridMode.minimumColumnWidth`, the same
//   layout is shown as a list (`GridListView`).
// VoiceOver: cells read "<date>: <lesson sentence>" column by column (sort priority), free slots read
// "<date>, period n, <time>, free" with the hint "Adds a lesson".
// APIs: GeometryReader, ScrollView, ZStack + frame/offset, RoundedRectangle.strokeBorder(style:), StrokeStyle(dash:),
//       accessibilitySortPriority(_:), accessibilityElement(children: .contain), @ScaledMetric,
//       Environment(\.dynamicTypeSize) + DynamicTypeSize.isAccessibilitySize (iOS 15), rotationEffect(_:).
import SwiftUI
import TimetableCore
import TimetableUI

struct GridWeekView: View {
    let layout: TimetableCore.GridLayout
    let strip: WeekStripModel
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var periodColumnWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var comfortableRowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var compactRowHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .caption2) private var breakRowHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var lunchRowHeight: CGFloat = 22

    private let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let mode = GridMode.choose(isAccessibilitySize: typeSize.isAccessibilitySize,
                                       columnCount: layout.columns.count,
                                       availableWidth: Double(proxy.size.width - 2 * horizontalPadding),
                                       periodColumnWidth: Double(periodColumnWidth))
            switch mode {
            case .grid:
                grid(width: proxy.size.width - 2 * horizontalPadding)
                    .padding(.horizontal, horizontalPadding)
            case .list:
                GridListView(layout: layout, strip: strip, timetable: timetable, reasons: reasons, onOpen: onOpen,
                             onAdd: onAdd)
            }
        }
    }

    // MARK: Geometry

    private var isCompact: Bool { timetable.density.effective == .compact }

    private func height(of row: TimetableCore.GridLayout.Row) -> CGFloat {
        if row.isLessonRow { return isCompact ? compactRowHeight : comfortableRowHeight }
        return row.kind == .lunch ? lunchRowHeight : breakRowHeight
    }

    private var rowTops: [CGFloat] {
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for row in layout.rows {
            tops.append(y)
            y += height(of: row)
        }
        return tops
    }

    private var totalHeight: CGFloat { layout.rows.reduce(0) { $0 + height(of: $1) } }

    // MARK: Grid

    private func grid(width: CGFloat) -> some View {
        let columnCount = max(1, layout.columns.count)
        let columnWidth = max(1, (width - periodColumnWidth) / CGFloat(columnCount))
        let tops = rowTops
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: periodColumnWidth, height: 1)
                ForEach(layout.columns, id: \.index) { column in
                    if let day = strip.days.first(where: { $0.date == column.date }) {
                        DayColumnHeader(day: day).frame(width: columnWidth)
                    } else {
                        Color.clear.frame(width: columnWidth)
                    }
                }
            }
            Divider()
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    rowBands(tops: tops, width: width)
                    periodLabels(tops: tops)
                    nonSchoolColumns(columnWidth: columnWidth)
                    freeSlots(tops: tops, columnWidth: columnWidth)
                    lessonCells(tops: tops, columnWidth: columnWidth)
                }
                .frame(width: width, height: totalHeight, alignment: .topLeading)
                .accessibilityElement(children: .contain)
                .padding(.vertical, 8)
                unplacedSection
            }
        }
    }

    private func rowBands(tops: [CGFloat], width: CGFloat) -> some View {
        ForEach(layout.rows, id: \.index) { row in
            Group {
                if row.isLessonRow {
                    Rectangle().fill(Color.clear)
                } else {
                    Rectangle().fill(Color.secondary.opacity(row.kind == .lunch ? 0.14 : 0.08))
                }
            }
            .frame(width: width, height: height(of: row))
            .offset(y: tops[row.index])
            .accessibilityHidden(true)
        }
    }

    private func periodLabels(tops: [CGFloat]) -> some View {
        ForEach(layout.rows, id: \.index) { row in
            VStack(spacing: 1) {
                if row.isLessonRow {
                    if let label = GridPresentation.rowLabel(row) {
                        Text(verbatim: label)
                            .font(.callout.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(verbatim: model.formatter.time(row.start))
                        .font(.caption2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !isCompact {
                        Text(verbatim: model.formatter.time(row.end))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                } else if row.kind == .lunch {
                    Image(systemName: "fork.knife").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: periodColumnWidth, height: height(of: row))
            .offset(y: tops[row.index])
            .accessibilityHidden(true)
        }
    }

    private func nonSchoolColumns(columnWidth: CGFloat) -> some View {
        ForEach(layout.columns.filter { $0.activeBreakID != nil }, id: \.index) { column in
            VStack(spacing: 8) {
                Image(systemName: "beach.umbrella")
                    .font(.title3)
                if let name = breakName(column.activeBreakID) {
                    Text(verbatim: name)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(.secondary)
            .padding(4)
            .frame(width: columnWidth - 4, height: totalHeight, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.1)))
            .offset(x: periodColumnWidth + CGFloat(column.index) * columnWidth + 2)
            .accessibilityHidden(true)   // the day header reads "holiday"
        }
    }

    private func freeSlots(tops: [CGFloat], columnWidth: CGFloat) -> some View {
        ForEach(layout.emptySlots, id: \.self) { slot in
            let row = layout.rows[slot.row]
            Button {
                if let target = QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row, timetable: timetable) {
                    onAdd(target)
                }
            } label: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: columnWidth - 4, height: height(of: row) - 4)
            .offset(x: periodColumnWidth + CGFloat(slot.column) * columnWidth + 2, y: tops[slot.row] + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.freeSlotAccessibilityLabel(
                column: layout.columns[slot.column], row: row, renderer: model.renderer)))
            .accessibilityHint(Text("timetable.a11y.addHint"))
            .accessibilitySortPriority(sortPriority(column: slot.column, row: slot.row))
        }
    }

    private func lessonCells(tops: [CGFloat], columnWidth: CGFloat) -> some View {
        ForEach(layout.cells, id: \.entry.id) { cell in
            let spanHeight = (cell.row..<(cell.row + cell.rowSpan)).reduce(CGFloat(0)) { $0 + height(of: layout.rows[$1]) }
            Button {
                onOpen(cell.entry)
            } label: {
                GridCellView(cell: cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                             showsDetails: !isCompact)
            }
            .buttonStyle(.plain)
            .frame(width: columnWidth - 4, height: spanHeight - 4)
            .offset(x: periodColumnWidth + CGFloat(cell.column) * columnWidth + 2, y: tops[cell.row] + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.cellAccessibilityLabel(
                cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                renderer: model.renderer)))
            .accessibilityHint(Text("timetable.a11y.openHint"))
            .accessibilitySortPriority(sortPriority(column: cell.column, row: cell.row))
        }
    }

    @ViewBuilder
    private var unplacedSection: some View {
        if !layout.unplaced.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("timetable.unplaced.header")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(layout.unplaced) { lesson in
                    Button { onOpen(lesson) } label: {
                        LessonRowView(lesson: lesson, reasons: reasons[lesson.id] ?? [], visibility: timetable.fieldVisibility)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Column-major reading order: Monday's periods first (higher priority is read first).
    private func sortPriority(column: Int, row: Int) -> Double {
        -Double(column * 1_000 + row)
    }

    private func breakName(_ id: CalendarBreak.ID?) -> String? {
        guard let id, let name = model.database?.breaks.first(where: { $0.id == id })?.name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One lesson in the grid: subject colour, emoji, short name, optional room, status/conflict icons.
struct GridCellView: View {
    let cell: TimetableCore.GridLayout.Cell
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    let showsDetails: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let lesson = cell.entry
        let style = LessonTileStyle(color: lesson.subject.color)
        let foreground = Color(style.foreground)
        let cancelled = lesson.status == .cancelled
        VStack(spacing: 1) {
            if let emoji = GridPresentation.emoji(lesson.subject) {
                Text(verbatim: emoji).font(.caption)
            }
            Text(verbatim: GridPresentation.cellTitle(lesson.subject))
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .strikethrough(cancelled, pattern: .solid, color: foreground)
            if showsDetails, let room = VisibleLessonFields(lesson: lesson, visibility: visibility).room {
                Text(verbatim: room)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(style.background)))
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                CornerIcon(symbolName: badge.symbolName)
            }
        }
        .overlay(alignment: .topLeading) {
            if cell.isInConflict {
                CornerIcon(symbolName: "exclamationmark.triangle.fill")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A tiny symbol on a material disc in a cell corner (legible on any subject colour).
struct CornerIcon: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.primary)
            .padding(3)
            .background(Circle().fill(.regularMaterial))
            .padding(1)
            .accessibilityHidden(true)
    }
}
