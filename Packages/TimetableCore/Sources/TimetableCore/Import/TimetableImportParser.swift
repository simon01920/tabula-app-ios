import Foundation

/// The deterministic parser: `RecognizedTable` → `ImportCandidate` (PHASE9_PLAN decision 4).
///
/// 1. Orientation: the column (days as rows) or row (days as columns) with the most day labels. Days as columns is
///    transposed and parsed like days as rows.
/// 2. Rows above the first day label are headers: period numbers and times per column ("1" over "7.00",
///    "08:00–08:45", "1. hod"). Columns without a number get the next one (`.unknownPeriod`).
/// 3. Day labels are resolved in order, so "St" after "Ut" is Wednesday and the next "St" Thursday. A second
///    run of days (Po…Pi, Po…Pi) is week B. A content row whose label is unreadable gets the next day (`.unknownDay`);
///    a row without a label continues the day above (two-row days).
/// 4. Every non-empty, non-header cell right of the labels becomes one lesson (or one per week marker); a cell
///    covering several period columns is a multi-period lesson. Nothing is invented.
public enum TimetableImportParser {
    public static func parse(_ table: RecognizedTable, options: ImportParserOptions = .init()) -> ImportCandidate {
        let cells = table.gridCells.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cells.isEmpty else { return ImportCandidate(notices: [.emptyInput], languages: table.languages) }
        // Day labels lead their row (days as rows) or column (days as columns): only the first non-header cell of
        // each row or column counts, so one-letter lessons ("K", "P") never outvote the label column.
        let (column, columnHits) = bestAxis(leading(cells, along: \.row, at: \.column))
        let (row, rowHits) = bestAxis(leading(cells, along: \.column, at: \.row))
        guard max(columnHits, rowHits) > 0 else { return ImportCandidate(notices: [.noDaysFound], languages: table.languages) }
        let asRows = columnHits >= rowHits
        let grid = asRows ? cells : cells.map(transposed)
        var candidate = parseDaysAsRows(grid, dayColumn: asRows ? column : row, options: options, languages: table.languages)
        candidate.orientation = asRows ? .daysAsRows : .daysAsColumns
        if !asRows {
            for index in candidate.lessons.indices {
                let source = candidate.lessons[index].source
                candidate.lessons[index].source = ImportCellRef(row: source.column, column: source.row)
            }
        }
        return candidate
    }

    /// The first non-header cell of each row (`along: \.row`) or column, keyed by its index on the other axis.
    private static func leading(_ cells: [RecognizedCell], along line: KeyPath<RecognizedCell, Int>,
                                at index: KeyPath<RecognizedCell, Int>) -> [(Int, RecognizedCell)] {
        var first: [Int: RecognizedCell] = [:]
        for cell in cells where !ImportBellInference.isHeaderLike(cell.text) {
            if let current = first[cell[keyPath: line]], current[keyPath: index] <= cell[keyPath: index] { continue }
            first[cell[keyPath: line]] = cell
        }
        return first.values.map { ($0[keyPath: index], $0) }
    }

    /// The axis index with the most day labels, and the count.
    private static func bestAxis(_ entries: [(Int, RecognizedCell)]) -> (Int, Int) {
        var hits: [Int: Int] = [:]
        for (index, cell) in entries where !ImportVocabulary.days(in: cell.text).isEmpty { hits[index, default: 0] += 1 }
        return hits.max { ($0.value, -$0.key) < ($1.value, -$1.key) }.map { ($0.key, $0.value) } ?? (0, 0)
    }

    private static func transposed(_ cell: RecognizedCell) -> RecognizedCell {
        RecognizedCell(text: cell.text, row: cell.column, column: cell.row, rowSpan: cell.columnSpan,
                       columnSpan: cell.rowSpan, box: cell.box, confidence: cell.confidence)
    }

    private struct DayGroup {
        var rows: Set<Int>
        var day: Weekday
        var block: Int
        var unknown: Bool
    }

    private static func parseDaysAsRows(_ cells: [RecognizedCell], dayColumn: Int, options: ImportParserOptions,
                                        languages: [String]) -> ImportCandidate {
        let labels = Dictionary(cells.filter { $0.column == dayColumn }.map { ($0.row, $0) }, uniquingKeysWith: { a, _ in a })
        let firstDayRow = labels.values.filter { !ImportVocabulary.days(in: $0.text).isEmpty }.map(\.row).min()!
        let rowCount = cells.map { $0.row + max(1, $0.rowSpan) }.max()!
        let content = cells.filter { $0.column > dayColumn && $0.row >= firstDayRow }
        let contentByRow = Dictionary(grouping: content, by: \.row)

        // Day groups, resolved in order.
        var groups: [DayGroup] = []
        var previous = 0
        var block = 0
        var covered = -1
        for row in firstDayRow..<rowCount {
            let lessonCells = (contentByRow[row] ?? []).filter { !ImportBellInference.isHeaderLike($0.text) }
            if let label = labels[row], case let days = ImportVocabulary.days(in: label.text), !days.isEmpty {
                let day: Weekday
                if let next = days.filter({ $0.rawValue > previous }).min() {
                    day = next
                } else {
                    block += 1
                    day = days.min()!
                }
                previous = day.rawValue
                covered = row + max(1, label.rowSpan) - 1
                groups.append(DayGroup(rows: Set(row...covered), day: day, block: block, unknown: false))
            } else if row <= covered || lessonCells.isEmpty {
                continue
            } else if labels[row] == nil, !groups.isEmpty {
                groups[groups.count - 1].rows.insert(row) // second row of the day above
            } else {
                guard previous < 7 else { continue }
                previous += 1
                groups.append(DayGroup(rows: [row], day: Weekday(rawValue: previous)!, block: block, unknown: true))
            }
        }

        // Period columns: every grid column right of the labels up to the last one with a header or content
        // (empty columns in between are periods nobody has, e.g. period 5 when the header row is missing).
        let headerCells = cells.filter { $0.row < firstDayRow && $0.column > dayColumn && ImportBellInference.isHeaderLike($0.text) }
        let lastColumn = (headerCells + content).map { $0.column + max(1, $0.columnSpan) - 1 }.max() ?? dayColumn
        // At most the share format's periods per schedule; cells further right are not imported.
        let periodColumns = lastColumn > dayColumn
            ? Array(((dayColumn + 1)...lastColumn).prefix(ShareLimits.maxPeriodsPerSchedule)) : []
        let headers = periodColumns.map { column in
            ImportBellInference.header(headerCells.filter { $0.column <= column && column < $0.column + max(1, $0.columnSpan) }
                .sorted { $0.row < $1.row }.map(\.text).joined(separator: "\n"))
        }
        // Numbers: printed when ascending, else the next number.
        var numbers: [Int] = []
        var unnumbered: Set<Int> = []
        for (index, header) in headers.enumerated() {
            let last = numbers.last ?? (header.number.map { $0 - 1 } ?? 0)
            if let number = header.number, number > last || numbers.isEmpty {
                numbers.append(number)
            } else {
                numbers.append(last + 1)
                unnumbered.insert(periodColumns[index])
            }
        }
        let (periods, notices) = ImportBellInference.periods(numbers: numbers, headers: headers)
        let numberOfColumn = Dictionary(uniqueKeysWithValues: zip(periodColumns, numbers))

        // Lessons.
        var lessons: [ImportLesson] = []
        let blocks = (groups.map(\.block).max() ?? 0) + 1
        // Group rows ascend in group order, so one pass in (row, column) order visits the groups in order.
        var groupOfRow: [Int: Int] = [:]
        for (index, group) in groups.enumerated() { for row in group.rows { groupOfRow[row] = index } }
        for cell in content.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            guard let groupIndex = groupOfRow[cell.row], !ImportBellInference.isHeaderLike(cell.text) else { continue }
            let group = groups[groupIndex]
            let columns = periodColumns.filter { cell.column <= $0 && $0 < cell.column + max(1, cell.columnSpan) }
            guard let first = columns.first, let number = numberOfColumn[first] else { continue }
            for part in ImportCellSplitter.split(cell.text, options: options, languages: languages) {
                var reasons = part.reasons
                if cell.confidence < ImportScoring.lowOCR { reasons.insert(.ocrLow) }
                if group.unknown { reasons.insert(.unknownDay) }
                if columns.contains(where: unnumbered.contains) { reasons.insert(.unknownPeriod) }
                if columns.contains(where: { column in periods.first { $0.number == numberOfColumn[column] }?.timeSource == .assumed }) {
                    reasons.insert(.timeInferred)
                }
                let weeks = part.weeks ?? (blocks > 1 ? [group.block + 1] : nil)
                lessons.append(ImportLesson(
                    id: lessons.count, day: group.day, period: number, span: columns.count, cycleWeeks: weeks,
                    subject: part.subject, room: part.room, teacher: part.teacher, lessonType: part.lessonType,
                    notes: part.notes.isEmpty ? nil : part.notes.joined(separator: "\n"), sourceText: cell.text,
                    source: ImportCellRef(row: cell.row, column: cell.column), ocrConfidence: cell.confidence,
                    reasons: reasons, alternatives: part.alternatives))
            }
        }
        markConflicts(&lessons)
        for index in lessons.indices {
            lessons[index].confidence = ImportScoring.confidence(ocr: lessons[index].ocrConfidence, reasons: lessons[index].reasons)
        }

        var cycle: Int?
        if lessons.contains(where: { $0.cycleWeeks != nil }) {
            cycle = max(2, lessons.compactMap(\.cycleWeeks).flatMap { $0 }.max() ?? 2)
            if !(WeekCycle.validLengths).contains(cycle!) {
                cycle = nil
                for index in lessons.indices { lessons[index].cycleWeeks = nil }
            }
        }
        var allNotices = notices
        if blocks > 1, cycle != nil { allNotices.append(.weekRotationDetected) }
        var days: [Weekday] = []
        for group in groups where !days.contains(group.day) { days.append(group.day) }
        return ImportCandidate(days: days, periods: periods, lessons: lessons, weekCycleLength: cycle,
                               notices: allNotices, languages: languages)
    }

    /// Marks lessons that overlap another lesson on the same day and week with `.timeConflict`. Sweep over lessons
    /// sorted by (day, period): each one is compared only with those starting before it ends.
    private static func markConflicts(_ lessons: inout [ImportLesson]) {
        let order = lessons.indices.sorted { (lessons[$0].day, lessons[$0].period, $0) < (lessons[$1].day, lessons[$1].period, $1) }
        for (position, a) in order.enumerated() {
            for b in order[(position + 1)...] {
                let x = lessons[a], y = lessons[b]
                guard y.day == x.day, y.period < x.period + x.span else { break }
                if x.cycleWeeks == nil || y.cycleWeeks == nil || !x.cycleWeeks!.isDisjoint(with: y.cycleWeeks!) {
                    lessons[a].reasons.insert(.timeConflict)
                    lessons[b].reasons.insert(.timeConflict)
                }
            }
        }
    }
}
