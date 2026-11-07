// Image and PDF export (Phase 8 E2): the EXISTING grid / week / day views drawn in a print layout and rasterised with
// `ImageRenderer` (iOS 16+; `render(rasterizationScale:renderer:)` and `uiImage` checked in the SwiftUICore interface
// of the SDK, 2026-10-31).
// Print layout = light scheme, Large text, fixed page size (A4 points: 842 × 595 landscape for grid and week, 595 × 842
// portrait for day), no today / now markers (today = `LocalDate.earliest`, minute -1), no interaction. The views are not
// forked: they get no-op callbacks. One page per week (grid, week) or per enabled day (day).
// PDF: one `CGContext` PDF with a page per `ImageRenderer.render` call. Image: the pages stacked in one PNG (at most
// `ExportPlan.maximumImagePages`).
// Phase 10 WP3:
// - P1/B13: the PNG scale is 3 only while the bitmap stays within `ExportPageFit.imagePixelBudget` (12 MP); more
//   pages get a lower scale (6 pages: 1.99). `ImageRenderer.cgImage` is taken on the main actor (ImageRenderer is
//   `@MainActor`); the PNG is encoded with ImageIO off the main actor (`ExportPNGEncoder`, `@concurrent`).
// - B2: the PDF loop stops at the next page when its task is cancelled (Cancel, a deep link, the sheet closing) and
//   returns nil, so the sheet publishes nothing.
// - B1 (P10-4): in export, `ExportAwareScroll` reports the height left on the page (`exportAvailableHeight`); the
//   time-block canvas fits its hours into it.
// APIs checked in Apple's documentation JSON (2026-11-05): `ImageRenderer.cgImage` (`@MainActor final var cgImage:
//   CGImage?`, iOS 16), `CGImageDestinationCreateWithData(_:_:_:_:)`, `CGImageDestinationAddImage(_:_:_:)`,
//   `CGImageDestinationFinalize(_:)` (iOS 4); `CGImage` conforms to `Sendable`.
// Unverifiable without a device: ImageRenderer with GeometryReader / ScrollView content (docs/checklists/PHASE8_DEVICE.md).
import ImageIO
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit
import UniformTypeIdentifiers

/// `true` inside an export page: scroll wrappers are dropped (ImageRenderer does not draw UIKit-backed scroll views);
/// the page frame is fixed, so the views' GeometryReaders read the page size.
private struct IsExportRenderingKey: EnvironmentKey { static let defaultValue = false }

/// On an export page: the height `ExportAwareScroll` has for its content (`nil` on screen).
private struct ExportAvailableHeightKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }

extension EnvironmentValues {
    var isExportRendering: Bool {
        get { self[IsExportRenderingKey.self] }
        set { self[IsExportRenderingKey.self] = newValue }
    }

    var exportAvailableHeight: CGFloat? {
        get { self[ExportAvailableHeightKey.self] }
        set { self[ExportAvailableHeightKey.self] = newValue }
    }
}

/// A vertical `ScrollView`, or plain stacked content when exporting (top-aligned in the space left on the page, whose
/// height the content can read as `exportAvailableHeight`).
struct ExportAwareScroll<Content: View>: View {
    @Environment(\.isExportRendering) private var exporting
    @ViewBuilder let content: () -> Content

    var body: some View {
        if exporting {
            GeometryReader { proxy in
                VStack(spacing: 0) { content() }
                    .environment(\.exportAvailableHeight, proxy.size.height)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        } else {
            ScrollView(.vertical) { content() }
        }
    }
}

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
            .environment(\.isExportRendering, true)
    }

    /// One PDF, one page per entry of `pages`.
    @MainActor
    func pdfData() async -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for date in pages {
            await Task.yield()   // a long PDF must not freeze the progress indicator between pages
            guard !Task.isCancelled else { return nil }   // B2: Cancel / a deep link stops at the next page
            let renderer = ImageRenderer(content: pageView(date))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        guard !Task.isCancelled else { return nil }
        return data.length > 0 ? data as Data : nil
    }

    /// The pages stacked in one PNG: rasterised here (main actor), encoded off the main actor.
    @MainActor
    func pngData() async -> Data? {
        guard let bitmap = pngBitmap(), !Task.isCancelled else { return nil }
        return await ExportPNGEncoder.encode(bitmap)
    }

    /// The stacked pages as one bitmap, at the scale the pixel budget allows.
    @MainActor
    private func pngBitmap() -> CGImage? {
        let shown = Array(pages.prefix(ExportPlan.maximumImagePages))
        guard !shown.isEmpty else { return nil }
        let stack = VStack(spacing: 0) { ForEach(shown, id: \.self) { pageView($0) } }
        let renderer = ImageRenderer(content: stack)
        renderer.scale = CGFloat(ExportPageFit.imageScale(width: Double(pageSize.width),
                                                          height: Double(pageSize.height) * Double(shown.count)))
        renderer.isOpaque = true
        return renderer.cgImage
    }
}

/// PNG encoding with ImageIO, off the main actor (encoding a multi-megapixel bitmap takes noticeable time).
enum ExportPNGEncoder {
    @concurrent
    static func encode(_ image: CGImage) async -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData,
                                                                 UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
        return data as Data
    }
}

#if DEBUG
/// Debug route `export.preview`: the current week as the grid, rendered by the real export path and shown as the PNG
/// image the share sheet would carry (proof that ImageRenderer draws the views, on a device).
struct ExportPreviewRouteView: View {
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?
    @State private var renderFailed = false

    /// The model loads asynchronously; the task re-runs once the active timetable and its resolver exist.
    private var readyID: Timetable.ID? {
        guard let timetable = model.activeTimetable, model.resolver(for: timetable.id) != nil else { return nil }
        return timetable.id
    }

    var body: some View {
        ScrollView {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else if renderFailed {
                Text("export.failed.title").padding()
            } else {
                ContentUnavailableView {
                    Label { Text("timetable.route.nothingToShow") } icon: { Image(systemName: "tray") }
                } description: { EmptyView() } actions: { EmptyView() }
            }
        }
        .task(id: readyID) {
            guard let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) else { return }
            let week = resolver.context.startOfWeek(containing: model.today)
            let job = ExportPrintJob(model: model, timetable: timetable, resolver: resolver, view: .grid, pages: [week])
            image = await job.pngData().flatMap(UIImage.init(data:))
            renderFailed = image == nil
        }
    }
}
#endif

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
            TimetableGridView(layout: layout, strip: strip, timetable: timetable,
                              reasons: reasons(layout.columns.map(\.date)), today: .earliest, nowMinute: -1,
                              onOpen: { _ in }, onAdd: { _ in })
        case .week:
            TimeBlockWeekView(layout: TimeBlockLayout.week(containing: weekStart, resolver: resolver), strip: strip,
                              timetable: timetable, reasons: reasons(strip.days.map(\.date)), today: .earliest,
                              nowMinute: -1, onOpen: { _ in }, fallback: { EmptyView() })   // a page is never too narrow
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
