import Foundation

/// Geometric clustering of loose OCR lines into grid cells (fallback when Vision finds no table).
///
/// Day labels are the anchors: when they run down the page (days as rows) each label owns the horizontal band
/// around it, and the header lines above the first band define the columns; a line that covers several column
/// centres is a merged cell. Days across the page are handled by swapping x and y. Without day labels, lines are
/// clustered by overlapping extents on both axes.
public enum LineClustering {
    public static func cells(from lines: [RecognizedLine]) -> [RecognizedCell] {
        let lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return [] }
        let dayLines = lines.filter { !ImportVocabulary.days(in: $0.text).isEmpty }
        if dayLines.count >= 2 {
            let spreadY = spread(dayLines.map(\.box.midY)), spreadX = spread(dayLines.map(\.box.midX))
            if spreadY >= spreadX { return anchored(lines, days: dayLines) }
            let flipped = anchored(lines.map(swapped), days: dayLines.map(swapped))
            return flipped.map { cell in
                RecognizedCell(text: cell.text, row: cell.column, column: cell.row, rowSpan: cell.columnSpan,
                               columnSpan: cell.rowSpan, box: cell.box.map(swapped), confidence: cell.confidence)
            }
        }
        return unanchored(lines)
    }

    private static func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }

    private static func swapped(_ rect: NormalizedRect) -> NormalizedRect {
        NormalizedRect(x: rect.y, y: rect.x, width: rect.height, height: rect.width)
    }

    private static func swapped(_ line: RecognizedLine) -> RecognizedLine {
        RecognizedLine(text: line.text, box: swapped(line.box), confidence: line.confidence)
    }

    /// Days as rows: label bands down the page, header columns across.
    private static func anchored(_ lines: [RecognizedLine], days: [RecognizedLine]) -> [RecognizedCell] {
        // One anchor per day row (labels on the same height merge).
        var anchors: [Double] = []
        let height = median(lines.map(\.box.height))
        for mid in days.map(\.box.midY).sorted() where anchors.last.map({ mid - $0 > height / 2 }) ?? true { anchors.append(mid) }
        let dayRight = days.map(\.box.maxX).max()! + 0.002
        let spacing = anchors.count > 1 ? (anchors.last! - anchors.first!) / Double(anchors.count - 1) : height * 4
        var bounds = [anchors[0] - spacing / 2]
        for (a, b) in zip(anchors, anchors.dropFirst()) { bounds.append((a + b) / 2) }
        bounds.append(anchors.last! + spacing / 2)
        let top = bounds[0]
        let dayIDs = Set(days.map(\.self))

        let headerLines = lines.filter { $0.box.midY < top && $0.box.minX >= dayRight - 0.002 }
        let body = lines.filter { $0.box.midY >= top && $0.box.midY < bounds.last! && !dayIDs.contains($0) && $0.box.midX > dayRight }
        // Columns: x clusters of the header, else of the body (ignoring wide, merged-cell lines).
        let narrowBody = body.filter { $0.box.width <= 2 * median(body.map(\.box.width)) }
        var columns = clusters(headerLines.isEmpty ? narrowBody.map(\.box) : headerLines.map(\.box), axis: \.minX, \.maxX)
        if columns.isEmpty { columns = [(dayRight, 1)] }
        let centres = columns.map { ($0.0 + $0.1) / 2 }
        var edges = [dayRight]
        for (a, b) in zip(centres, centres.dropFirst()) { edges.append((a + b) / 2) }
        edges.append(1)
        let headerRow = headerLines.isEmpty ? 0 : 1

        func columnRange(_ box: NormalizedRect) -> (Int, Int) {
            let covered = centres.indices.filter { box.minX <= centres[$0] && centres[$0] <= box.maxX }
            if covered.count > 1 { return (covered[0], covered.count) }
            // Short text centred over a merged cell sits on the edge between two columns.
            for edge in 1..<max(1, edges.count - 1) where abs(box.midX - edges[edge]) < 0.15 * (edges[edge + 1] - edges[edge - 1]) / 2 {
                return (edge - 1, 2)
            }
            if let first = covered.first { return (first, 1) }
            let index = max(0, min(edges.count - 2, (edges.lastIndex { $0 <= box.midX } ?? 0)))
            return (index, 1)
        }

        var groups: [Key: [RecognizedLine]] = [:]
        var spans: [Key: Int] = [:]
        for line in headerLines {
            let (column, _) = columnRange(line.box)
            groups[Key(row: 0, column: column + 1), default: []].append(line)
        }
        for line in days {
            let band = max(0, (bounds.lastIndex { $0 <= line.box.midY } ?? 0))
            groups[Key(row: min(band, anchors.count - 1) + headerRow, column: 0), default: []].append(line)
        }
        // Lines of one cell are centred on the same x (subject over room): group them first, so a merged cell's
        // short room line follows its subject. shortcut: spans come from the text extent only (a short "prax" over six
        // periods reads as 1–2 periods); Vision's table cells carry the real span.
        let columnWidth = (1 - dayRight) / Double(max(1, centres.count))
        let bands = Dictionary(grouping: body) { line in min(anchors.count - 1, bounds.lastIndex { $0 <= line.box.midY } ?? 0) }
        for (band, bandLines) in bands {
            var blobs: [[RecognizedLine]] = []
            for line in bandLines.sorted(by: { $0.box.minY < $1.box.minY }) {
                if let index = blobs.firstIndex(where: { blob in blob.contains { abs($0.box.midX - line.box.midX) < columnWidth / 4 } }) {
                    blobs[index].append(line)
                } else {
                    blobs.append([line])
                }
            }
            for blob in blobs {
                let box = blob.dropFirst().reduce(blob[0].box) { $0.union($1.box) }
                let (column, span) = columnRange(box)
                let key = Key(row: band + headerRow, column: column + 1)
                groups[key, default: []] += blob
                spans[key] = max(spans[key] ?? 1, span)
            }
        }
        return makeCells(groups, spans: spans)
    }

    /// No anchors: rows and columns from overlapping extents.
    private static func unanchored(_ lines: [RecognizedLine]) -> [RecognizedCell] {
        let rows = clusters(lines.map(\.box), axis: \.minY, \.maxY)
        let columns = clusters(lines.map(\.box), axis: \.minX, \.maxX)
        var groups: [Key: [RecognizedLine]] = [:]
        for line in lines {
            let row = rows.firstIndex { $0.0 <= line.box.midY && line.box.midY <= $0.1 } ?? 0
            let column = columns.firstIndex { $0.0 <= line.box.midX && line.box.midX <= $0.1 } ?? 0
            groups[Key(row: row, column: column), default: []].append(line)
        }
        return makeCells(groups, spans: [:])
    }

    private struct Key: Hashable, Comparable {
        var row: Int
        var column: Int
        static func < (a: Key, b: Key) -> Bool { (a.row, a.column) < (b.row, b.column) }
    }

    private static func makeCells(_ groups: [Key: [RecognizedLine]], spans: [Key: Int]) -> [RecognizedCell] {
        groups.keys.sorted().map { key in
            let lines = groups[key]!.sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
            let box = lines.dropFirst().reduce(lines[0].box) { $0.union($1.box) }
            return RecognizedCell(text: lines.map(\.text).joined(separator: "\n"), row: key.row, column: key.column,
                                  columnSpan: spans[key] ?? 1, box: box, confidence: lines.map(\.confidence).min() ?? 1)
        }
    }

    /// Merged intervals of overlapping extents along one axis, ascending.
    private static func clusters(_ boxes: [NormalizedRect], axis low: KeyPath<NormalizedRect, Double>,
                                 _ high: KeyPath<NormalizedRect, Double>) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for box in boxes.sorted(by: { $0[keyPath: low] < $1[keyPath: low] }) {
            if let last = result.last, box[keyPath: low] <= last.1 {
                result[result.count - 1].1 = max(last.1, box[keyPath: high])
            } else {
                result.append((box[keyPath: low], box[keyPath: high]))
            }
        }
        return result
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.02 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
