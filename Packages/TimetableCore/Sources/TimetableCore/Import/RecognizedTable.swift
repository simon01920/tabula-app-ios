import Foundation

// The seam between the Vision adapter (App, I2) and the deterministic import parser (PHASE9_PLAN decision 3).
// The adapter fills a `RecognizedTable` from `RecognizeDocumentsRequest` (cells) or, when no table is found, from
// `VNRecognizeTextRequest` (loose `lines`). Everything here is plain data; the JSON form is what the eval fixtures
// (`Packages/TimetableCore/Tests/Fixtures/import/`) store.

/// A rectangle in normalised page coordinates: 0…1 on both axes, **origin top-left**, y grows downwards.
/// (Vision uses a bottom-left origin; the adapter converts with `y = 1 - visionY - height`.)
public struct NormalizedRect: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// The smallest rectangle containing both.
    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let x0 = min(minX, other.minX), y0 = min(minY, other.minY)
        return NormalizedRect(x: x0, y: y0, width: max(maxX, other.maxX) - x0, height: max(maxY, other.maxY) - y0)
    }
}

/// One table cell as recognised. Row and column are 0-based grid indices of the top-left grid cell it covers;
/// a merged cell has `rowSpan`/`columnSpan` > 1. Multi-line text keeps its line breaks (`\n`).
public struct RecognizedCell: Hashable, Sendable, Codable {
    /// Verbatim OCR text (lines separated by `\n`; may be empty).
    public var text: String
    public var row: Int
    public var column: Int
    public var rowSpan: Int
    public var columnSpan: Int
    /// Where the cell is on the page, if known.
    public var box: NormalizedRect?
    /// OCR confidence 0…1 (the lowest of the cell's lines).
    public var confidence: Double

    public init(text: String, row: Int, column: Int, rowSpan: Int = 1, columnSpan: Int = 1,
                box: NormalizedRect? = nil, confidence: Double = 1) {
        self.text = text
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.box = box
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey { case text, row, column, rowSpan, columnSpan, box, confidence }

    /// Spans default to 1 and confidence to 1 when absent (hand-written fixtures stay short).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        row = try c.decode(Int.self, forKey: .row)
        column = try c.decode(Int.self, forKey: .column)
        rowSpan = try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1
        columnSpan = try c.decodeIfPresent(Int.self, forKey: .columnSpan) ?? 1
        box = try c.decodeIfPresent(NormalizedRect.self, forKey: .box)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }
}

/// One loose OCR text line (fallback when no table structure was found).
public struct RecognizedLine: Hashable, Sendable, Codable {
    public var text: String
    public var box: NormalizedRect
    /// OCR confidence 0…1.
    public var confidence: Double

    public init(text: String, box: NormalizedRect, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey { case text, box, confidence }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        box = try c.decode(NormalizedRect.self, forKey: .box)
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }
}

/// What the OCR step saw on one page: table cells, or (fallback) loose lines. `cells` wins when non-empty.
public struct RecognizedTable: Hashable, Sendable, Codable {
    /// Format version of this JSON (bump on a breaking change).
    public static let currentVersion = 1

    public var version: Int
    /// Page size in pixels (or points); boxes are normalised, so this is informational.
    public var pageWidth: Double
    public var pageHeight: Double
    /// Detected or requested recognition languages, BCP-47 (`"sk"`, `"en-US"`, `"zh-Hans"`); may be empty.
    public var languages: [String]
    /// Table cells (`RecognizeDocumentsRequest`).
    public var cells: [RecognizedCell]
    /// Loose lines (`VNRecognizeTextRequest`), used only when `cells` is empty.
    public var lines: [RecognizedLine]

    public init(version: Int = RecognizedTable.currentVersion, pageWidth: Double = 1, pageHeight: Double = 1,
                languages: [String] = [], cells: [RecognizedCell] = [], lines: [RecognizedLine] = []) {
        self.version = version
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.languages = languages
        self.cells = cells
        self.lines = lines
    }

    private enum CodingKeys: String, CodingKey { case version, pageWidth, pageHeight, languages, cells, lines }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        pageWidth = try c.decodeIfPresent(Double.self, forKey: .pageWidth) ?? 1
        pageHeight = try c.decodeIfPresent(Double.self, forKey: .pageHeight) ?? 1
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        cells = try c.decodeIfPresent([RecognizedCell].self, forKey: .cells) ?? []
        lines = try c.decodeIfPresent([RecognizedLine].self, forKey: .lines) ?? []
    }

    /// The grid the parser reads: `cells`, or cells clustered from `lines` (`LineClustering`), within `Bounds`.
    public var gridCells: [RecognizedCell] {
        Bounds.cells(cells.isEmpty ? LineClustering.cells(from: Bounds.lines(lines)) : cells)
    }

    /// Limits on untrusted input (a page never comes near them): the parser's work stays small and nothing traps.
    public enum Bounds {
        /// Rows and columns outside 0..<maxIndex are dropped.
        public static let maxIndex = 256
        /// Spans are clamped to 1...maxSpan.
        public static let maxSpan = 64
        /// Cells and lines beyond this many are dropped.
        public static let maxItems = 4000
        /// Text is cut to this many characters.
        public static let maxText = 1000

        /// In-range cells, one per (row, column) (the first wins), spans and confidence clamped, text cut.
        public static func cells(_ cells: [RecognizedCell]) -> [RecognizedCell] {
            var seen: Set<Int> = []
            var result: [RecognizedCell] = []
            for var cell in cells where result.count < maxItems {
                guard (0..<maxIndex).contains(cell.row), (0..<maxIndex).contains(cell.column),
                      seen.insert(cell.row * maxIndex + cell.column).inserted else { continue }
                cell.rowSpan = min(max(cell.rowSpan, 1), maxSpan)
                cell.columnSpan = min(max(cell.columnSpan, 1), maxSpan)
                cell.confidence = clamp(cell.confidence)
                if cell.text.count > maxText { cell.text = String(cell.text.prefix(maxText)) }
                result.append(cell)
            }
            return result
        }

        /// Lines with a finite box, at most `maxItems`, confidence clamped, text cut.
        public static func lines(_ lines: [RecognizedLine]) -> [RecognizedLine] {
            lines.lazy.filter { [$0.box.x, $0.box.y, $0.box.width, $0.box.height].allSatisfy(\.isFinite) }
                .prefix(maxItems).map { line in
                    var line = line
                    line.confidence = clamp(line.confidence)
                    if line.text.count > maxText { line.text = String(line.text.prefix(maxText)) }
                    return line
                }
        }

        private static func clamp(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
    }
}
