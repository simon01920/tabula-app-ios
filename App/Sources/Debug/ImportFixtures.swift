// DEBUG fixtures of the photo import (Phase 9 I2): the Slovak aSc-style table (days as rows Po–Pi, periods 1–8 with
// start–end times, rooms under the subject, one double lesson) as a `RecognizedTable` with realistic OCR flaws
// ("2O4", a low-confidence cell, an unsplit cell, abbreviations of known subjects), and a picture of it drawn from the
// same cell boxes, so the review's highlights line up. Used by the `import.*` screenshot routes and the developer
// screen's "Run import on the sample picture" (the real Vision → parser pipeline on this picture).
#if DEBUG
import SwiftUI
import TimetableCore
import TimetableUI

enum ImportFixtures {
    static let knownSubjects = ["Matematika", "Biológia", "Fyzika"]

    static let periodTimes = ["8:00 - 8:45", "8:55 - 9:40", "10:00 - 10:45", "10:55 - 11:40", "11:50 - 12:35",
                              "12:45 - 13:30", "13:40 - 14:25", "14:30 - 15:15"]

    /// One row per day: (cell text, column span, OCR confidence).
    static let rows: [(day: String, cells: [(String, Int, Double)])] = [
        ("Po", [("SJL\n204", 1, 0.97), ("MAT\n204", 1, 0.96), ("ANJ\n31", 1, 0.95), ("DEJ\n204", 1, 0.94),
                ("TSV\nTel", 1, 0.9), ("FYZ\n112", 1, 0.95), ("", 1, 1), ("", 1, 1)]),
        ("Ut", [("MAT\n204", 1, 0.96), ("CHE\n108", 1, 0.95), ("SJL\n204", 1, 0.96), ("GEO\n204", 1, 0.93),
                ("INF\nUč3", 2, 0.91), ("NBV\n204", 1, 0.9), ("", 1, 1)]),
        ("St", [("ANJ\n31", 1, 0.95), ("MAT\n204", 1, 0.96), ("FYZ\n2O4", 1, 0.48), ("Bio\n105", 1, 0.93),
                ("SJL\n204", 1, 0.95), ("TSV\nTel", 1, 0.9), ("", 1, 1), ("", 1, 1)]),
        ("Št", [("DEJ\n204", 1, 0.94), ("Bio\n105", 1, 0.92), ("MAT\n204", 1, 0.96), ("CHE\n108", 1, 0.94),
                ("ANJ Ko 31", 1, 0.52), ("GEO\n204", 1, 0.93), ("UMK\nAula", 1, 0.88), ("", 1, 1)]),
        ("Pi", [("SJL\n204", 1, 0.96), ("FYZ\n112", 1, 0.95), ("MAT\n204", 1, 0.96), ("INF\nUč3", 1, 0.92),
                ("ANJ\n31", 1, 0.95), ("", 1, 1), ("", 1, 1), ("", 1, 1)]),
    ]

    // Page layout (pixels): a header column for the days and one column per period.
    static let page = CGSize(width: 1800, height: 900)
    static let margin: CGFloat = 60
    static let dayColumn: CGFloat = 120
    static let headerRow: CGFloat = 110

    static var periodColumn: CGFloat { (page.width - 2 * margin - dayColumn) / CGFloat(periodTimes.count) }
    static var dayRow: CGFloat { (page.height - 2 * margin - headerRow) / CGFloat(rows.count) }

    /// The pixel rectangle of grid cell (row, column) spanning `span` columns (row 0 / column 0 = headers).
    static func rect(row: Int, column: Int, span: Int = 1) -> CGRect {
        let x = column == 0 ? margin : margin + dayColumn + CGFloat(column - 1) * periodColumn
        let y = row == 0 ? margin : margin + headerRow + CGFloat(row - 1) * dayRow
        let width = column == 0 ? dayColumn : periodColumn * CGFloat(span)
        return CGRect(x: x, y: y, width: width, height: row == 0 ? headerRow : dayRow)
    }

    /// What Vision would report for the picture.
    static var table: RecognizedTable {
        var cells: [RecognizedCell] = [cell("", row: 0, column: 0)]
        for (index, time) in periodTimes.enumerated() {
            cells.append(cell("\(index + 1)\n\(time)", row: 0, column: index + 1, confidence: 0.95))
        }
        for (rowIndex, row) in rows.enumerated() {
            cells.append(cell(row.day, row: rowIndex + 1, column: 0, confidence: 0.97))
            var column = 1
            for (text, span, confidence) in row.cells {
                cells.append(cell(text, row: rowIndex + 1, column: column, span: span, confidence: confidence))
                column += span
            }
        }
        return RecognizedTable(pageWidth: page.width, pageHeight: page.height, languages: ["sk"], cells: cells)
    }

    private static func cell(_ text: String, row: Int, column: Int, span: Int = 1, confidence: Double = 1) -> RecognizedCell {
        let r = rect(row: row, column: column, span: span)
        return RecognizedCell(text: text, row: row, column: column, columnSpan: span,
                              box: NormalizedRect(x: r.minX / page.width, y: r.minY / page.height,
                                                  width: r.width / page.width, height: r.height / page.height),
                              confidence: confidence)
    }

    /// The picture of the table (black on white, like a printed aSc export).
    @MainActor static var image: UIImage {
        let renderer = ImageRenderer(content: FixturePage().frame(width: page.width, height: page.height))
        renderer.scale = 1
        return renderer.uiImage ?? UIImage()
    }

    /// The parsed review (the real parser on the fixture table).
    static var review: ImportReview {
        let candidate = TimetableImportParser.parse(table, options: ImportParserOptions(knownSubjects: knownSubjects))
        return ImportReview(candidate: candidate, timetableName: "Rozvrh 2.A")
    }

    @MainActor static func model(stage: PhotoImportModel.Stage, step: ImportStep = .reading,
                                 anchor: String? = nil) -> PhotoImportModel {
        let flow = PhotoImportModel(stage: stage, step: step, image: image, table: table,
                                    review: stage == .review ? review : nil)
        flow.initialAnchor = anchor
        return flow
    }
}

/// Capture screen row (DEBUG): runs the real Vision → parser pipeline on the fixture picture, on the device.
struct ImportSampleSection: View {
    let start: (UIImage) -> Void

    var body: some View {
        Section {
            Button { start(ImportFixtures.image) } label: {
                Label { Text(verbatim: "Use Sample Picture (Debug)") } icon: { Image(systemName: "ladybug") }
            }
        } footer: {
            Text(verbatim: "Developer check: the fixture aSc timetable picture through Vision, the parser and (if available) Apple Intelligence.")
        }
    }
}

/// The fixture page, drawn from `ImportFixtures` cell boxes.
private struct FixturePage: View {
    var body: some View {
        Canvas { context, _ in
            for cell in ImportFixtures.table.cells {
                guard let box = cell.box else { continue }
                let rect = CGRect(x: box.x * ImportFixtures.page.width, y: box.y * ImportFixtures.page.height,
                                  width: box.width * ImportFixtures.page.width, height: box.height * ImportFixtures.page.height)
                context.stroke(Path(rect), with: .color(.black), lineWidth: 2)
                let lines = cell.text.split(separator: "\n").map(String.init)
                guard let first = lines.first else { continue }
                context.draw(Text(verbatim: first).font(.system(size: cell.row == 0 ? 34 : 38, weight: .bold)).foregroundColor(.black),
                             at: CGPoint(x: rect.minX + 14, y: rect.minY + 12), anchor: .topLeading)
                if lines.count > 1 {
                    context.draw(Text(verbatim: lines[1]).font(.system(size: 26)).foregroundColor(.black),
                                 at: CGPoint(x: rect.maxX - 12, y: rect.maxY - 10), anchor: .bottomTrailing)
                }
            }
        }
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
#endif // DEBUG
