// Proportional views drawn from `TimeBlockLayout` (wall-clock minutes → height): the week time-blocks view
// (route `timetable.week`) and the single-day view (route `timetable.day`). Overlapping lessons share the column in
// lanes. Durations stay exact (block height = duration; short blocks only widen their hit area to 44 pt).
// Phase 4U U4:
// - now line (Opus M11, Astra F19, verification D3): a 2 pt correction-red line on a 4 pt backplate across today's
//   column, drawn BEHIND the blocks so it never strikes through a card's text; a dot at the column edge stays above;
//   a "10:20" label (correction capsule, white / black text ≥ 4.5:1) sits in the gutter and hides the hour label it
//   would cover (`NowLinePresentation.hiddenHourMarks`). Moved once a minute by the parent's TimelineView, never
//   animated (Reduce Motion needs nothing); frozen at `-TabulaNow` in screenshot mode;
// - day cards (Opus M12, Astra F18): subject line, then the time (subheadline semibold, monospaced digits) with the
//   room on the same line when it fits; the teacher as footnote only when the block is tall enough;
// - the current lesson has the highlighter outline; cancelled blocks are dimmed; badges use the one-slot rule in the
//   week view (`CellBadgeView`) and the full status / task capsules in the day view.
// APIs: GeometryReader, ScrollView, ZStack + frame/offset, zIndex(_:), Rectangle, Capsule, ViewThatFits, @ScaledMetric,
//       Button(.plain), accessibilitySortPriority(_:), accessibilityHidden(_:).
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

    @ScaledMetric(relativeTo: .caption2) private var gutterWidth: CGFloat = 46
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

    @ScaledMetric(relativeTo: .caption2) private var gutterWidth: CGFloat = 52

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
    @ScaledMetric(relativeTo: .caption2) private var nowLabelHeight: CGFloat = 16

    private var hourHeight: CGFloat {
        let base = timetable.density.effective == .compact ? compactHourHeight : comfortableHourHeight
        return detailed ? base * 1.3 : base
    }

    private var totalHeight: CGFloat { CGFloat(layout.endMinute - layout.startMinute) / 60 * hourHeight }

    var body: some View {
        let height = totalHeight
        let columnWidth = max(1, (width - gutterWidth) / CGFloat(max(1, layout.columns.count)))
        let marker = GridPresentation.nowMarker(layout, today: today, minuteOfDay: nowMinute)
        let hidden = NowLinePresentation.hiddenHourMarks(
            layout.hourMarks.map(\.minuteOfDay), nowMinute: marker == nil ? nil : nowMinute,
            clearanceMinutes: NowLinePresentation.clearanceMinutes(labelHeight: Double(nowLabelHeight),
                                                                   hourHeight: Double(hourHeight)))
        ZStack(alignment: .topLeading) {
            ForEach(layout.hourMarks, id: \.minuteOfDay) { mark in
                let y = CGFloat(mark.position) * height
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: width - gutterWidth, height: 0.5)
                    .offset(x: gutterWidth, y: y)
                if let time = LocalTime(minuteOfDay: mark.minuteOfDay), !hidden.contains(mark.minuteOfDay) {
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

            ForEach(layout.blocks, id: \.entry.id) { block in
                let laneWidth = columnWidth / CGFloat(max(1, block.laneCount))
                let blockHeight = max(minimumBlockHeight, CGFloat(block.height) * height)
                // Short blocks keep their proportional drawing; only the hit area grows to 44 pt (centred on the block).
                let hit = TapTarget.hitArea(drawn: Double(blockHeight - 2))
                let current = NowLinePresentation.isCurrent(block.entry, today: today, minuteOfDay: nowMinute)
                Button {
                    onOpen(block.entry)
                } label: {
                    TimeBlockView(block: block, reasons: reasons[block.entry.id] ?? [],
                                  visibility: timetable.fieldVisibility, detailed: detailed, height: blockHeight,
                                  badges: work.badges(for: block.entry.id), isCurrent: current)
                        .frame(width: laneWidth - 3, height: blockHeight - 2)
                        .frame(height: CGFloat(hit.length))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: laneWidth - 3, height: CGFloat(hit.length))
                .offset(x: gutterWidth + CGFloat(block.column) * columnWidth + CGFloat(block.lane) * laneWidth + 1.5,
                        y: CGFloat(block.top) * height + 1 - CGFloat(hit.overhang))
                .accessibilityLabel(Text(verbatim: blockLabel(block)))
                .accessibilityValue(ifPresent: current ? "today.a11y.inProgress" : nil)
                .accessibilityHint(Text("timetable.a11y.openHint"))
                .accessibilitySortPriority(-Double(block.column * 10_000 + block.entry.startTime.minuteOfDay))
            }

            // The line runs behind the blocks so it never strikes through a card's text (verification D3); the time
            // label and a dot at the column edge sit above them, so the time stays visible on a card too.
            if let marker {
                ForEach([NowLine.Layer.line, .marker], id: \.self) { layer in
                    NowLine(layer: layer, time: LocalTime(minuteOfDay: nowMinute).map(model.formatter.time) ?? "",
                            gutterWidth: gutterWidth, lineX: gutterWidth + CGFloat(marker.column) * columnWidth,
                            lineWidth: columnWidth, labelHeight: nowLabelHeight)
                        .offset(y: CGFloat(marker.position) * height - nowLabelHeight / 2)
                        .zIndex(layer == .line ? -1 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)   // the current block's value says "in progress"
                }
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

/// The current-time marker: "10:20" in a correction capsule in the gutter (x = 0), a hairline from the gutter to
/// today's column (week view), then the correction line on a backplate in the page background colour across today's
/// column (`lineX` … `lineX + lineWidth`).
private struct NowLine: View {
    /// `.line` is drawn behind the blocks, `.marker` (dot + time label) above them.
    enum Layer: Hashable { case line, marker }
    let layer: Layer
    let time: String
    let gutterWidth: CGFloat
    let lineX: CGFloat
    let lineWidth: CGFloat
    let labelHeight: CGFloat
    @ScaledMetric(relativeTo: .caption2) private var dot: CGFloat = 9

    var body: some View {
        ZStack(alignment: .leading) {
            switch layer {
            case .line:
                if lineX > gutterWidth {
                    Rectangle()
                        .fill(Color.correction.opacity(0.5))
                        .frame(width: lineX - gutterWidth, height: 1)
                        .offset(x: gutterWidth)
                }
                // Backplate: contrasting halo around the line where it crosses a free slot (Astra F19).
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(width: lineWidth, height: 4)
                    .offset(x: lineX)
                Rectangle()
                    .fill(Color.correction)
                    .frame(width: lineWidth, height: 2)
                    .offset(x: lineX)
            case .marker:
                // A dot at today's column edge: only the card's padding lies under it, never its text.
                Circle()
                    .fill(Color.correction)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                    .frame(width: dot, height: dot)
                    .offset(x: lineX - dot / 2)
                label
            }
        }
        .frame(height: labelHeight)
    }

    private var label: some View {
        Text(verbatim: time)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color.onCorrection)
            .padding(.horizontal, 4)
            .frame(maxWidth: gutterWidth - 2, minHeight: labelHeight)
            .background(Capsule().fill(Color.correction))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One proportional block. Day view (`detailed`): subject, then time (primary) + room, the teacher when tall enough,
/// then status / task capsules. Week view: short name, start time, room, one badge slot.
struct TimeBlockView: View {
    let block: TimeBlockLayout.Block
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    let detailed: Bool
    let height: CGFloat
    var badges: LessonBadges?
    var isCurrent = false
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let lesson = block.entry
        let style = LessonTileStyle(color: lesson.subject.color)
        let foreground = Color(style.foreground)
        let cancelled = lesson.status == .cancelled
        let fields = VisibleLessonFields(lesson: lesson, visibility: visibility)
        Group {
            if detailed {
                dayCard(lesson: lesson, fields: fields, foreground: foreground, cancelled: cancelled)
            } else {
                weekBlock(lesson: lesson, fields: fields, foreground: foreground, cancelled: cancelled)
            }
        }
        .foregroundStyle(foreground)
        .padding(detailed ? 6 : 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(style.background)))
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .opacity(cancelled ? 0.4 : 1)
        .overlay {
            if isCurrent { HighlighterOutline(cornerRadius: 6) }
        }
        .overlay(alignment: detailed ? .topTrailing : .bottomTrailing) {
            if detailed {
                if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                    LessonStatusBadge(badge).foregroundStyle(Color.primary).padding(4)
                }
            } else if height >= 30, let badge = LessonCellBadge.make(status: lesson.status, reasons: reasons, badges: badges) {
                CellBadgeView(badge: badge)
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }

    /// Day view: subject line; time (primary datum) + room; teacher (footnote) when it fits; task / exam capsules.
    private func dayCard(lesson: ResolvedLesson, fields: VisibleLessonFields, foreground: Color,
                         cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                SubjectSymbolText(subject: lesson.subject, font: .subheadline)
                Text(verbatim: lesson.subject.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(height >= 72 ? 2 : 1)
                    .minimumScaleFactor(0.8)
                    .strikethrough(cancelled, pattern: .solid, color: foreground)
            }
            if height >= 40 {
                let time = Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .strikethrough(cancelled, pattern: .solid, color: foreground)
                if let room = fields.room {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            time
                            roomLabel(room)
                        }
                        time
                    }
                    .lineLimit(1)
                } else {
                    time.lineLimit(1)
                }
            }
            if height >= 64, let teacher = fields.teacher {
                Label { Text(verbatim: teacher) } icon: { Image(systemName: "person") }
                    .font(.footnote)
                    .lineLimit(1)
            }
            if let badges, height >= 88 {
                LessonWorkBadgeRow(badges: badges)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) == nil ? 0 : 24)
    }

    private func roomLabel(_ room: String) -> some View {
        Label { Text(verbatim: room) } icon: { Image(systemName: LessonFieldLine.room(room).symbolName) }
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
    }

    /// Week view: short name, start time (from 40 pt), room (from 56 pt); the badge sits in the corner slot.
    private func weekBlock(lesson: ResolvedLesson, fields: VisibleLessonFields, foreground: Color,
                           cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: GridPresentation.cellTitle(lesson.subject))
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .strikethrough(cancelled, pattern: .solid, color: foreground)
            if height >= 40 {
                Text(verbatim: model.formatter.time(lesson.startTime))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if height >= 56, let room = fields.room {
                Text(verbatim: room).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
    }
}
