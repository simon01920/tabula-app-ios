// COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629); on-device run pending (docs/spikes/LLM_RUNTIME.md).
//
// Phase 0 import-feasibility probes (docs/specs/AI_IMPORT.md), shown inside the app's debug screen:
//   (a) OCR languages supported by Vision RecognizeDocumentsRequest (and RecognizeTextRequest, for comparison),
//       flagged against our 12 launch languages (sr and zh split by script);
//   (b) PhotosPicker -> RecognizeDocumentsRequest on the chosen image: tables found, rows x cols of the first
//       table, first 20 cells with min line confidence, elapsed ms;
//   (c) Foundation Models: availability + reason, supported languages, device locale + per-language support;
//   (d) os_proc_available_memory() snapshot (budget for the local LLM, AI_IMPORT.md Tier B).
// Developer diagnostics only: every string uses Text(verbatim:) so nothing is extracted into String Catalogs.
// API names verified against developer.apple.com JSON docs on 2026-10-04 (URLs in docs/spikes/LLM_RUNTIME.md).
// Minimum OS iOS 26.0; nothing iOS 27-only is called (the iOS 27 image-attachment API is only reported via #available).

// No macros in the default build (CLAUDE.md rule 5): `@State` is a SwiftUI macro in the Xcode 27 SDK, so state
// lives in an ObservableObject owned via `@StateObject` (property wrappers only).

// Compiled only in DEBUG builds (PHASE2_PLAN §0.2): Release archives/TestFlight contain no probe code.
#if DEBUG
import Combine
import FoundationModels
import ImageIO
import os
import PhotosUI
import SwiftUI
import Vision

struct ImportProbesSection: View {
    // @StateObject (not @ObservedObject): this view creates and owns the model, and SwiftUI must keep the same
    // instance (and any in-flight OCR result) across re-renders of the parent List.
    @StateObject private var model = ImportProbeModel()

    var body: some View {
        Group {
            languagesSection
            documentSection
            foundationModelsSection
            memorySection
            Section {
                ShareLink(item: reportText) {
                    Label { Text(verbatim: "Share probe report (plain text)") } icon: { Image(systemName: "square.and.arrow.up") }
                }
            } footer: {
                Text(verbatim: "Paste the report into docs/ENVIRONMENT.md / the Phase 0 gate report as on-device evidence.")
            }
        }
        .task {
            await model.loadStaticProbes()
        }
        .task(id: model.pickedItem) {
            // Re-runs (and cancels the previous run) whenever the picker selection changes.
            guard let item = model.pickedItem else { return }
            await model.recognize(item)
        }
    }

    // MARK: (a) OCR languages

    private var languagesSection: some View {
        Section {
            if let report = model.ocrLanguages {
                ForEach(report.flags) { flag in
                    LabeledContent {
                        Text(verbatim: "documents: \(yesNo(flag.document)) · text: \(yesNo(flag.text))")
                    } label: {
                        Text(verbatim: flag.id)
                    }
                    .accessibilityElement(children: .combine)
                }
                DisclosureGroup {
                    Text(verbatim: report.documentLanguages.joined(separator: ", ")).textSelection(.enabled)
                } label: {
                    Text(verbatim: "RecognizeDocumentsRequest: \(report.documentLanguages.count) languages")
                }
                DisclosureGroup {
                    Text(verbatim: report.textLanguages.joined(separator: ", ")).textSelection(.enabled)
                } label: {
                    Text(verbatim: "RecognizeTextRequest: \(report.textLanguages.count) languages")
                }
            } else {
                ProgressView()
            }
        } header: {
            Text(verbatim: "OCR languages (Vision)")
        } footer: {
            Text(verbatim: "Runtime values of supportedRecognitionLanguages. \"NO\" means OCR for that language must be measured on fixtures before we rely on it.")
        }
    }

    // MARK: (b) RecognizeDocumentsRequest on a picked image

    private var documentSection: some View {
        Section {
            PhotosPicker(selection: $model.pickedItem, matching: .images) {
                Label { Text(verbatim: "Pick a timetable photo or screenshot") } icon: { Image(systemName: "photo") }
            }
            switch model.ocrState {
            case .idle:
                Text(verbatim: "No image selected.")
            case .loading:
                ProgressView { Text(verbatim: "Loading image…") }
            case .running(let bytes):
                ProgressView { Text(verbatim: "Running RecognizeDocumentsRequest on \(bytes) bytes…") }
            case .failed(let message):
                Text(verbatim: message).foregroundStyle(.red).textSelection(.enabled)
            case .done(let summary):
                LabeledContent { Text(verbatim: "\(summary.elapsedMs) ms") } label: { Text(verbatim: "Request time") }
                LabeledContent { Text(verbatim: "\(summary.pixelSize), \(summary.bytes) bytes") } label: { Text(verbatim: "Image") }
                LabeledContent { Text(verbatim: "\(summary.observationCount)") } label: { Text(verbatim: "Document observations") }
                LabeledContent { Text(verbatim: "\(summary.tableCount)") } label: { Text(verbatim: "Tables found") }
                LabeledContent { Text(verbatim: "\(summary.firstTableRows) × \(summary.firstTableColumns)") } label: { Text(verbatim: "First table rows × cols") }
                LabeledContent { Text(verbatim: "\(summary.paragraphCount)") } label: { Text(verbatim: "Paragraphs") }
                ForEach(summary.cells) { cell in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "r\(rangeText(cell.rows)) c\(rangeText(cell.columns)) · conf \(confidenceText(cell.minConfidence))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: cell.text.isEmpty ? "(empty)" : cell.text)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text(verbatim: "RecognizeDocumentsRequest")
        } footer: {
            Text(verbatim: "Default options (automatic language detection, language correction as shipped). Cell confidence = lowest top-candidate confidence of the cell's lines.")
        }
    }

    // MARK: (c) Foundation Models

    private var foundationModelsSection: some View {
        Section {
            if let report = model.modelReport {
                LabeledContent { Text(verbatim: report.availability) } label: { Text(verbatim: "availability") }
                LabeledContent { Text(verbatim: yesNo(report.isAvailable)) } label: { Text(verbatim: "isAvailable") }
                LabeledContent {
                    Text(verbatim: "\(report.currentLocale): \(yesNo(report.currentLocaleSupported))")
                } label: {
                    Text(verbatim: "supportsLocale(.current)")
                }
                ForEach(report.perLanguage) { entry in
                    LabeledContent { Text(verbatim: yesNo(entry.supported)) } label: { Text(verbatim: "supportsLocale(\(entry.id))") }
                }
                DisclosureGroup {
                    Text(verbatim: report.supportedLanguages.joined(separator: ", ")).textSelection(.enabled)
                } label: {
                    Text(verbatim: "supportedLanguages: \(report.supportedLanguages.count)")
                }
                LabeledContent { Text(verbatim: report.imageAttachments) } label: { Text(verbatim: "Image prompts") }
            } else {
                ProgressView()
            }
        } header: {
            Text(verbatim: "Foundation Models (Tier A bonus)")
        } footer: {
            Text(verbatim: "Language support also depends on the device language and Apple Intelligence settings; re-check after changing them.")
        }
    }

    // MARK: (d) Memory

    private var memorySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: model.availableMemoryMB.map { "\($0) MB" } ?? "…")
            } label: {
                Text(verbatim: "os_proc_available_memory()")
            }
            LabeledContent {
                Text(verbatim: "\(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
            } label: {
                Text(verbatim: "physicalMemory")
            }
        } header: {
            Text(verbatim: "Memory budget")
        } footer: {
            Text(verbatim: "Advisory snapshot (do not cache). Compare with and without the increased-memory-limit entitlement.")
        }
    }

    // MARK: Report

    private var reportText: String {
        var lines: [String] = []
        lines.append("Tabula ImportProbes report \(Date.now.formatted(.iso8601))")
        lines.append("os: \(ProcessInfo.processInfo.operatingSystemVersionString); locale: \(Locale.current.identifier); preferred: \(Locale.preferredLanguages.prefix(3).joined(separator: ","))")
        if let report = model.ocrLanguages {
            lines.append("[ocr] RecognizeDocumentsRequest (\(report.documentLanguages.count)): \(report.documentLanguages.joined(separator: ","))")
            lines.append("[ocr] RecognizeTextRequest (\(report.textLanguages.count)): \(report.textLanguages.joined(separator: ","))")
            lines.append("[ocr] flags: " + report.flags.map { "\($0.id)=doc:\(yesNo($0.document))/text:\(yesNo($0.text))" }.joined(separator: " "))
        }
        switch model.ocrState {
        case .done(let s):
            lines.append("[doc] \(s.elapsedMs) ms, image \(s.pixelSize) \(s.bytes) B, observations \(s.observationCount), tables \(s.tableCount), first \(s.firstTableRows)x\(s.firstTableColumns), paragraphs \(s.paragraphCount)")
            for cell in s.cells {
                lines.append("[doc]   r\(rangeText(cell.rows)) c\(rangeText(cell.columns)) conf=\(confidenceText(cell.minConfidence)) \"\(cell.text.replacingOccurrences(of: "\n", with: " ⏎ "))\"")
            }
        case .failed(let message):
            lines.append("[doc] failed: \(message)")
        default:
            lines.append("[doc] not run")
        }
        if let m = model.modelReport {
            lines.append("[fm] availability=\(m.availability) isAvailable=\(m.isAvailable) current(\(m.currentLocale))=\(yesNo(m.currentLocaleSupported))")
            lines.append("[fm] per-language: " + m.perLanguage.map { "\($0.id)=\(yesNo($0.supported))" }.joined(separator: " "))
            lines.append("[fm] supportedLanguages (\(m.supportedLanguages.count)): \(m.supportedLanguages.joined(separator: ","))")
            lines.append("[fm] image prompts: \(m.imageAttachments)")
        }
        lines.append("[mem] available=\(model.availableMemoryMB.map(String.init) ?? "?") MB physical=\(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
        return lines.joined(separator: "\n")
    }
}

// MARK: - View model (ObservableObject/@Published: property wrappers, no macros)

/// Main-actor state holder. Heavy work (Vision, Foundation Models, image decoding) runs in the `@concurrent`
/// `ProbeRunner` helpers, which return Sendable values; this class only assigns those results on the main actor.
/// File-private: its @Published properties use the file-private report types below.
@MainActor
private final class ImportProbeModel: ObservableObject {
    @Published var pickedItem: PhotosPickerItem?
    @Published private(set) var ocrLanguages: OCRLanguageReport?
    @Published private(set) var ocrState: OCRState = .idle
    @Published private(set) var modelReport: ModelReport?
    @Published private(set) var availableMemoryMB: Int?

    func loadStaticProbes() async {
        let languages = await ProbeRunner.ocrLanguages()
        ocrLanguages = languages
        let report = await ProbeRunner.foundationModelsReport()
        modelReport = report
        availableMemoryMB = ProbeRunner.availableMemoryMB()
    }

    func recognize(_ item: PhotosPickerItem) async {
        ocrState = .loading
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                ocrState = .failed("PhotosPickerItem returned no Data representation")
                return
            }
            ocrState = .running(bytes: data.count)
            let result = await ProbeRunner.recognize(imageData: data)
            ocrState = result
        } catch {
            ocrState = .failed("loadTransferable failed: \(error)")
        }
        availableMemoryMB = ProbeRunner.availableMemoryMB()
    }
}

// MARK: - Probe logic (file-private; no dependencies on other app files)
// Explicitly `nonisolated` so this compiles unchanged if the App target enables default MainActor isolation.

nonisolated private struct LanguageFlag: Sendable, Identifiable {
    let id: String          // our label, e.g. "sr-Latn"
    let document: Bool
    let text: Bool
}

nonisolated private struct OCRLanguageReport: Sendable {
    let documentLanguages: [String]
    let textLanguages: [String]
    let flags: [LanguageFlag]
}

nonisolated private struct CellSample: Sendable, Identifiable {
    let id: Int
    let rows: ClosedRange<Int>
    let columns: ClosedRange<Int>
    let text: String
    let minConfidence: Float?
}

nonisolated private struct OCRSummary: Sendable {
    let elapsedMs: Int
    let bytes: Int
    let pixelSize: String
    let observationCount: Int
    let tableCount: Int
    let firstTableRows: Int
    let firstTableColumns: Int
    let paragraphCount: Int
    let cells: [CellSample]
}

nonisolated private enum OCRState: Sendable {
    case idle
    case loading
    case running(bytes: Int)
    case done(OCRSummary)
    case failed(String)
}

nonisolated private struct LocaleSupport: Sendable, Identifiable {
    let id: String
    let supported: Bool
}

nonisolated private struct ModelReport: Sendable {
    let availability: String
    let isAvailable: Bool
    let currentLocale: String
    let currentLocaleSupported: Bool
    let perLanguage: [LocaleSupport]
    let supportedLanguages: [String]
    let imageAttachments: String
}

nonisolated private enum ProbeRunner {
    struct Target: Sendable {
        let label: String
        let language: String
        let script: String?
    }

    /// The 12 launch languages (docs/specs/LOCALIZATION.md); Serbian and Chinese split by script.
    static let targets: [Target] = [
        Target(label: "en", language: "en", script: nil),
        Target(label: "sk", language: "sk", script: nil),
        Target(label: "cs", language: "cs", script: nil),
        Target(label: "pl", language: "pl", script: nil),
        Target(label: "hu", language: "hu", script: nil),
        Target(label: "ro", language: "ro", script: nil),
        Target(label: "de", language: "de", script: nil),
        Target(label: "fr", language: "fr", script: nil),
        Target(label: "uk", language: "uk", script: nil),
        Target(label: "sr-Latn", language: "sr", script: "Latn"),
        Target(label: "sr-Cyrl", language: "sr", script: "Cyrl"),
        Target(label: "ja", language: "ja", script: nil),
        Target(label: "zh-Hans", language: "zh", script: "Hans"),
        Target(label: "zh-Hant", language: "zh", script: "Hant"),
    ]

    static func matches(_ language: Locale.Language, _ target: Target) -> Bool {
        guard language.languageCode?.identifier == target.language else { return false }
        guard let script = target.script else { return true }
        let resolved = language.script?.identifier
            ?? Locale.Language(identifier: language.maximalIdentifier).script?.identifier
        return resolved == script
    }

    @concurrent
    static func ocrLanguages() async -> OCRLanguageReport {
        let document = RecognizeDocumentsRequest().supportedRecognitionLanguages
        let text = RecognizeTextRequest().supportedRecognitionLanguages
        let flags = targets.map { target in
            LanguageFlag(
                id: target.label,
                document: document.contains { matches($0, target) },
                text: text.contains { matches($0, target) }
            )
        }
        return OCRLanguageReport(
            documentLanguages: document.map(\.maximalIdentifier),
            textLanguages: text.map(\.maximalIdentifier),
            flags: flags
        )
    }

    @concurrent
    static func recognize(imageData: Data) async -> OCRState {
        let request = RecognizeDocumentsRequest()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let observations = try await request.perform(on: imageData, orientation: nil)
            let elapsed = start.duration(to: clock.now)
            return .done(summarize(observations, elapsed: elapsed, imageData: imageData))
        } catch {
            return .failed("RecognizeDocumentsRequest failed after \(milliseconds(start.duration(to: clock.now))) ms: \(error)")
        }
    }

    static func summarize(_ observations: [DocumentObservation], elapsed: Duration, imageData: Data) -> OCRSummary {
        let tables = observations.flatMap { $0.document.tables }
        let first = tables.first
        var cells: [CellSample] = []
        if let first {
            rowLoop: for row in first.rows {
                for cell in row {
                    let confidences = cell.content.text.lines.compactMap { $0.topCandidates(1).first?.confidence }
                    cells.append(CellSample(
                        id: cells.count,
                        rows: cell.rowRange,
                        columns: cell.columnRange,
                        text: cell.content.text.transcript,
                        minConfidence: confidences.min()
                    ))
                    if cells.count >= 20 { break rowLoop }
                }
            }
        }
        return OCRSummary(
            elapsedMs: milliseconds(elapsed),
            bytes: imageData.count,
            pixelSize: pixelSize(of: imageData),
            observationCount: observations.count,
            tableCount: tables.count,
            firstTableRows: first?.rows.count ?? 0,
            firstTableColumns: first?.columns.count ?? 0,
            paragraphCount: observations.reduce(0) { $0 + $1.document.paragraphs.count },
            cells: cells
        )
    }

    @concurrent
    static func foundationModelsReport() async -> ModelReport {
        let model = SystemLanguageModel.default
        let availability: String
        switch model.availability {
        case .available:
            availability = "available"
        case .unavailable(let reason):
            availability = "unavailable: \(describe(reason))"
        }
        let current = Locale.current
        let perLanguage = targets.map { target in
            LocaleSupport(id: target.label, supported: model.supportsLocale(Locale(identifier: target.label)))
        }
        let imageAttachments: String
        if #available(iOS 27.0, *) {
            imageAttachments = "iOS 27+: Attachment(image) API exists on this OS (not exercised by this probe)"
        } else {
            imageAttachments = "needs iOS 27 (Attachment/ImageAttachmentContent are iOS 27.0+)"
        }
        return ModelReport(
            availability: availability,
            isAvailable: model.isAvailable,
            currentLocale: current.identifier,
            currentLocaleSupported: model.supportsLocale(current),
            perLanguage: perLanguage,
            supportedLanguages: model.supportedLanguages.map(\.maximalIdentifier).sorted(),
            imageAttachments: imageAttachments
        )
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "deviceNotEligible"
        case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
        case .modelNotReady: return "modelNotReady"
        @unknown default: return "other (\(String(describing: reason)))"
        }
    }

    static func availableMemoryMB() -> Int {
        Int(os_proc_available_memory() / 1_048_576)
    }
}

nonisolated private func milliseconds(_ duration: Duration) -> Int {
    let parts = duration.components
    return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
}

nonisolated private func pixelSize(of data: Data) -> String {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return "unknown size" }
    return "\(width)×\(height) px"
}

nonisolated private func yesNo(_ value: Bool) -> String { value ? "yes" : "NO" }

nonisolated private func rangeText(_ range: ClosedRange<Int>) -> String {
    range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
}

nonisolated private func confidenceText(_ value: Float?) -> String {
    value.map { String(format: "%.2f", $0) } ?? "n/a"
}
#endif // DEBUG
