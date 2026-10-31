// The Export sheet (route `export.sheet`, opened from the Timetable ⋯ menu "Export…"). Phase 8 E2.
// Form: Type (Image / PDF / CSV / Excel / Calendar), View (Grid / Week / Day; image and PDF only), Range (This week /
// Current term / Custom dates with From / To). The toolbar "Export" builds the file in the temporary folder and opens the
// system share sheet (UIActivityViewController) for it. Pro gate: `ProFeature.exports` (all-access for now): without it
// the button is disabled and a footer says why.
// Logic is in TimetableUI `ExportPlan` (Linux-tested); writers are TimetableCore `CSVExport` / `ICSExport` / `XLSXExport`.
// HIG: sheets.md, pickers.md (menu pickers for short lists), sharing via the share sheet (activity view).
// States: no lessons in the range → the Export button stays enabled but the footer warns "No lessons in this range."
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
            .environment(\.timeZone, model.calendarContext.timeZone)
            .navigationTitle(Text("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("editor.common.cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await export() } } label: { Text("export.action") }
                        .disabled(isWorking || !allowed || model.activeTimetable == nil)
                }
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .alert(Text("export.failed.title"), isPresented: $failed) {
                Button(role: .cancel) {} label: { Text("export.failed.ok") }
            } message: { Text("export.failed.message") }
        }
        .sheet(item: $shared) { file in
            ActivityView(url: file.url) { shared = nil }
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

    private func export() async {
        guard allowed, let timetable = model.activeTimetable, let database = model.database,
              let resolver = model.resolver(for: timetable.id) else { return }
        isWorking = true
        defer { isWorking = false }
        await Task.yield()   // let the progress indicator appear before the main-actor render
        let range = range
        let suffix = ExportPlan.fileSuffix(choice, range: range, termName: currentTermName, renderer: model.renderer)
        let name = ExportPlan.fileName(timetable: timetable.name, suffix: suffix, ext: kind.fileExtension)
        let data: Data?
        switch kind {
        case .image, .pdf:
            let pages = ExportPlan.pages(view: view, range: range, context: context, enabledDays: timetable.enabledDays)
            let job = ExportPrintJob(model: model, timetable: timetable, resolver: resolver, view: view, pages: pages)
            data = kind == .pdf ? job.pdfData() : job.pngData()
        case .csv, .excel, .calendar:
            let rows = ExportRows.build(database: database, timetableID: timetable.id, range: range, context: context)
            let labels = ExportPlan.labels(renderer: model.renderer)
            switch kind {
            case .csv: data = CSVExport.data(rows: rows, labels: labels)
            case .excel: data = XLSXExport.data(rows: rows, labels: labels, sheetName: String(timetable.name.prefix(31)))
            default:
                var fixed = false
                if case .fixed = model.settings.timeZoneMode { fixed = true }
                data = ICSExport.data(rows: rows, labels: labels, timeZone: fixed ? context.timeZone : nil, stamp: .now,
                                      calendarName: timetable.name)
            }
        }
        guard let data, let url = write(data, name: name) else { failed = true; return }
        shared = SharedFile(url: url)
    }

    /// Writes into a fresh temporary folder so the share sheet shows the sanitised name.
    private func write(_ data: Data, name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
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
