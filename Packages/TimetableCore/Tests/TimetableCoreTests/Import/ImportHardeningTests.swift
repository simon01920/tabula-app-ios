import Foundation
import Testing
@testable import TimetableCore

private func cell(_ text: String, _ row: Int, _ column: Int, span: Int = 1, confidence: Double = 0.95) -> RecognizedCell {
    RecognizedCell(text: text, row: row, column: column, columnSpan: span, confidence: confidence)
}

@Suite("Import: hostile input and edge cases (QA)")
struct ImportHardeningTests {
    /// Huge and negative indices, Int.max spans, NaN confidence, 10k cells, 100k-character text, non-finite line boxes:
    /// no trap, bounded work, and every lesson still sits inside the period grid.
    @Test func hostileInputFinishesFast() throws {
        let long = String(repeating: "MAT 204 (A) ", count: 10_000)
        var cells = [
            RecognizedCell(text: "Po", row: Int.max, column: Int.max, rowSpan: Int.max, columnSpan: Int.max),
            RecognizedCell(text: "Ut", row: 1_000_000_000, column: 0), RecognizedCell(text: "St", row: -5, column: -1),
            RecognizedCell(text: "Po", row: 1, column: 0, rowSpan: Int.max), RecognizedCell(text: long, row: 1, column: 1, columnSpan: Int.max),
            RecognizedCell(text: "FYZ", row: 2, column: 2, rowSpan: Int.min, columnSpan: Int.min, confidence: .nan),
        ]
        var rng = TestRNG(seed: 0xB0_0B)
        for _ in 0..<10_000 {
            cells.append(cell(["Po", "Ut", "MAT", "1\n7.00", long.prefix(50) + "", "A: X 1"].randomElement(using: &rng)!,
                              Int.random(in: 0..<300, using: &rng), Int.random(in: 0..<300, using: &rng),
                              span: Int.random(in: -3...100, using: &rng), confidence: Double.random(in: -1...2, using: &rng)))
        }
        var lines: [RecognizedLine] = []
        for index in 0..<10_000 {
            let x: Double = index % 3 == 0 ? .infinity : Double(index % 100) / 100
            let y: Double = index % 5 == 0 ? .nan : Double(index % 90) / 90
            let height: Double = index % 11 == 0 ? 1e9 : 0.01
            lines.append(RecognizedLine(text: index % 7 == 0 ? "Po" : long,
                                        box: NormalizedRect(x: x, y: y, width: 0.01, height: height), confidence: .nan))
        }
        let clock = ContinuousClock()
        var candidates: [ImportCandidate] = []
        let elapsed = clock.measure {
            candidates.append(TimetableImportParser.parse(RecognizedTable(cells: cells)))
            candidates.append(TimetableImportParser.parse(RecognizedTable(lines: lines)))
        }
        #expect(elapsed < .seconds(30), "took \(elapsed)")
        for candidate in candidates {
            #expect(candidate.periods.count <= ShareLimits.maxPeriodsPerSchedule)
            for (a, b) in zip(candidate.periods, candidate.periods.dropFirst()) { #expect(a.start < a.end && a.end <= b.start) }
            let numbers = candidate.periods.map(\.number)
            for lesson in candidate.lessons {
                let first = try #require(numbers.firstIndex(of: lesson.period))
                #expect(lesson.span >= 1 && first + lesson.span <= numbers.count)
                #expect(lesson.sourceText.count <= RecognizedTable.Bounds.maxText)
                #expect((0...1).contains(lesson.confidence))
            }
        }
        let bounded = RecognizedTable(cells: cells).gridCells
        #expect(bounded.count <= RecognizedTable.Bounds.maxItems)
        #expect(bounded.allSatisfy { (0..<256).contains($0.row) && (1...64).contains($0.columnSpan) && (1...64).contains($0.rowSpan) })
    }

    /// Hungarian one-letter days next to one-letter lessons: the label column wins, with and without a header row.
    @Test(arguments: [true, false])
    func hungarianLetterDaysBeatLetterLessons(withHeader: Bool) {
        let shift = withHeader ? 1 : 0
        var cells = withHeader ? (1...5).map { cell("\($0)", 0, $0) } : []
        for (index, label) in ["H", "K", "Sze", "Cs", "P"].enumerated() { cells.append(cell(label, index + shift, 0)) }
        for (column, lesson) in ["K", "P", "V", "H"].enumerated() { cells.append(cell(lesson, shift, column + 1)) } // Monday
        cells.append(cell("Cs", 2 + shift, 3))
        let candidate = TimetableImportParser.parse(RecognizedTable(languages: ["hu"], cells: cells))
        #expect(candidate.orientation == .daysAsRows)
        #expect(candidate.days == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(candidate.lessons.map { "\($0.day.rawValue) \($0.period) \($0.subject)" } == ["1 1 K", "1 2 P", "1 3 V", "1 4 H", "3 3 Cs"])
    }

    @Test(arguments: [
        ("10:00–10:50 a.m.", "10:00", "10:50"), ("12:00–12:50", "12:00", "12:50"), ("1:00–1:50 p.m.", "13:00", "13:50"),
        ("2:00-2:50PM", "14:00", "14:50"), ("11:30–12:20 p.m.", "11:30", "12:20"), ("12:30–1:15", "12:30", "13:15"),
        ("12:15 a.m.", "00:15", nil),
    ] as [(String, String, String?)])
    func twelveHourHeaders(_ text: String, _ start: String, _ end: String?) {
        let header = ImportBellInference.header(text)
        #expect(header.start == LocalTime(start), "\(text)")
        #expect(header.end == end.flatMap(LocalTime.init), "\(text)")
        #expect(ImportBellInference.isHeaderLike(text))
    }

    @Test func twelveHourStartsAfterNoonMoveOn() {
        let headers = ["11:00", "12:00", "01:00", "02:00"].map { ImportBellInference.Header(start: LocalTime($0)) }
        let (periods, _) = ImportBellInference.periods(numbers: [1, 2, 3, 4], headers: headers)
        #expect(periods.map(\.start.isoString) == ["11:00", "12:00", "13:00", "14:00"])
    }

    /// More than 28 columns without times used to clamp to 23:00 and duplicate periods.
    @Test func manyAssumedPeriodsStayDistinct() throws {
        let (periods, notices) = ImportBellInference.periods(numbers: Array(1...40), headers: Array(repeating: .init(), count: 40))
        #expect(periods.count == 40 && notices == [.timesAssumed])
        for (a, b) in zip(periods, periods.dropFirst()) { #expect(a.start < a.end && a.end <= b.start) }
        // A late printed start with many interpolated columns after it falls back to the assumed schedule.
        let late = [ImportBellInference.Header(start: LocalTime("22:00"))] + Array(repeating: .init(), count: 30)
        let (fallback, lateNotices) = ImportBellInference.periods(numbers: Array(1...31), headers: late)
        #expect(fallback.count == 31 && lateNotices == [.timesAssumed])
        for (a, b) in zip(fallback, fallback.dropFirst()) { #expect(a.start < a.end && a.end <= b.start) }
        // End to end: 45 header-less columns are capped to the share limit and still make a valid payload.
        var cells = [cell("Po", 0, 0)]
        for column in 1...45 { cells.append(cell("L\(column)", 0, column)) }
        let candidate = TimetableImportParser.parse(RecognizedTable(cells: cells))
        #expect(candidate.periods.count == ShareLimits.maxPeriodsPerSchedule)
        _ = try ImportPayloadBuilder.payload(from: candidate, name: "T", bellScheduleName: "B")
    }

    @Test func reconciliationStoresTheCellsSpelling() {
        let candidate = TimetableImportParser.parse(RecognizedTable(languages: ["sk"], cells: [
            cell("1", 0, 1), cell("Po", 1, 0), cell("Odborná prax\nZŠ Hlboká ulica", 1, 1),
            cell("Ut", 2, 0), cell("Matematika\n2O4", 2, 1, confidence: 0.4),
        ]))
        let result = ImportReconciliation.apply([
            NormalisationSuggestion(id: 0, room: .value("zs hlboka ULICA")),
            NormalisationSuggestion(id: 1, subject: .value("M"), room: .value("204")),
        ], to: candidate)
        #expect(result.lessons[0].room == "ZŠ Hlboká ulica") // the cell's spelling, not the model's
        #expect(result.lessons[0].notes == nil)
        #expect(result.lessons[1].room == "204") // agrees with the parser's value: unchanged
        #expect(result.lessons[1].subject == "Matematika") // one character: a question, never applied
        #expect(result.lessons[1].alternatives.contains(ImportAlternative(field: .subject, kind: .normaliser, values: ["Matematika", "M"])))
        #expect(ImportText.verbatimSpan(of: "h4p1", in: "Teor.\nH4PI") == "H4PI")
        #expect(ImportText.verbatimSpan(of: "x", in: "x y") == nil)
    }
}
