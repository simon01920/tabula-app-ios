// The photo import pipeline (Phase 9 I2): picture → Vision (`VisionTableReader`) → deterministic parser
// (`TimetableImportParser`) → Tier A when available (`FoundationModelsNormaliser` via `ImportReconciliation`) →
// `ImportReview` (TimetableUI). One task at a time; Cancel cancels it and returns to the capture choices. Nothing is
// written here: the review's Approve hands a payload to the share import path (ShareImportPreview).
// Main actor state only; Vision, decoding and parsing run in `@concurrent` helpers.
// Phase 10 WP3 (P10): a file from Files is read and, for a PDF, inspected off the main actor (`open(file:)`); the same
// task slot as the pipeline, so Cancel, a new source or the sheet closing stops it. `isOpeningFile` shows a spinner.
import Foundation
import Observation
import TimetableCore
import TimetableUI
import UIKit

@MainActor
@Observable
final class PhotoImportModel {
    enum Stage: Equatable {
        case capture
        /// A multi-page PDF: which page?
        case choosingPage(Data, pageCount: Int)
        case processing
        case review
    }

    /// Where the picture comes from.
    enum Source {
        case image(UIImage)
        case imageData(Data)
        case pdf(Data, page: Int)
    }

    var stage: Stage = .capture
    private(set) var step: ImportStep = .reading
    /// The picture being read (upright, downscaled): shown while processing and beside the review grid.
    private(set) var image: UIImage?
    /// What Vision saw (cell boxes for the highlights on the image).
    private(set) var table: RecognizedTable?
    var review: ImportReview?
    private(set) var usedAppleIntelligence = false
    /// Catalog key of a problem to show (the capture screen stays).
    var problemKey: String?
    /// A picked file is being read or inspected (capture screen spinner).
    private(set) var isOpeningFile = false
    /// A/B weeks: the user's answer to "Which week is A?" (`true` = this week); `nil` until answered. Approve needs it.
    var weekAIsThisWeek: Bool?
    /// Review section to scroll to when the review first appears (`"grid"`, `"questions"`; screenshot routes).
    @ObservationIgnored var initialAnchor: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    init() {}

    /// A finished state (DEBUG screenshot routes and previews).
    init(stage: Stage, step: ImportStep = .reading, image: UIImage?, table: RecognizedTable?, review: ImportReview?) {
        self.stage = stage
        self.step = step
        self.image = image
        self.table = table
        self.review = review
    }

    /// The import's own pipeline; `knownSubjects` are the user's subject names (abbreviation questions).
    func start(_ source: Source, knownSubjects: [String], defaultName: String) {
        task?.cancel()
        isOpeningFile = false
        problemKey = nil
        step = .reading
        image = nil
        stage = .processing
        let usesAI = AppleIntelligenceStatus.current == .available
        usedAppleIntelligence = usesAI
        task = Task {
            await run(source, options: ImportParserOptions(knownSubjects: knownSubjects), usesAI: usesAI, defaultName: defaultName)
        }
    }

    /// A file picked in Files: read (and for a PDF inspected) off the main actor; an image or a one-page PDF goes
    /// straight on, several pages ask first.
    func open(file url: URL, isPDF: Bool, knownSubjects: [String], defaultName: String) {
        task?.cancel()
        problemKey = nil
        isOpeningFile = true
        task = Task {
            guard let data = await ImportImageLoader.readPicked(url) else {
                guard !Task.isCancelled else { return }
                return failOpening("import.error.unreadable")
            }
            guard !Task.isCancelled else { return }
            guard isPDF else {
                return start(.imageData(data), knownSubjects: knownSubjects, defaultName: defaultName)
            }
            let inspection = await ImportImageLoader.inspect(pdf: data)
            guard !Task.isCancelled else { return }
            switch inspection {
            case .unreadable: failOpening("import.error.unreadable")
            case .locked: failOpening("import.error.pdfLocked")
            case .pages(1): start(.pdf(data, page: 0), knownSubjects: knownSubjects, defaultName: defaultName)
            case .pages(let count):
                isOpeningFile = false
                stage = .choosingPage(data, pageCount: count)
            }
        }
    }

    private func failOpening(_ key: String) {
        isOpeningFile = false
        problemKey = key
    }

    func cancel() {
        task?.cancel()
        task = nil
        isOpeningFile = false
        stage = .capture
    }

    private func run(_ source: Source, options: ImportParserOptions, usesAI: Bool, defaultName: String) async {
        let picture: ImportImage?
        switch source {
        case .image(let image): picture = await ImportImageLoader.normalise(image)
        case .imageData(let data): picture = await ImportImageLoader.image(from: data)
        case .pdf(let data, let page): picture = await ImportImageLoader.render(pdf: data, pageIndex: page)
        }
        guard !Task.isCancelled else { return }
        guard let picture, let cgImage = picture.cgImage else { return fail("import.error.unreadable") }
        image = picture.image

        step = .finding
        let table: RecognizedTable
        do {
            table = try await VisionTableReader.read(cgImage)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }   // QA: a cancelled import must not raise an alert
            return fail("import.error.noText")
        }
        guard !Task.isCancelled else { return }
        self.table = table

        step = .understanding
        var candidate = await Self.parse(table, options: options)
        if usesAI, FoundationModelsNormaliser.canRun(languages: candidate.languages) {
            candidate = await ImportReconciliation.normalise(candidate, using: FoundationModelsNormaliser(), options: options)
        } else {
            usedAppleIntelligence = false
        }
        guard !Task.isCancelled else { return }
        guard !candidate.lessons.isEmpty else {
            return fail(candidate.notices.first.map(\.l10nKey) ?? "import.error.noLessons")
        }
        review = ImportReview(candidate: candidate, timetableName: defaultName)
        stage = .review
    }

    @concurrent
    private static func parse(_ table: RecognizedTable, options: ImportParserOptions) async -> ImportCandidate {
        TimetableImportParser.parse(table, options: options)
    }

    private func fail(_ key: String) {
        problemKey = key
        stage = .capture
    }
}
