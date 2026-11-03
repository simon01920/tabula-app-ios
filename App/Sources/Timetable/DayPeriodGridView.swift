// The Grid as days × periods (`GridLayoutStyle.daysAsRows`, the default; human decision 2026-11-01, the Slovak aSc
// layout), drawn from `DayPeriodGrid` (TimetableUI, Linux-tested) over `GridLayout`. The periods × days layout
// (`GridWeekView`) is the second option; `TimetableGridView` picks one from `AppSettings.gridLayout`.
// - rows = days: a pinned leading day column (abbreviated weekday + date, today tinted ink, change symbol);
//   columns = periods of the bell schedule: a two-line header (number, start time; free-form: start, end); the current
//   period's number gets the highlighter;
// - the period columns share the width when each gets at least `minimumPeriodWidth` (7 periods in portrait); then the
//   header is pinned above the vertical scroll. Otherwise they keep that width and scroll horizontally together with
//   the header while the day column stays put (shortcut: the header then scrolls vertically with the rows when the
//   rows do not fit too; pin it with a synced header if that shows up on the device). The export page
//   (`isExportRendering`) always fits all periods, without scrolling;
// - day rows share the height between a minimum and 1.5x their normal height;
// - a lesson spanning several periods spans those columns (a double period across a break is one cell); break columns
//   are dropped (the header's start times show the gaps); holidays shade their row;
// - fixed cell anatomy (Opus H5): short name bold and centred (emoji above it when it fits), the room small at
//   bottom-trailing (field rule: absent when hidden or empty), one badge slot bottom-leading with priority
//   cancelled > exam > tasks > change (`LessonCellBadge`); cancelled cells are dimmed and struck through; the current
//   lesson has the highlighter outline (VoiceOver value "in progress");
// - free periods are quiet grey cells (no outline); tap opens quick add, the dashed "+" shows while pressed;
// - at accessibility text sizes, or when fewer than 3 period columns fit, the list (`GridListView`) is shown.
// VoiceOver reads row by row (sort priority): cells "<date>: <lesson sentence>", free periods
// "<date>, period n, <time>, free" with the hint "Adds a lesson", a holiday row the day's sentence.
// APIs: GeometryReader, ScrollView(.horizontal), ZStack + frame/offset, RoundedRectangle, ViewThatFits,
//       ButtonStyle, accessibilitySortPriority(_:), accessibilityElement(children:), @ScaledMetric,
//       Environment(\.dynamicTypeSize) + DynamicTypeSize.isAccessibilitySize.
import SwiftUI
import TimetableCore
import TimetableUI

/// The Grid in the layout chosen in Settings (`AppSettings.gridLayout`); the export page follows the same setting.
struct TimetableGridView: View {
    let layout: TimetableCore.GridLayout
    let strip: WeekStripModel
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let onOpen: (ResolvedLesson) -> Void
    let onAdd: (QuickAddTarget) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.gridLayoutOverride) private var override

    var body: some View {
        if (override ?? model.settings.effectiveGridLayout) == .periodsAsRows {
            GridWeekView(layout: layout, strip: strip, timetable: timetable, reasons: reasons, today: today,
                         nowMinute: nowMinute, onOpen: onOpen, onAdd: onAdd)
        } else {
            DayPeriodGridView(layout: layout, strip: strip, timetable: timetable, reasons: reasons, today: today,
                              nowMinute: nowMinute, onOpen: onOpen, onAdd: onAdd)
        }
    }
}

/// Screenshot route `timetable.grid-periods`: draws a layout without changing the saved setting.
private struct GridLayoutOverrideKey: EnvironmentKey { static let defaultValue: GridLayoutStyle? = nil }

extension EnvironmentValues {
    var gridLayoutOverride: GridLayoutStyle? {
        get { self[GridLayoutOverrideKey.self] }
        set { self[GridLayoutOverrideKey.self] = newValue }
    }
}

struct DayPeriodGridView: View {
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
    @Environment(\.isExportRendering) private var exporting
    @ScaledMetric(relativeTo: .subheadline) private var dayColumnWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .callout) private var headerHeight: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var minimumPeriodWidth: CGFloat = GridMode.minimumPeriodColumnWidth
    @ScaledMetric(relativeTo: .caption) private var comfortableRowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var compactRowHeight: CGFloat = 50

    private let horizontalPadding: CGFloat = 8
    private let verticalPadding: CGFloat = 8
    /// Rows grow at most to this multiple of their normal height (a 4-day week should not get half-screen cells).
    private let maximumGrowth: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 2 * horizontalPadding
            let mode = GridMode.choose(isAccessibilitySize: typeSize.isAccessibilitySize, availableWidth: Double(width),
                                       dayColumnWidth: Double(dayColumnWidth), minimumWidth: Double(minimumPeriodWidth))
            switch mode {
            case .grid:
                grid(DayPeriodGrid(layout), width: width, height: proxy.size.height)
                    .padding(.horizontal, horizontalPadding)
            case .list:
                GridListView(layout: layout, strip: strip, timetable: timetable, reasons: reasons, today: today,
                             nowMinute: nowMinute, onOpen: onOpen, onAdd: onAdd)
            }
        }
    }

    // MARK: Grid

    private func grid(_ grid: DayPeriodGrid, width: CGFloat, height: CGFloat) -> some View {
        let columns = GridMode.periodColumnWidth(count: grid.periods.count, availableWidth: Double(width),
                                                 dayColumnWidth: Double(dayColumnWidth),
                                                 minimumWidth: Double(minimumPeriodWidth), fitAll: exporting)
        let periodWidth = CGFloat(columns.width)
        let normal = timetable.density.effective == .compact ? compactRowHeight : comfortableRowHeight
        let rowHeight = CGFloat(GridMode.dayRowHeight(
            count: grid.days.count, available: Double(height - headerHeight - 1 - 2 * verticalPadding),
            minimum: Double(compactRowHeight), maximum: Double(normal * maximumGrowth)))
        let bodySize = CGSize(width: periodWidth * CGFloat(grid.periods.count), height: rowHeight * CGFloat(grid.days.count))
        return VStack(spacing: 0) {
            if !columns.scrolls {
                // All periods fit: the header is pinned above the vertical scroll, as the other layout pins its days.
                HStack(spacing: 0) {
                    Color.clear.frame(width: dayColumnWidth, height: 1)
                    periodHeader(grid, periodWidth: periodWidth)
                }
                headerRule(width: dayColumnWidth + bodySize.width)
            }
            ExportAwareScroll {
                HStack(alignment: .top, spacing: 0) {
                    dayLabels(grid, rowHeight: rowHeight, headerSpace: columns.scrolls)
                    if columns.scrolls {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                periodHeader(grid, periodWidth: periodWidth)
                                headerRule(width: bodySize.width)
                                table(grid, periodWidth: periodWidth, rowHeight: rowHeight, size: bodySize)
                            }
                        }
                    } else {
                        table(grid, periodWidth: periodWidth, rowHeight: rowHeight, size: bodySize)
                    }
                }
                .padding(.vertical, verticalPadding)
                unplacedSection(grid.unplaced)
            }
        }
    }

    private func headerRule(width: CGFloat) -> some View {
        Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: width, height: 1).accessibilityHidden(true)
    }

    private func table(_ grid: DayPeriodGrid, periodWidth: CGFloat, rowHeight: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            holidayRows(grid, size: size, rowHeight: rowHeight)
            freeSlots(grid, periodWidth: periodWidth, rowHeight: rowHeight)
            lessonCells(grid, periodWidth: periodWidth, rowHeight: rowHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    /// The pinned leading column: one label per day row (below a header-tall spacer when the header scrolls).
    private func dayLabels(_ grid: DayPeriodGrid, rowHeight: CGFloat, headerSpace: Bool) -> some View {
        VStack(spacing: 0) {
            if headerSpace { Color.clear.frame(height: headerHeight + 1) }
            ForEach(grid.days, id: \.index) { column in
                GridDayLabel(date: column.date, day: strip.days.first { $0.date == column.date })
                    .frame(height: rowHeight)
            }
        }
        .frame(width: dayColumnWidth)
        .accessibilityHidden(true)   // every cell and free period names its day; a holiday row reads the day sentence
    }

    private func periodHeader(_ grid: DayPeriodGrid, periodWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(grid.periods.indices, id: \.self) { index in
                let row = grid.periods[index]
                let current = grid.isCurrent(period: index, today: today, minuteOfDay: nowMinute)
                VStack(spacing: 1) {
                    // Bell schedule: number + start time; free-form slots have no period number: start + end time.
                    if row.periodID != nil, let label = GridPresentation.rowLabel(row) {
                        highlighted(Text(verbatim: label).font(.callout.weight(.bold)), current: current)
                        timeText(row.start)
                    } else {
                        highlighted(Text(verbatim: model.formatter.time(row.start)).font(.caption.weight(.bold)),
                                    current: current)
                        timeText(row.end)
                    }
                }
                .frame(width: periodWidth, height: headerHeight)
            }
        }
        .accessibilityHidden(true)   // free periods and cells read their period and time
    }

    /// The current period's label: the highlighter marker behind black text (Opus §9 signature).
    private func highlighted(_ text: Text, current: Bool) -> some View {
        text
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(current ? Color.onHighlighter : Color.primary)
            .padding(.horizontal, current ? 5 : 0)
            .background {
                if current { HighlighterStroke().fill(Color.highlighter) }
            }
    }

    private func timeText(_ time: LocalTime) -> some View {
        Text(verbatim: model.formatter.time(time))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func holidayRows(_ grid: DayPeriodGrid, size: CGSize, rowHeight: CGFloat) -> some View {
        ForEach(grid.days.filter { $0.activeBreakID != nil }, id: \.index) { column in
            HStack(spacing: 6) {
                Image(systemName: "beach.umbrella")
                if let name = breakName(column.activeBreakID) {
                    Text(verbatim: name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(width: size.width - 4, height: rowHeight - 4, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.1)))
            .offset(x: 2, y: CGFloat(column.index) * rowHeight + 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: dayAccessibilityLabel(column.date)))
            .accessibilitySortPriority(sortPriority(day: column.index, period: -1))
        }
    }

    private func freeSlots(_ grid: DayPeriodGrid, periodWidth: CGFloat, rowHeight: CGFloat) -> some View {
        ForEach(grid.free, id: \.self) { free in
            Button {
                if let target = QuickAddTarget.make(layout: layout, column: free.day, row: free.row, timetable: timetable) {
                    onAdd(target)
                }
            } label: {
                EmptyView()
            }
            .buttonStyle(QuietFreeSlotButtonStyle(filled: true))
            .frame(width: periodWidth - 4, height: rowHeight - 4)
            .offset(x: CGFloat(free.period) * periodWidth + 2, y: CGFloat(free.day) * rowHeight + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.freeSlotAccessibilityLabel(
                column: layout.columns[free.day], row: layout.rows[free.row], renderer: model.renderer)))
            .accessibilityHint(Text("timetable.a11y.addHint"))
            .accessibilitySortPriority(sortPriority(day: free.day, period: free.period))
        }
    }

    private func lessonCells(_ grid: DayPeriodGrid, periodWidth: CGFloat, rowHeight: CGFloat) -> some View {
        ForEach(grid.cells, id: \.cell.entry.id) { item in
            let cell = item.cell
            let current = NowLinePresentation.isCurrent(cell.entry, today: today, minuteOfDay: nowMinute)
            Button {
                onOpen(cell.entry)
            } label: {
                DayPeriodCellView(cell: cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                                  badges: work.badges(for: cell.entry.id), isCurrent: current)
            }
            .buttonStyle(.plain)
            .frame(width: CGFloat(item.span) * periodWidth - 4, height: rowHeight - 4)
            .offset(x: CGFloat(item.period) * periodWidth + 2, y: CGFloat(item.day) * rowHeight + 2)
            .accessibilityLabel(Text(verbatim: GridPresentation.cellAccessibilityLabel(
                cell, reasons: reasons[cell.entry.id] ?? [], visibility: timetable.fieldVisibility,
                badges: work.badges(for: cell.entry.id), renderer: model.renderer)))
            .accessibilityValue(ifPresent: current ? "today.a11y.inProgress" : nil)
            .accessibilityHint(Text("timetable.a11y.openHint"))
            .accessibilitySortPriority(sortPriority(day: item.day, period: item.period))
        }
    }

    @ViewBuilder
    private func unplacedSection(_ unplaced: [ResolvedLesson]) -> some View {
        if !unplaced.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("timetable.unplaced.header")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(unplaced) { lesson in
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

    /// Row-major reading order: Monday's periods first, left to right (higher priority is read first).
    private func sortPriority(day: Int, period: Int) -> Double {
        -Double(day * 1_000 + period)
    }

    private func dayAccessibilityLabel(_ date: LocalDate) -> String {
        guard let day = strip.days.first(where: { $0.date == date }) else { return model.formatter.date(date, style: .full) }
        return WeekStripModel.accessibilityLabel(day, renderer: model.renderer)
    }

    private func breakName(_ id: CalendarBreak.ID?) -> String? {
        guard let id, let name = model.database?.breaks.first(where: { $0.id == id })?.name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A day row's label: the abbreviated weekday (as in the week strip), the day of the month and the change symbol;
/// today is tinted ink (not red: red means cancelled / overdue only, UX plan D1).
struct GridDayLabel: View {
    let date: LocalDate
    let day: WeekStripDay?
    @Environment(AppModel.self) private var model

    var body: some View {
        let isToday = day?.isToday ?? false
        VStack(spacing: 1) {
            Text(verbatim: model.formatter.weekdayName(date.weekday, width: .abbreviated))
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: date.day.formatted())
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.ink : Color.secondary)
                .lineLimit(1)
            if day?.hasChanges == true {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .foregroundStyle(isToday ? Color.ink : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.ink.opacity(0.12)).padding(2)
            }
        }
    }
}

/// One lesson in the grid (Opus H5 anatomy): short name bold and centred (emoji above when it fits), the room small at
/// bottom-trailing whenever it is visible and set, one badge slot bottom-leading, a conflict icon top-leading.
struct DayPeriodCellView: View {
    let cell: TimetableCore.GridLayout.Cell
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    var badges: LessonBadges?
    var isCurrent = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    /// The height of `CellBadgeView` (a 10 pt caption2 symbol plus its capsule padding): the bottom row is always this
    /// tall, so names line up along a row whether or not a cell has a room or a badge.
    @ScaledMetric(relativeTo: .caption2) private var badgeRow: CGFloat = 19

    private let cornerRadius: CGFloat = 8

    var body: some View {
        let lesson = cell.entry
        let style = LessonTileStyle(color: lesson.subject.color)
        let foreground = Color(style.foreground)
        let cancelled = lesson.status == .cancelled
        let badge = LessonCellBadge.make(status: lesson.status, reasons: reasons, badges: badges)
        let room = VisibleLessonFields(lesson: lesson, visibility: visibility).room
        // Cancelled: the cell steps back (Opus H5): background, name and room at 0.4; the badge stays at full strength.
        let dim = cancelled ? 0.4 : 1.0
        // Inside the highlighter outline (4.5 pt) the text keeps clear of it.
        let inset: CGFloat = isCurrent ? 6 : 4
        VStack(spacing: 0) {
            ViewThatFits(in: .vertical) {
                title(lesson, foreground: foreground, cancelled: cancelled, withEmoji: true)
                title(lesson, foreground: foreground, cancelled: cancelled, withEmoji: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(dim)
            // One bottom row: badge leading, room trailing, side by side (D6: the badge never covers the room). When
            // the room and the badge with its task count do not both fit, the badge drops the count first.
            ViewThatFits(in: .horizontal) {
                bottomRow(badge: badge, room: room, badgeWidth: badgeRow * 1.8, fixedRoom: true,
                          foreground: foreground, cancelled: cancelled, dim: dim)
                bottomRow(badge: badge, room: room, badgeWidth: badgeRow + 2, fixedRoom: false,
                          foreground: foreground, cancelled: cancelled, dim: dim)
            }
            .frame(height: badgeRow)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, inset)
        .padding(.top, 3)
        .padding(.bottom, isCurrent ? 3 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color(style.background)).opacity(dim)
        }
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                    .opacity(dim)
            }
        }
        .overlay {
            if isCurrent { HighlighterOutline(cornerRadius: cornerRadius) }
        }
        .overlay(alignment: .topLeading) {
            if cell.isInConflict {
                ConflictCornerIcon()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// The badge in a slot `badgeWidth` wide (it shows its task count only when that fits), the room in the rest,
    /// trailing; `fixedRoom` keeps the room at full size so `ViewThatFits` falls back when it does not fit.
    private func bottomRow(badge: LessonCellBadge?, room: String?, badgeWidth: CGFloat, fixedRoom: Bool,
                           foreground: Color, cancelled: Bool, dim: Double) -> some View {
        HStack(spacing: 0) {
            if let badge {
                CellBadgeView(badge: badge)
                    .padding(.leading, -3)
                    .frame(width: badgeWidth, alignment: .leading)
            }
            Group {
                if let room {
                    Text(verbatim: room)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(fixedRoom ? 1 : 0.6)
                        .strikethrough(cancelled, pattern: .solid, color: foreground)
                        .fixedSize(horizontal: fixedRoom, vertical: false)
                        .opacity(dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func title(_ lesson: ResolvedLesson, foreground: Color, cancelled: Bool, withEmoji: Bool) -> some View {
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
        }
    }
}

