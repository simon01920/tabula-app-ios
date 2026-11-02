// The Vision adapter of the photo import (Phase 9 I2, AI_IMPORT pipeline steps 1–2): one upright picture in,
// one `RecognizedTable` (TimetableCore) out. Runs off the main actor (`@concurrent`).
//   1. `RecognizeDocumentsRequest` (iOS 26): the table with the most cells becomes `cells` (row/column ranges → spans,
//      the cell's lines joined with "\n", the lowest top-candidate confidence, the box converted to a top-left origin).
//   2. No table (or a single row/column): `RecognizeTextRequest` (the Swift form of VNRecognizeTextRequest, accurate,
//      language correction off so room numbers stay as printed) → loose `lines`; TimetableCore clusters them.
// Derived from the Phase 0 probe (Debug/ImportProbes.swift). API names checked in iPhoneOS27.0.sdk
// Vision.swiftinterface (2026-11-02): RecognizeDocumentsRequest() → [DocumentObservation]; DocumentObservation
// .document.tables; Table.rows [[Cell]], Cell.rowRange / .columnRange (ClosedRange<Int>), Cell.content.text.lines
// ([RecognizedTextObservation]), .transcript, .boundingRegion.boundingBox (NormalizedRect, lower-left origin);
// RecognizedTextObservation.topCandidates(_:), .boundingBox, .recognitionLanguages; RecognizeTextRequest
// .recognitionLevel (.accurate), .usesLanguageCorrection; ImageProcessingRequest.perform(on: CGImage, orientation:).
import CoreGraphics
import Foundation
import TimetableCore
import Vision

enum VisionTableReader {
    enum Failure: Error { case noImage, nothingFound }

    /// Reads `image`. Throws `CancellationError` when the task is cancelled between the two requests.
    @concurrent
    static func read(_ image: CGImage) async throws -> RecognizedTable {
        let width = Double(image.width), height = Double(image.height)
        let documents = try await RecognizeDocumentsRequest().perform(on: image, orientation: .up)
        try Task.checkCancellation()
        let tables = documents.flatMap { $0.document.tables }
        if let table = tables.max(by: { cellCount($0) < cellCount($1) }), table.rows.count > 1, (table.rows.first?.count ?? 0) > 1 {
            let cells = recognizedCells(table)
            if cells.contains(where: { !$0.text.isEmpty }) {
                return RecognizedTable(pageWidth: width, pageHeight: height,
                                       languages: languages(documents.flatMap { $0.document.text.lines }), cells: cells)
            }
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image, orientation: .up)
        try Task.checkCancellation()
        let lines = observations.compactMap { observation -> RecognizedLine? in
            guard let best = observation.topCandidates(1).first, !best.string.isEmpty else { return nil }
            return RecognizedLine(text: best.string, box: topLeft(observation.boundingBox), confidence: Double(best.confidence))
        }
        guard !lines.isEmpty else { throw Failure.nothingFound }
        return RecognizedTable(pageWidth: width, pageHeight: height, languages: languages(observations), lines: lines)
    }

    private static func cellCount(_ table: DocumentObservation.Container.Table) -> Int {
        table.rows.reduce(0) { $0 + $1.count }
    }

    /// One `RecognizedCell` per Vision cell; a merged cell listed in several rows is kept once.
    private static func recognizedCells(_ table: DocumentObservation.Container.Table) -> [RecognizedCell] {
        var seen = Set<[Int]>()
        var cells: [RecognizedCell] = []
        for cell in table.rows.joined() {
            let key = [cell.rowRange.lowerBound, cell.columnRange.lowerBound]
            guard seen.insert(key).inserted else { continue }
            let lines = cell.content.text.lines
            let text = lines.isEmpty ? cell.content.text.transcript : lines.map(\.transcript).joined(separator: "\n")
            let confidences = lines.compactMap { $0.topCandidates(1).first?.confidence }
            cells.append(RecognizedCell(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                row: cell.rowRange.lowerBound, column: cell.columnRange.lowerBound,
                rowSpan: cell.rowRange.count, columnSpan: cell.columnRange.count,
                box: topLeft(cell.content.boundingRegion.boundingBox),
                confidence: Double(confidences.min() ?? 1)))
        }
        return cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    /// Vision's lower-left normalised rectangle as TimetableCore's top-left one.
    private static func topLeft(_ rect: Vision.NormalizedRect) -> TimetableCore.NormalizedRect {
        TimetableCore.NormalizedRect(x: Double(rect.origin.x), y: Double(1 - rect.origin.y - rect.height),
                                     width: Double(rect.width), height: Double(rect.height))
    }

    /// The languages Vision recognised in, BCP-47, most frequent first.
    private static func languages(_ lines: [RecognizedTextObservation]) -> [String] {
        var counts: [String: Int] = [:]
        for line in lines { for language in line.recognitionLanguages { counts[language.minimalIdentifier, default: 0] += 1 } }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}
