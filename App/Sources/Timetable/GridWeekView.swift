// Classic periods × days grid (route `timetable.grid`), drawn from `GridLayout`:
// - day headers pinned above the scroll view (aligned with the columns; today's header tinted, change symbol), the
//   period column on the leading edge with lesson numbers and times (no horizontal scrolling: 5/6/7 columns share the
//   width, so the period column is always visible); the current period's number gets the highlighter;
// - lesson rows grow to fill the available height, with a minimum (Opus L3); cells span rows (double periods include
//   the break between), break/lunch rows are thin bands, holidays shade their column;
// - fixed cell anatomy (Opus H5): line 1 = short name (emoji above it when it fits, dropped first via ViewThatFits),
//   line 2 = room, always (field rule: absent when hidden or empty), one badge slot bottom-trailing with priority
//   cancelled > exam > tasks > change (`LessonCellBadge`); cancelled cells are dimmed and struck through; the current
//   lesson has the highlighter outline (VoiceOver value "in progress");
// - free lesson slots stay quiet (Opus M14): no outline; tap opens quick add, the dashed "+" shows while pressed;
// - at accessibility text sizes, or when the columns would be narrower than `GridMode.minimumColumnWidth`, the same
//   layout is shown as a list (`GridListView`, kept from Phase 2: Opus §3 "What works").
// VoiceOver: cells read "<date>: <lesson sentence>" column by column (sort priority), free slots read
// "<date>, period n, <time>, free" with the hint "Adds a lesson".
// APIs: GeometryReader, ScrollView, ZStack + frame/offset, RoundedRectangle, ViewThatFits(in: .vertical),
//       ButtonStyle, accessibilitySortPriority(_:), accessibilityElement(children: .contain), @ScaledMetric,
//       Environment(\.dynamicTypeSize) + DynamicTypeSize.isAccessibilitySize.
import SwiftUI
import TimetableCore
import TimetableUI

struct GridWeekView: View {
    let layout: TimetableCore.GridLayout
    let strip: WeekStripModel
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.lessonWork) private var work
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var periodColumnWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var comfortableRowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var compactRowHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .caption2) private var breakRowHeight: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var lunchRowHeight: CGFloat = 22

    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 8
    /// Rows grow at most to this multiple of their minimum (a 4-period day should not get half-screen cells).
    private let maximumGrowth: CGFloat = 2

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
                GridListView(layout: layout, strip: strip, timetable: timetable, reasons: reasons, today: today,
                             nowMinute: nowMinute, onOpen: onOpen, onAdd: onAdd)
            }
        }
    }

    // MARK: Geometry

    private var isCompact: Bool { timetable.density.effective == .compact }

    /// Heights of all rows when the scroll area is `available` points tall: break rows fixed, lesson rows share the
    /// rest (at least their minimum, at most `maximumGrowth` times it).
    private func rowHeights(available: CGFloat) -> [CGFloat] {
        let minimum = isCompact ? compactRowHeight : comfortableRowHeight
        let lessonRows = layout.rows.filter(\.isLessonRow).count
        let fixed = layout.rows.filter { !$0.isLessonRow }
            .reduce(CGFloat(0)) { $0 + ($1.kind == .lunch ? lunchRowHeight : breakRowHeight) }
        let share = lessonRows > 0 ? (available - 2 * verticalPadding - fixed) / CGFloat(lessonRows) : minimum
        let lessonHeight = min(max(minimum, share), minimum * maximumGrowth)
        return layout.rows.map { row in
            row.isLessonRow ? lessonHeight : (row.kind == .lunch ? lunchRowHeight : breakRowHeight)
        }
    }

    private func tops(_ heights: [CGFloat]) -> [CGFloat] {
        var result: [CGFloat] = []
        var y: CGFloat = 0
        for height in heights {
            result.append(y)
            y += height
        }
        return result
    }

    // MARK: Grid

    private func grid(width: CGFloat) -> some View {
        let columnCount = max(1, layout.columns.count)
        let columnWidth = max(1, (width - periodColumnWidth) / CGFloat(columnCount))
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
            GeometryReader { scrollProxy in
                let heights = rowHeights(available: scrollProxy.size.height)
                let tops = tops(heights)
                let total = heights.reduce(0, +)
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        rowBands(tops: tops, heights: heights, width: width)
                        periodLabels(tops: tops, heights: heights)
                        nonSchoolColumns(columnWidth: columnWidth, totalHeight: total)
                        freeSlots(tops: tops, heights: heights, columnWidth: columnWidth)
                        lessonCells(tops: tops, heights: heights, columnWidth: columnWidth)
                    }
                    .frame(width: width, height: total, alignment: .topLeading)
                    .accessibilityElement(children: .contain)
                    .padding(.vertical, verticalPadding)
                    unplacedSection
                }
            }
        }
    }

    private func rowBands(tops: [CGFloat], heights: [CGFloat], width: CGFloat) -> some View {
        ForEach(layout.rows, id: \.index) { row in
            Group {
                if row.isLessonRow {
                    Rectangle().fill(Color.clear)
                } else {
                    Rectangle().fill(Color.secondary.opacity(row.kind == .lunch ? 0.14 : 0.08))
                }
            }
            .frame(width: width, height: heights[row.index])
            .offset(y: tops[row.index])
            .accessibilityHidden(true)
        }
    }

    /// `true` when `row` is today's current lesson period.
    private func isCurrentRow(_ row: TimetableCore.GridLayout.Row) -> Bool {
        row.isLessonRow && layout.columns.contains { $0.date == today }
            && row.start.minuteOfDay <= nowMinute && nowMinute < row.end.minuteOfDay
    }

    private func periodLabels(tops: [CGFloat], heights: [CGFloat]) -> some View {
        ForEach(layout.rows, id: \.index) { row in
            VStack(spacing: 1) {
                if row.isLessonRow {
                    if let label = GridPresentation.rowLabel(row) {
                        let current = isCurrentRow(row)
                        Text(verbatim: label)
                            .font(.callout.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(current ? TimetableColor.onHighlighter : Color.primary)
                            .padding(.horizontal, current ? 5 : 0)
                            .background {
                                // The current period: the highlighter marker in the gutter (Opus §9 signature).
                                if current {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(TimetableColor.highlighter)
                                }
                            }
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
            .frame(width: periodColumnWidth, height: heights[row.index])
            .offset(y: tops[row.index])
            .accessibilityHidden(true)
        }
    }

    private func nonSchoolColumns(columnWidth: CGFloat, totalHeight: CGFloat) -> some View {
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

    private func freeSlots(tops: [CGFloat], heights: [CGFloat], columnWidth: CGFloat) -> some View {
        ForEach(layout.emptySlots, id: \.self) { slot in
            let row = layout.rows[slot.row]
            Button {
                if let target = QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row, timetable: timetable) {
                    onAdd(target)
                }
            } label: {
                EmptyView()
            }
            .buttonStyle(QuietFreeSlotButtonStyle())
            .frame(width: columnWidth - 4, height: heights[slot.row] - 4)
            .offset(x: periodColumnWidth + CGFloat(slot.column) * columnWidth + 2, y: tops[slot.row] + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.freeSlotAccessibilityLabel(
                column: layout.columns[slot.column], row: row, renderer: model.renderer)))
            .accessibilityHint(Text("timetable.a11y.addHint"))
            .accessibilitySortPriority(sortPriority(column: slot.column, row: slot.row))
        }
    }

    private func lessonCells(tops: [CGFloat], heights: [CGFloat], columnWidth: CGFloat) -> some View {
        ForEach(layout.cells, id: \.entry.id) { cell in
            let spanHeight = (cell.row..<min(cell.row + cell.rowSpan, heights.count)).reduce(CGFloat(0)) { $0 + heights[$1] }
            let current = NowLinePresentation.isCurrent(cell.entry, today: today, minuteOfDay: nowMinute)
            Button {
                onOpen(cell.entry)
            } label: {
                GridCellView(cell: cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                             badges: work.badges(for: cell.entry.id), isCurrent: current)
            }
            .buttonStyle(.plain)
            .frame(width: columnWidth - 4, height: spanHeight - 4)
            .offset(x: periodColumnWidth + CGFloat(cell.column) * columnWidth + 2, y: tops[cell.row] + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.cellAccessibilityLabel(
                cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                badges: work.badges(for: cell.entry.id), renderer: model.renderer)))
            .accessibilityValue(ifPresent: current ? "today.a11y.inProgress" : nil)
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
                        LessonRowView(lesson: lesson, reasons: reasons[lesson.id] ?? [], visibility: timetable.fieldVisibility,
                                      isCurrent: NowLinePresentation.isCurrent(lesson, today: today, minuteOfDay: nowMinute))
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

/// One lesson in the grid (Opus H5 anatomy): short name (emoji above when it fits), the room on line 2 whenever it is
/// visible and set, one badge slot bottom-trailing, a conflict icon top-leading.
struct GridCellView: View {
    let cell: TimetableCore.GridLayout.Cell
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    var badges: LessonBadges?
    var isCurrent = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private let cornerRadius: CGFloat = 8

    var body: some View {
        let lesson = cell.entry
        let style = LessonTileStyle(color: lesson.subject.color)
        let foreground = Color(style.foreground)
        let cancelled = lesson.status == .cancelled
        let badge = LessonCellBadge.make(status: lesson.status, reasons: reasons, badges: badges)
        let room = VisibleLessonFields(lesson: lesson, visibility: visibility).room
        ViewThatFits(in: .vertical) {
            lines(lesson: lesson, room: room, foreground: foreground, cancelled: cancelled, withEmoji: true)
            lines(lesson: lesson, room: room, foreground: foreground, cancelled: cancelled, withEmoji: false)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color(style.background)))
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        // Cancelled: the whole cell steps back (Opus H5); the badge below stays at full strength.
        .opacity(cancelled ? 0.4 : 1)
        .overlay {
            if isCurrent { HighlighterOutline(cornerRadius: cornerRadius) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge { CellBadgeView(badge: badge) }
        }
        .overlay(alignment: .topLeading) {
            if cell.isInConflict {
                ConflictCornerIcon()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func lines(lesson: ResolvedLesson, room: String?, foreground: Color, cancelled: Bool,
                       withEmoji: Bool) -> some View {
        VStack(spacing: 1) {
            if withEmoji, let emoji = GridPresentation.emoji(lesson.subject) {
                Text(verbatim: emoji).font(.caption)
            }
            Text(verbatim: GridPresentation.cellTitle(lesson.subject))
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .strikethrough(cancelled, pattern: .solid, color: foreground)
            if let room {
                Text(verbatim: room)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .strikethrough(cancelled, pattern: .solid, color: foreground)
            }
        }
    }
}

/// The overlap/conflict marker: a tiny symbol on a material disc in a cell corner (legible on any subject colour).
struct ConflictCornerIcon: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.primary)
            .padding(3)
            .background(Circle().fill(.regularMaterial))
            .padding(1)
            .accessibilityHidden(true)
    }
}
