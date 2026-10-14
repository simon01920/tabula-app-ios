// Proportional views drawn from `TimeBlockLayout` (wall-clock minutes → height): the week time-blocks view
// (route `timetable.week`) and the single-day view (route `timetable.day`). Overlapping lessons share the column in
// lanes; a current-time line marks "now" in today's column (moved once a minute by the parent's TimelineView, never
// animated, so Reduce Motion needs no special case; drawn beneath the tiles; frozen at `-TabulaNow` in screenshot mode).
// APIs: GeometryReader, ScrollView, ZStack + frame/offset, Rectangle, Circle, @ScaledMetric, Button(.plain),
//       accessibilitySortPriority(_:), accessibilityHidden(_:).
import SwiftUI
import TimetableCore
import TimetableUI

/// The week as proportional blocks with an hour axis.
struct TimeBlockWeekView: View {
    let layout: TimeBlockLayout
    let strip: WeekStripModel
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let onOpen: (ResolvedLesson) -> Void

    @ScaledMetric(relativeTo: .caption2) private var gutterWidth: CGFloat = 44
    private let horizontalPadding: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 2 * horizontalPadding
            let columnWidth = max(1, (width - gutterWidth) / CGFloat(max(1, layout.columns.count)))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutterWidth, height: 1)
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
                    TimeBlockCanvas(layout: layout, timetable: timetable, reasons: reasons, today: today,
                                    nowMinute: nowMinute, width: width, gutterWidth: gutterWidth, detailed: false,
                                    onOpen: onOpen)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

/// One day as proportional blocks (wider blocks with time range and fields).
struct TimeBlockDayView: View {
    let layout: TimeBlockLayout
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let onOpen: (ResolvedLesson) -> Void

    @ScaledMetric(relativeTo: .caption2) private var gutterWidth: CGFloat = 50

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                TimeBlockCanvas(layout: layout, timetable: timetable, reasons: reasons, today: today, nowMinute: nowMinute,
                                width: proxy.size.width - 32, gutterWidth: gutterWidth, detailed: true, onOpen: onOpen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }
}

/// Hour axis, hour lines, blocks and the now line of a `TimeBlockLayout`.
struct TimeBlockCanvas: View {
    let layout: TimeBlockLayout
    let timetable: Timetable
    let reasons: [OccurrenceID: [ModificationReason]]
    let today: LocalDate
    let nowMinute: Int
    let width: CGFloat
    let gutterWidth: CGFloat
    let detailed: Bool
    let onOpen: (ResolvedLesson) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.lessonWork) private var work
    @ScaledMetric(relativeTo: .caption) private var comfortableHourHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .caption) private var compactHourHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .caption) private var minimumBlockHeight: CGFloat = 24

    private var hourHeight: CGFloat {
        let base = timetable.density.effective == .compact ? compactHourHeight : comfortableHourHeight
        return detailed ? base * 1.3 : base
    }

    private var totalHeight: CGFloat { CGFloat(layout.endMinute - layout.startMinute) / 60 * hourHeight }

    var body: some View {
        let height = totalHeight
        let columnWidth = max(1, (width - gutterWidth) / CGFloat(max(1, layout.columns.count)))
        ZStack(alignment: .topLeading) {
            ForEach(layout.hourMarks, id: \.minuteOfDay) { mark in
                let y = CGFloat(mark.position) * height
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: width - gutterWidth, height: 0.5)
                    .offset(x: gutterWidth, y: y)
                if let time = LocalTime(minuteOfDay: mark.minuteOfDay) {
                    Text(verbatim: model.formatter.time(time))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: gutterWidth - 4, alignment: .trailing)
                        .offset(y: y - 7)
                }
            }
            .accessibilityHidden(true)

            ForEach(layout.columns.filter { $0.activeBreakID != nil }, id: \.index) { column in
                Image(systemName: "beach.umbrella")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth - 4, height: height)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.1)))
                    .offset(x: gutterWidth + CGFloat(column.index) * columnWidth + 2)
                    .accessibilityHidden(true)
            }

            // Beneath the tiles (declared before them), so it never covers tile text; visible over empty space and the gutter.
            if let marker = GridPresentation.nowMarker(layout, today: today, minuteOfDay: nowMinute) {
                let y = CGFloat(marker.position) * height
                HStack(spacing: 0) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Rectangle().fill(Color.red).frame(width: columnWidth - 6, height: 2)
                }
                .offset(x: gutterWidth + CGFloat(marker.column) * columnWidth - 2, y: y - 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            ForEach(layout.blocks, id: \.entry.id) { block in
                let laneWidth = columnWidth / CGFloat(max(1, block.laneCount))
                let blockHeight = max(minimumBlockHeight, CGFloat(block.height) * height)
                // Short blocks keep their proportional drawing; only the hit area grows to 44 pt (centred on the block).
                let hit = TapTarget.hitArea(drawn: Double(blockHeight - 2))
                Button {
                    onOpen(block.entry)
                } label: {
                    TimeBlockView(block: block, reasons: reasons[block.entry.id] ?? [],
                                  visibility: timetable.fieldVisibility, detailed: detailed, height: blockHeight,
                                  badges: work.badges(for: block.entry.id))
                        .frame(width: laneWidth - 3, height: blockHeight - 2)
                        .frame(height: CGFloat(hit.length))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: laneWidth - 3, height: CGFloat(hit.length))
                .offset(x: gutterWidth + CGFloat(block.column) * columnWidth + CGFloat(block.lane) * laneWidth + 1.5,
                        y: CGFloat(block.top) * height + 1 - CGFloat(hit.overhang))
                .accessibilityLabel(Text(verbatim: blockLabel(block)))
                .accessibilityHint(Text("timetable.a11y.openHint"))
                .accessibilitySortPriority(-Double(block.column * 10_000 + block.entry.startTime.minuteOfDay))
            }
        }
        .overlay(alignment: .topLeading) {
            // The line itself is beneath the tiles; this dot on the column's left edge (outside the tile text)
            // keeps "now" visible when it falls inside a lesson.
            if let marker = GridPresentation.nowMarker(layout, today: today, minuteOfDay: nowMinute) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                    .offset(x: gutterWidth + CGFloat(marker.column) * columnWidth - 4,
                            y: CGFloat(marker.position) * height - 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func blockLabel(_ block: TimeBlockLayout.Block) -> String {
        let lesson = LessonAccessibilityLabel.make(lesson: block.entry, visibility: timetable.fieldVisibility,
                                                   reasons: reasons[block.entry.id] ?? [],
                                                   badges: work.badges(for: block.entry.id), renderer: model.renderer)
        guard !detailed else { return lesson }
        return model.renderer.format(key: "timetable.a11y.cell", arguments: [
            .text(model.formatter.date(block.entry.date, style: .full)), .text(lesson),
        ])
    }
}

/// One proportional block. Task / exam badges (Phase 3 C1): full capsules in the day view when the block is tall
/// enough, else the compact "☑2 🎓" line (week view: from 40 pt; shorter blocks rely on VoiceOver and the detail).
struct TimeBlockView: View {
    let block: TimeBlockLayout.Block
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    let detailed: Bool
    let height: CGFloat
    var badges: LessonBadges?
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let lesson = block.entry
        let style = LessonTileStyle(color: lesson.subject.color)
        let foreground = Color(style.foreground)
        let cancelled = lesson.status == .cancelled
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if detailed { SubjectSymbolText(subject: lesson.subject, font: .subheadline) }
                Text(verbatim: detailed ? lesson.subject.name : GridPresentation.cellTitle(lesson.subject))
                    .font(detailed ? .subheadline.weight(.semibold) : .caption.weight(.bold))
                    .lineLimit(detailed ? 2 : 1)
                    .minimumScaleFactor(0.6)
                    .strikethrough(cancelled, pattern: .solid, color: foreground)
            }
            if height >= 40 {
                Text(verbatim: detailed ? model.formatter.timeRange(lesson.startTime, lesson.endTime)
                                        : model.formatter.time(lesson.startTime))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if detailed, height >= 64 {
                LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility,
                                                                  only: [.room, .building, .teacher, .lessonType]),
                                     font: .caption)
            } else if height >= 56, badges == nil, let room = VisibleLessonFields(lesson: lesson, visibility: visibility).room {
                Text(verbatim: room).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
            }
            if let badges, height >= 40 {
                if detailed && height >= 88 {
                    LessonWorkBadgeRow(badges: badges)
                } else {
                    CompactLessonWorkBadges(badges: badges)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(style.background)))
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                if detailed {
                    LessonStatusBadge(badge).foregroundStyle(Color.primary).padding(4)
                } else {
                    CornerIcon(symbolName: badge.symbolName)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }
}
