// Image and PDF export (Phase 8 E2): the EXISTING grid / week / day views drawn in a print layout and rasterised with
// `ImageRenderer` (iOS 16+; `render(rasterizationScale:renderer:)` and `uiImage` checked in the SwiftUICore interface
// of the SDK, 2026-10-31).
// Print layout = light scheme, Large text, fixed page size (A4 points: 842 × 595 landscape for grid and week, 595 × 842
// portrait for day), no today / now markers (today = `LocalDate.earliest`, minute -1), no interaction. The views are not
// forked: they get no-op callbacks. One page per week (grid, week) or per enabled day (day).
// PDF: one `CGContext` PDF with a page per `ImageRenderer.render` call. Image: the pages stacked in one PNG at scale 3
// (at most `ExportPlan.maximumImagePages`, so the bitmap stays below 16 384 px).
// Unverifiable without a device: ImageRenderer with GeometryReader / ScrollView content (docs/checklists/PHASE8_DEVICE.md).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct ExportPrintJob {
    let model: AppModel
    let timetable: Timetable
    let resolver: ScheduleResolver
    let view: ExportView
    /// First day of every page.
    let pages: [LocalDate]

    /// A4 in points.
    var pageSize: CGSize { view == .day ? CGSize(width: 595, height: 842) : CGSize(width: 842, height: 595) }

    @MainActor
    func pageView(_ date: LocalDate) -> some View {
        ExportPageView(timetable: timetable, resolver: resolver, view: view, date: date, size: pageSize)
            .environment(model)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    /// One PDF, one page per entry of `pages`.
    @MainActor
    func pdfData() -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for date in pages {
            let renderer = ImageRenderer(content: pageView(date))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data.length > 0 ? data as Data : nil
    }

    /// The pages stacked in one PNG.
    @MainActor
    func pngData() -> Data? {
        let shown = Array(pages.prefix(ExportPlan.maximumImagePages))
        guard !shown.isEmpty else { return nil }
        let stack = VStack(spacing: 0) { ForEach(shown, id: \.self) { pageView($0) } }
        let renderer = ImageRenderer(content: stack)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

/// One printed page: title line, then the unchanged timetable view.
private struct ExportPageView: View {
    let timetable: Timetable
    let resolver: ScheduleResolver
    let view: ExportView
    let date: LocalDate
    let size: CGSize

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: timetable.name).font(.title3.bold())
                Text(verbatim: span).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            content
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .allowsHitTesting(false)
    }

    private var weekStart: LocalDate { resolver.context.startOfWeek(containing: date) }

    private var span: String {
        let formatter = model.formatter
        if view == .day { return formatter.date(date, style: .full) }
        let days = TimetableSelection.shownDays(weekStart: weekStart, resolver: resolver)
        let first = days.first ?? weekStart
        let last = days.last ?? weekStart.adding(days: 6)
        return model.renderer.format(key: "export.range.span", arguments: [
            .text(formatter.date(first, style: .dayMonth)), .text(formatter.date(last, style: .dayMonth))])
    }

    @ViewBuilder
    private var content: some View {
        let selection = TimetableSelection(weekStart: weekStart, selectedDate: date)
        let strip = WeekStripModel.make(selection: selection, today: .earliest, resolver: resolver)
        switch view {
        case .grid:
            let layout = TimetableCore.GridLayout.week(containing: weekStart, resolver: resolver)
            GridWeekView(layout: layout, strip: strip, timetable: timetable,
                         reasons: reasons(layout.columns.map(\.date)), today: .earliest, nowMinute: -1,
                         onOpen: { _ in }, onAdd: { _ in })
        case .week:
            TimeBlockWeekView(layout: TimeBlockLayout.week(containing: weekStart, resolver: resolver), strip: strip,
                              timetable: timetable, reasons: reasons(strip.days.map(\.date)), today: .earliest,
                              nowMinute: -1, onOpen: { _ in })
        case .day:
            TimeBlockDayView(layout: TimeBlockLayout.make(days: [resolver.resolution(for: date).schedule]),
                             timetable: timetable, reasons: reasons([date]), today: .earliest, nowMinute: -1,
                             onOpen: { _ in })
        }
    }

    private func reasons(_ dates: [LocalDate]) -> [OccurrenceID: [ModificationReason]] {
        var result: [OccurrenceID: [ModificationReason]] = [:]
        for date in dates {
            for change in resolver.resolution(for: date).changes { result[change.occurrenceID] = change.reasons }
        }
        return result
    }
}
