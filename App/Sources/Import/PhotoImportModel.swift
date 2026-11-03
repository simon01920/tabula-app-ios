// The photo import pipeline (Phase 9 I2): picture → Vision (`VisionTableReader`) → deterministic parser
// (`TimetableImportParser`) → Tier A when available (`FoundationModelsNormaliser` via `ImportReconciliation`) →
// `ImportReview` (TimetableUI). One task at a time; Cancel cancels it and returns to the capture choices. Nothing is
// written here: the review's Approve hands a payload to the share import path (ShareImportPreview).
// Main actor state only; Vision, decoding and parsing run in `@concurrent` helpers.
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
        case choosingPage(Data)
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

    /// A PDF file: one page goes straight on; several pages ask first.
    func open(pdf data: Data, knownSubjects: [String], defaultName: String) {
        guard let count = ImportImageLoader.pageCount(pdf: data), count > 0 else {
            problemKey = "import.error.unreadable"
            return
        }
        if count == 1 {
            start(.pdf(data, page: 0), knownSubjects: knownSubjects, defaultName: defaultName)
        } else {
            stage = .choosingPage(data)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
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
