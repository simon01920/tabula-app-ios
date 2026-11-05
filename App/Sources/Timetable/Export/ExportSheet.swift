// The Export sheet (route `export.sheet`, opened from the Timetable ⋯ menu "Export…"). Phase 8 E2.
// Form: Type (Image / PDF / CSV / Excel / Calendar), View (Grid / Week / Day; image and PDF only), Range (This week /
// Current term / Custom dates with From / To). The toolbar "Export" builds the file in the temporary folder and opens the
// system share sheet (UIActivityViewController) for it. Pro gate: `ProFeature.exports` (all-access for now): without it
// the button is disabled and a footer says why.
// Logic is in TimetableUI `ExportPlan` (Linux-tested); writers are TimetableCore `CSVExport` / `ICSExport` / `XLSXExport`.
// HIG: sheets.md, pickers.md (menu pickers for short lists), sharing via the share sheet (activity view).
// States: no lessons in the range → the Export button stays enabled but the footer warns "No lessons in this range."
// Phase 10 WP3:
// - B2: the export runs in one `Task` held in `@State`; `isWorking` is set before it starts (a double tap starts one
//   export). Cancel and `onDisappear` (a deep link closing the sheet, `closesForDeepLink`) cancel it; the PDF loop
//   stops at the next page, and nothing is published (no `shared =` on a closed sheet). A file written just before the
//   cancel is removed with its `export-*` folder.
// - B14: the temp folder is removed when the share sheet completes AND when it is dismissed (`onDismiss`), whichever
//   comes first; `clearOldExports` still sweeps leftovers when the sheet opens.
// - C5: CSV / Excel / Calendar are built off the main actor from Sendable values (`TabularExport`, `@concurrent`),
//   with the resolver the app already holds (`ExportRows.build(resolver:range:)`); the file is written off main too.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ExportKind = .pdf
    @State private var view: ExportView = .grid
    @State private var choice: ExportRangeChoice = .thisWeek
    @State private var from: Date
    @State private var to: Date
    @State private var isWorking = false
    @State private var failed = false
    @State private var shared: SharedFile?
    /// The running export (B2): cancelled by Cancel and when the sheet disappears.
    @State private var job: Task<Void, Never>?
    /// The `export-*` folder of the file on the share sheet, removed once (completion or dismissal, B14).
    @State private var sharedFolder: URL?

    init(initialKind: ExportKind = .pdf, initialView: ExportView = .grid, today: Date = .now) {
        _kind = State(initialValue: initialKind)
        _view = State(initialValue: initialView)
        _from = State(initialValue: today)
        _to = State(initialValue: today.addingTimeInterval(6 * 86_400))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $kind) {
                        ForEach(ExportKind.allCases) { Text(LocalizedStringKey($0.nameKey)).tag($0) }
                    } label: { Text("export.type.header") }
                    if kind.showsView {
                        Picker(selection: $view) {
                            ForEach(ExportView.allCases) { Text(LocalizedStringKey($0.nameKey)).tag($0) }
                        } label: { Text("export.view.header") }
                    }
                }
                Section {
                    Picker(selection: $choice) {
                        ForEach(ExportRangeChoice.allCases) { Text(LocalizedStringKey($0.nameKey)).tag($0) }
                    } label: { Text("export.range.header") }
                    if choice == .custom {
                        DatePicker(selection: $from, displayedComponents: .date) { Text("export.range.from") }
                        DatePicker(selection: $to, in: from..., displayedComponents: .date) { Text("export.range.to") }
                    }
                } footer: {
                    footer
                }
            }
            // The pickers show and return days in the timetable's zone (the same zone `localDate(of:)` reads back).
            .environment(\.timeZone, model.calendarContext.timeZone)
            .environment(\.calendar, model.calendarContext.calendar)
            .task { Self.clearOldExports() }
            .navigationTitle(Text("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        cancelExport()
                        dismiss()
                    } label: { Text("editor.common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { startExport() } label: { Text("export.action") }
                        .disabled(isWorking || !allowed || model.activeTimetable == nil)
                }
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .interactiveDismissDisabled(isWorking)   // QA: a swipe mid-render would orphan the PDF task
            .onDisappear { cancelExport() }   // B2: a deep link closes the sheet without Cancel
            .alert(Text("export.failed.title"), isPresented: $failed) {
                Button(role: .cancel) {} label: { Text("export.failed.ok") }
            } message: { Text("export.failed.message") }
        }
        .sheet(item: $shared, onDismiss: removeSharedFolder) { file in
            ActivityView(url: file.url) {
                removeSharedFolder()
                shared = nil
            }
                .presentationDetents([.medium, .large])
        }
        .presentationDetents([.medium, .large])
    }

    private var allowed: Bool { model.entitlements.isAllowed(.exports) }

    @ViewBuilder
    private var footer: some View {
        if !allowed {
            Text("export.pro.footer")
        } else if kind == .image, choice != .thisWeek || view == .day {
            Text("export.image.footer")
        } else if choice == .term, currentTermName == nil {
            Text("export.range.term.footer")
        }
    }

    // MARK: Resolving

    private var context: CalendarContext { model.calendarContext }

    private var liveTerms: [Term] {
        guard let id = model.activeTimetable?.id else { return [] }
        return model.database?.terms.filter { $0.timetableID == id && !$0.isDeleted } ?? []
    }

    private var currentTermName: String? { ExportPlan.currentTerm(liveTerms, today: model.today)?.name }

    private var range: LocalDateRange {
        ExportPlan.range(choice, custom: LocalDateRange(start: context.localDate(of: from), end: context.localDate(of: to)),
                         today: model.today, context: context, terms: liveTerms)
    }

    // MARK: Export

    /// Starts one export; `isWorking` is set first, so a second tap before the task runs does nothing (B2).
    private func startExport() {
        guard !isWorking else { return }
        isWorking = true
        job = Task {
            await export()
            isWorking = false
            job = nil
        }
    }

    private func cancelExport() {
        job?.cancel()
        job = nil
    }

    private func removeSharedFolder() {
        guard let folder = sharedFolder else { return }
        sharedFolder = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func export() async {
        guard allowed, let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) else {
            return
        }
        await Task.yield()   // let the progress indicator appear before the main-actor render
        let range = range
        let suffix = ExportPlan.fileSuffix(choice, range: range, termName: currentTermName, renderer: model.renderer)
        let name = ExportPlan.fileName(timetable: timetable.name, suffix: suffix, ext: kind.fileExtension,
                                       fallback: model.renderer.string(forKey: "export.file.fallback"))
        let data: Data?
        switch kind {
        case .image, .pdf:
            let pages = ExportPlan.pages(view: view, range: range, context: context, enabledDays: timetable.enabledDays)
            let printJob = ExportPrintJob(model: model, timetable: timetable, resolver: resolver, view: view,
                                          pages: pages)
            if kind == .pdf { data = await printJob.pdfData() } else { data = await printJob.pngData() }
        case .csv, .excel, .calendar:
            var fixed = false
            if case .fixed = model.settings.timeZoneMode { fixed = true }
            let request = TabularExport(kind: kind, resolver: resolver, range: range,
                                        labels: ExportPlan.labels(renderer: model.renderer),
                                        sheetName: String(timetable.name.prefix(31)),
                                        timeZone: fixed ? context.timeZone : nil, stamp: .now,
                                        calendarName: timetable.name)
            data = await TabularExport.data(request)
        }
        guard !Task.isCancelled else { return }
        guard let data, let url = await ExportFiles.write(data, name: name) else { failed = true; return }
        guard !Task.isCancelled else {   // closed while writing: nothing to share, nothing left behind
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return
        }
        sharedFolder = url.deletingLastPathComponent()
        shared = SharedFile(url: url)
    }

    /// Removes `export-<UUID>` folders left by earlier exports (a cancelled or crashed share).
    private static func clearOldExports() {
        let temp = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix("export-") { try? FileManager.default.removeItem(at: item) }
    }
}

/// The inputs of a CSV / Excel / Calendar file: Sendable values only, so the build runs off the main actor (C5).
private struct TabularExport: Sendable {
    let kind: ExportKind
    let resolver: ScheduleResolver
    let range: LocalDateRange
    let labels: ExportLabels
    let sheetName: String
    let timeZone: TimeZone?
    let stamp: Date
    let calendarName: String

    /// Resolves up to `ExportPlan.maximumDays` days and writes the file (XLSX: deflate) away from the main actor.
    @concurrent
    static func data(_ request: TabularExport) async -> Data? {
        let rows = ExportRows.build(resolver: request.resolver, range: request.range)
        guard !Task.isCancelled else { return nil }
        switch request.kind {
        case .csv: return CSVExport.data(rows: rows, labels: request.labels)
        case .excel: return XLSXExport.data(rows: rows, labels: request.labels, sheetName: request.sheetName)
        case .calendar:
            return ICSExport.data(rows: rows, labels: request.labels, timeZone: request.timeZone, stamp: request.stamp,
                                  calendarName: request.calendarName)
        case .image, .pdf: return nil
        }
    }
}

enum ExportFiles {
    /// Writes into a fresh temporary `export-<UUID>` folder (so the share sheet shows the sanitised name), off the
    /// main actor.
    @concurrent
    static func write(_ data: Data, name: String) async -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for one file.
private struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onDone() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
