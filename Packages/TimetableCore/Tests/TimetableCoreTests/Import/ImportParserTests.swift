import Foundation
import Testing
@testable import TimetableCore

private func cell(_ text: String, _ row: Int, _ column: Int, span: Int = 1, confidence: Double = 0.95) -> RecognizedCell {
    RecognizedCell(text: text, row: row, column: column, columnSpan: span, confidence: confidence)
}

private func parse(_ cells: [RecognizedCell], languages: [String] = ["sk"], options: ImportParserOptions = .init()) -> ImportCandidate {
    TimetableImportParser.parse(RecognizedTable(languages: languages, cells: cells), options: options)
}

private func split(_ text: String, languages: [String] = ["sk"], options: ImportParserOptions = .init()) -> ImportCellSplitter.Part {
    let parts = ImportCellSplitter.split(text, options: options, languages: languages)
    #expect(parts.count == 1, "\(text): \(parts.count) parts")
    return parts[0]
}

@Suite("Import: day names")
struct ImportDayTests {
    @Test(arguments: [
        ("Po", 1), ("Pondelok", 1), ("Utorok", 2), ("Štvrtok", 4), ("Stvrtok", 4), ("Piatok", 5), ("Pá", 5), ("Čt", 4),
        ("Monday", 1), ("Thu", 4), ("Montag", 1), ("Mittwoch", 3), ("Fr", 5), ("Poniedziałek", 1), ("Sr", 3),
        ("Czwartek", 4), ("Hétfő", 1), ("Csütörtök", 4), ("Sze", 3), ("Luni", 1), ("Marți", 2), ("Joi", 4), ("Lundi", 1),
        ("Mercredi", 3), ("Ven", 5), ("Пн", 1), ("Четвер", 4), ("П'ятниця", 5), ("Понедељак", 1), ("Četvrtak", 4),
        ("Cet", 4), ("月", 1), ("金曜日", 5), ("(水)", 3), ("星期一", 1), ("周五", 5), ("Po 1.9.", 1), ("Pond.", 1),
    ])
    func recognisesDay(_ text: String, _ day: Int) {
        #expect(ImportVocabulary.days(in: text).contains(Weekday(rawValue: day)!), "\(text)")
    }

    @Test(arguments: ["Matematika", "204", "", "1", "7.00", "SPAJ", "prax"])
    func ignoresNonDays(_ text: String) {
        #expect(ImportVocabulary.days(in: text).isEmpty, "\(text)")
    }

    @Test func ambiguousAbbreviationsResolveByOrder() {
        // Slovak without diacritics: St, St = Wednesday, Thursday. German Sa, So = Saturday, Sunday; Czech So, Ne.
        let sk = parse(["Po", "Ut", "St", "St", "Pi"].enumerated().map { cell($1, $0, 0) } + (0..<5).map { cell("X\(Character(UnicodeScalar(65 + $0)!))", $0, 1) })
        #expect(sk.days == [.monday, .tuesday, .wednesday, .thursday, .friday])
        let de = parse(["Fr", "Sa", "So"].enumerated().map { cell($1, $0, 0) } + (0..<3).map { cell("Mathe", $0, 1) }, languages: ["de"])
        #expect(de.days == [.friday, .saturday, .sunday])
        let cs = parse(["Pá", "So", "Ne"].enumerated().map { cell($1, $0, 0) } + (0..<3).map { cell("MAT", $0, 1) }, languages: ["cs"])
        #expect(cs.days == [.friday, .saturday, .sunday])
    }
}

@Suite("Import: headers and bell schedule")
struct ImportBellTests {
    @Test(arguments: [
        ("1\n7.00", 1, "07:00", nil), ("08:00–08:45", nil, "08:00", "08:45"), ("8.00-8.45", nil, "08:00", "08:45"),
        ("1. hod\n8:00-8:45", 1, "08:00", "08:45"), ("第3节\n10:00-10:45", 3, "10:00", "10:45"), ("2\n8h55-9h50", 2, "08:55", "09:50"),
        ("Period 4\n10:55", 4, "10:55", nil), ("12", 12, nil, nil), ("0\n7:10", 0, "07:10", nil),
    ] as [(String, Int?, String?, String?)])
    func header(_ text: String, _ number: Int?, _ start: String?, _ end: String?) {
        let header = ImportBellInference.header(text)
        #expect(header.number == number, "\(text)")
        #expect(header.start == start.flatMap(LocalTime.init), "\(text)")
        #expect(header.end == end.flatMap(LocalTime.init), "\(text)")
    }

    @Test func headerLike() {
        for text in ["1", "7.00", "1\n7.00", "1. hod", "08:00-08:45", "第1节", "1限", "Period 3", "3. Std"] {
            #expect(ImportBellInference.isHeaderLike(text), "\(text)")
        }
        for text in ["MAT", "SPAJ\n3P1", "Room 12", "Rozvrh 3.A", ""] {
            #expect(!ImportBellInference.isHeaderLike(text), "\(text)")
        }
        #expect(ImportBellInference.isHeaderLike("204")) // a bare number is never a lesson
    }

    @Test func ascStartsGive45MinuteLessons() {
        let starts = ["07:00", "07:50", "08:40", "09:30", "10:20", "11:10", "12:00", "12:50", "13:50", "14:40", "15:30", "16:20", "17:10"]
        let headers = starts.map { ImportBellInference.Header(number: nil, start: LocalTime($0), end: nil) }
        let (periods, notices) = ImportBellInference.periods(numbers: Array(1...13), headers: headers)
        #expect(periods.map(\.end.isoString) == ["07:45", "08:35", "09:25", "10:15", "11:05", "11:55", "12:45", "13:35", "14:35",
                                                  "15:25", "16:15", "17:05", "17:55"])
        #expect(notices == [.endTimesInferred])
    }

    @Test func universityStartsGive90MinuteBlocks() {
        let headers = ["07:30", "09:10", "10:50"].map { ImportBellInference.Header(number: nil, start: LocalTime($0), end: nil) }
        let (periods, _) = ImportBellInference.periods(numbers: [1, 2, 3], headers: headers)
        #expect(periods.map(\.end.isoString) == ["09:00", "10:40", "12:20"])
    }

    @Test func noTimesAreAssumedAndSaid() {
        let (periods, notices) = ImportBellInference.periods(numbers: [1, 2], headers: [.init(), .init()])
        #expect(periods.map(\.start.isoString) == ["08:00", "08:55"])
        #expect(periods.allSatisfy { $0.timeSource == .assumed })
        #expect(notices == [.timesAssumed])
    }

    @Test func misreadStartIsInterpolatedAndPeriodsNeverOverlap() {
        // "9.30" misread as "3.30" breaks the order: it is replaced, never trusted.
        let headers = ["08:00", "08:55", "03:30", "10:45"].map { ImportBellInference.Header(number: nil, start: LocalTime($0), end: nil) }
        let (periods, _) = ImportBellInference.periods(numbers: [1, 2, 3, 4], headers: headers)
        #expect(periods.count == 4)
        for (a, b) in zip(periods, periods.dropFirst()) { #expect(a.start < a.end && a.end <= b.start) }
        #expect(periods[2].timeSource == .assumed)
    }
}

@Suite("Import: cell splitting")
struct ImportSplitTests {
    @Test(arguments: [
        ("SPAJ 3P1", "SPAJ", "3P1"), ("Muzejná pedagogika H5S1", "Muzejná pedagogika", "H5S1"), ("MPV Aula", "MPV", "Aula"),
        ("prax\naaa", "prax", "aaa"), ("Teor. a prax vyuč. hist. I\nH4P1", "Teor. a prax vyuč. hist. I", "H4P1"),
        ("TPVAJ1\nAula", "TPVAJ1", "Aula"), ("Matematyka sala 12", "Matematyka", "sala 12"), ("Fyzika\nB-204", "Fyzika", "B-204"),
        ("Математика\nкаб. 21", "Математика", "каб. 21"), ("数学\n301", "数学", "301"),
    ] as [(String, String, String?)])
    func subjectAndRoom(_ text: String, _ subject: String, _ room: String?) {
        let part = split(text)
        #expect(part.subject == subject)
        #expect(part.room == room)
        #expect(part.reasons.isEmpty, "\(text): \(part.reasons)")
    }

    @Test func teachersAndTypes() {
        var part = split("Matematika\n204\nMgr. Kováčová")
        #expect(part.subject == "Matematika" && part.room == "204" && part.teacher == "Mgr. Kováčová")
        part = split("Fyzika\nLab F\nMgr. Horváth, PhD.")
        #expect(part.teacher == "Mgr. Horváth, PhD.")
        part = split("Analýza (P)\nAula")
        #expect(part.subject == "Analýza" && part.lessonType == LessonType.lecture)
        part = split("Algorithms (Lab)\nB204", languages: ["en"])
        #expect(part.subject == "Algorithms" && part.lessonType == LessonType.lab && part.room == "B204")
        part = split("線形代数\n301\n田中先生", languages: ["ja"])
        #expect(part.teacher == "田中先生")
        // "(P)" is only a type code for languages that use it.
        part = split("Analysis (P)", languages: ["en"])
        #expect(part.lessonType == nil)
    }

    @Test func lookAlikesAreCorrectedAndAsked() {
        let part = split("Matematika\n2O4")
        #expect(part.room == "204")
        #expect(part.reasons == [.ocrConfusion])
        #expect(part.alternatives == [ImportAlternative(field: .room, kind: .ocrReading, values: ["204", "2O4"])])
        #expect(split("Informatika\nI3").room == "I3") // a letter before a digit is a real room code
    }

    @Test func hiddenFieldsGoToNotes() {
        let part = split("Mathe\nR104\nHerr Becker", languages: ["de"], options: ImportParserOptions(enabledFields: [.room]))
        #expect(part.room == "R104" && part.teacher == nil && part.notes == ["Herr Becker"])
    }

    @Test func unclearExtraTextIsKeptAndQuestioned() {
        let part = split("Odborná prax\nZŠ Hlboká ulica")
        #expect(part.subject == "Odborná prax")
        #expect(part.notes == ["ZŠ Hlboká ulica"])
        #expect(part.reasons == [.ambiguousSplit])
        #expect(part.alternatives.first?.kind == .split)
    }

    @Test func knownSubjectAbbreviation() {
        let options = ImportParserOptions(knownSubjects: ["Biológia", "Matematika"])
        let part = split("Bio\n204", options: options)
        #expect(part.subject == "Bio")
        #expect(part.alternatives == [ImportAlternative(field: .subject, kind: .abbreviation, values: ["Bio", "Biológia"])])
        #expect(split("matematika\n204", options: options).subject == "Matematika") // exact match takes the known spelling
    }

    @Test func weekMarkers() {
        let options = ImportParserOptions()
        for text in ["MAT 204 (A)\nFYZ 105 (B)", "A: MAT 204\nB: FYZ 105", "MAT 204 (A) / FYZ 105 (B)", "MAT 204\n(A)\nFYZ 105\n(B)"] {
            let parts = ImportCellSplitter.split(text, options: options, languages: ["sk"])
            #expect(parts.map(\.subject) == ["MAT", "FYZ"], "\(text)")
            #expect(parts.map(\.room) == ["204", "105"], "\(text)")
            #expect(parts.map(\.weeks) == [[1], [2]], "\(text)")
        }
    }
}

@Suite("Import: parser")
struct ImportParserStructureTests {
    /// A small aSc-style table: header "1"/"7.00", rows Po–Ut, a two-period merged cell and an empty cell.
    private var asc: [RecognizedCell] {
        [cell("1\n7.00", 0, 1), cell("2\n7.50", 0, 2), cell("3\n8.40", 0, 3),
         cell("Po", 1, 0), cell("prax\naaa", 1, 2, span: 2),
         cell("Ut", 2, 0), cell("SPAJ\n3P1", 2, 1), cell("", 2, 2), cell("SAL\n3S1", 2, 3)]
    }

    @Test func daysAsRows() {
        let candidate = parse(asc)
        #expect(candidate.orientation == .daysAsRows)
        #expect(candidate.days == [.monday, .tuesday])
        #expect(candidate.periods.map(\.number) == [1, 2, 3])
        #expect(candidate.lessons.map { "\($0.day.rawValue) \($0.period)+\($0.span) \($0.subject) \($0.room ?? "")" }
                == ["1 2+2 prax aaa", "2 1+1 SPAJ 3P1", "2 3+1 SAL 3S1"])
        #expect(candidate.lessons.allSatisfy { $0.reasons == [] && !$0.needsReview })
    }

    @Test func daysAsColumnsIsTheTranspose() {
        let transposed = asc.map { RecognizedCell(text: $0.text, row: $0.column, column: $0.row, rowSpan: $0.columnSpan,
                                                  columnSpan: $0.rowSpan, confidence: $0.confidence) }
        let rows = parse(asc), columns = parse(transposed)
        #expect(columns.orientation == .daysAsColumns)
        #expect(columns.lessons.map(\.subject) == rows.lessons.map(\.subject))
        #expect(columns.lessons.map(\.span) == rows.lessons.map(\.span))
        #expect(columns.lessons.map(\.source) == rows.lessons.map { ImportCellRef(row: $0.source.column, column: $0.source.row) })
    }

    @Test func emptyAndDaylessInput() {
        #expect(parse([]).notices == [.emptyInput])
        #expect(parse([cell("", 0, 0)]).notices == [.emptyInput])
        let none = parse([cell("MAT", 0, 0), cell("FYZ", 0, 1)])
        #expect(none.notices == [.noDaysFound] && none.lessons.isEmpty)
    }

    @Test func overlapsAreConflictsAndLowOCRIsFlagged() {
        let candidate = parse([cell("1", 0, 1), cell("2", 0, 2), cell("Po", 1, 0), cell("MAT", 1, 1, span: 2),
                               cell("Po", 2, 0), cell("FYZ", 2, 2, confidence: 0.3)])
        // Second "Po" row starts a new block (week B), so no conflict there; make a real overlap via a two-row day.
        #expect(candidate.weekCycleLength == 2)
        let overlap = parse([cell("1", 0, 1), cell("2", 0, 2), cell("Po", 1, 0), cell("MAT", 1, 1, span: 2), cell("FYZ", 2, 2, confidence: 0.3)])
        #expect(overlap.lessons.allSatisfy { $0.reasons.contains(.timeConflict) })
        #expect(overlap.lessons[1].reasons.contains(.ocrLow) && overlap.lessons[1].needsReview)
    }

    @Test func unreadableLabelTakesTheNextDay() {
        let candidate = parse([cell("Po", 0, 0), cell("MAT", 0, 1), cell("?t", 1, 0), cell("FYZ", 1, 1), cell("St", 2, 0), cell("CHE", 2, 1)])
        #expect(candidate.lessons.map(\.day) == [.monday, .tuesday, .wednesday])
        #expect(candidate.lessons[1].reasons == [.unknownDay, .unknownPeriod, .timeInferred]) // no header row either
    }

    /// Property: on random tables the parser never makes a lesson from nothing, keeps every lesson inside the period
    /// grid, is deterministic, and its result always becomes a valid share payload.
    @Test func randomTablesProperties() throws {
        var rng = TestRNG(seed: 0x1A_B0_C7)
        let words = ["MAT", "FYZ 204", "Aula", "SJL\n3P1", "", "7.00", "Mgr. Novák", "(P)", "A: X 1", "B: Y 2", "2O4", "Po", "lab"]
        let days = ["Po", "Ut", "St", "Št", "Pi", "Mo", "Di", "??"]
        var budget = FailureBudget()
        for _ in 0..<300 {
            let rows = Int.random(in: 1...8, using: &rng), columns = Int.random(in: 1...10, using: &rng)
            var cells: [RecognizedCell] = (1...columns).map { cell(Bool.random(using: &rng) ? "\($0)\n\(7 + $0).00" : "", 0, $0) }
            for row in 1...rows {
                cells.append(cell(days.randomElement(using: &rng)!, row, 0))
                var column = 1
                while column <= columns {
                    let span = Int.random(in: 1...3, using: &rng)
                    cells.append(cell(words.randomElement(using: &rng)!, row, column, span: span,
                                      confidence: Double.random(in: 0.2...1, using: &rng)))
                    column += span
                }
            }
            let table = RecognizedTable(languages: ["sk"], cells: cells)
            let candidate = TimetableImportParser.parse(table)
            #expect(TimetableImportParser.parse(table) == candidate)
            let texts = Set(cells.map(\.text))
            let numbers = candidate.periods.map(\.number)
            for lesson in candidate.lessons {
                guard texts.contains(lesson.sourceText), !lesson.subject.isEmpty,
                      let first = numbers.firstIndex(of: lesson.period), first + lesson.span <= numbers.count,
                      (0...1).contains(lesson.confidence) else {
                    if !budget.record("bad lesson \(lesson) in \(cells)") { return }
                    continue
                }
            }
            for (a, b) in zip(candidate.periods, candidate.periods.dropFirst()) where !(a.start < a.end && a.end <= b.start) {
                if !budget.record("overlapping periods \(candidate.periods)") { return }
            }
            if !candidate.lessons.isEmpty {
                do { _ = try ImportPayloadBuilder.payload(from: candidate, name: "T", bellScheduleName: "B") } catch {
                    if !budget.record("payload \(error) for \(candidate)") { return }
                }
            }
        }
    }
}

@Suite("Import: line clustering")
struct ImportClusteringTests {
    private func line(_ text: String, _ x: Double, _ y: Double, width: Double = 0.04) -> RecognizedLine {
        RecognizedLine(text: text, box: NormalizedRect(x: x - width / 2, y: y, width: width, height: 0.015), confidence: 0.9)
    }

    @Test func daysAsRowsWithHeaderAndMultiLineCells() {
        let lines = [line("1", 0.3, 0.05), line("7.00", 0.3, 0.07), line("2", 0.6, 0.05), line("7.50", 0.6, 0.07),
                     line("Po", 0.05, 0.2), line("MAT", 0.3, 0.19), line("204", 0.3, 0.21),
                     line("Ut", 0.05, 0.4), line("FYZ", 0.6, 0.39), line("105", 0.6, 0.41)]
        let cells = LineClustering.cells(from: lines)
        let texts = cells.map { "\($0.row),\($0.column) \($0.text)" }
        #expect(texts == ["0,1 1\n7.00", "0,2 2\n7.50", "1,0 Po", "1,1 MAT\n204", "2,0 Ut", "2,2 FYZ\n105"])
        let candidate = TimetableImportParser.parse(RecognizedTable(lines: lines))
        #expect(candidate.lessons.map { "\($0.day.rawValue) \($0.period) \($0.subject) \($0.room ?? "")" } == ["1 1 MAT 204", "2 2 FYZ 105"])
    }

    @Test func wideLineIsAMergedCell() {
        let lines = [line("1", 0.25, 0.05), line("2", 0.5, 0.05), line("3", 0.75, 0.05),
                     line("Po", 0.05, 0.2), line("Odborná prax v škole", 0.375, 0.2, width: 0.3), line("Ut", 0.05, 0.4)]
        let lesson = TimetableImportParser.parse(RecognizedTable(lines: lines)).lessons.first
        #expect(lesson?.period == 1 && lesson?.span == 2)
    }

    @Test func daysAcrossThePage() {
        let lines = [line("Mon", 0.3, 0.05), line("Tue", 0.6, 0.05), line("1", 0.05, 0.2), line("2", 0.05, 0.4),
                     line("Maths", 0.3, 0.2), line("Art", 0.6, 0.4)]
        let candidate = TimetableImportParser.parse(RecognizedTable(lines: lines))
        #expect(candidate.orientation == .daysAsColumns)
        #expect(candidate.lessons.map { "\($0.day.rawValue) \($0.period) \($0.subject)" } == ["1 1 Maths", "2 2 Art"])
    }

    @Test func noAnchorsStillGivesAGrid() {
        let cells = LineClustering.cells(from: [line("a", 0.2, 0.1), line("b", 0.6, 0.1), line("c", 0.2, 0.5)])
        #expect(cells.map { "\($0.row),\($0.column) \($0.text)" } == ["0,0 a", "0,1 b", "1,0 c"])
    }
}

@Suite("Import: reconciliation and payload")
struct ImportReconciliationTests {
    private var candidate: ImportCandidate {
        TimetableImportParser.parse(RecognizedTable(languages: ["sk"], cells: [
            cell("1\n8:00-8:45", 0, 1), cell("2\n8:55-9:40", 0, 2),
            cell("Po", 1, 0), cell("Matematika\n2O4", 1, 1, confidence: 0.5), cell("Odborná prax\nZŠ Hlboká ulica", 1, 2),
            cell("Ut", 2, 0), cell("Bio\n105", 2, 1),
        ]))
    }

    @Test func requestHoldsOnlyLowConfidenceCells() {
        let request = ImportReconciliation.request(for: candidate)
        #expect(request.cells.map(\.id) == [0, 1])
        #expect(request.cells[0].reasons == [.ocrLow, .ocrConfusion])
    }

    @Test func deterministicNormaliserChangesNothing() async {
        let base = candidate
        #expect(await ImportReconciliation.normalise(base, using: DeterministicNormaliser()) == base)
    }

    @Test func verbatimValuesApplyOthersBecomeQuestions() {
        let suggestions = [
            NormalisationSuggestion(id: 1, subject: .value("Odborná prax"), room: .value("ZŠ Hlboká ulica")), // verbatim
            NormalisationSuggestion(id: 0, subject: .value("Matematika (Mathematics)"), room: .unknown(alternatives: ["204", "2O4"])),
            NormalisationSuggestion(id: 2, subject: .value("Biológia")), // id 2 is not low-confidence: ignored
            NormalisationSuggestion(id: 99, subject: .value("Invented")), // unknown cell: ignored
        ]
        let result = ImportReconciliation.apply(suggestions, to: candidate)
        #expect(result.lessons.count == candidate.lessons.count)
        #expect(result.lessons[1].room == "ZŠ Hlboká ulica")
        #expect(!result.lessons[1].reasons.contains(.ambiguousSplit) && result.lessons[1].reasons.contains(.normaliser))
        #expect(result.lessons[1].confidence > candidate.lessons[1].confidence)
        #expect(result.lessons[0].subject == "Matematika") // not in the cell: offered, not applied
        #expect(result.lessons[0].alternatives.contains(ImportAlternative(field: .subject, kind: .normaliser,
                                                                          values: ["Matematika", "Matematika (Mathematics)"])))
        #expect(result.lessons[2] == candidate.lessons[2])
        #expect(!result.lessons.contains { $0.subject == "Invented" })
    }

    @Test func failingNormaliserFallsBack() async {
        struct Failing: CellNormaliser {
            struct Unavailable: Error {}
            func normalise(_ request: NormalisationRequest) async throws -> [NormalisationSuggestion] { throw Unavailable() }
        }
        let base = candidate
        #expect(await ImportReconciliation.normalise(base, using: Failing()) == base)
    }

    @Test func jsonShapes() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(NormalisedValue.value("204")), as: UTF8.self) == #"{"kind":"value","value":"204"}"#)
        let unknown = try JSONDecoder().decode(NormalisedValue.self, from: Data(#"{"kind":"unknown","alternatives":["a","b"]}"#.utf8))
        #expect(unknown == .unknown(alternatives: ["a", "b"]))
        let table = RecognizedTable(languages: ["sk"], cells: [cell("Po", 0, 0)], lines: [RecognizedLine(text: "x", box: .init(x: 0, y: 0, width: 1, height: 1))])
        #expect(try JSONDecoder().decode(RecognizedTable.self, from: encoder.encode(table)) == table)
        let base = candidate
        #expect(try JSONDecoder().decode(ImportCandidate.self, from: encoder.encode(base)) == base)
        // Minimal hand-written cell JSON: spans and confidence default.
        let minimal = try JSONDecoder().decode(RecognizedCell.self, from: Data(#"{"text":"Po","row":1,"column":0}"#.utf8))
        #expect((minimal.rowSpan, minimal.columnSpan, minimal.confidence) == (1, 1, 1))
    }

    @Test func payloadImportsThroughTheSharePath() throws {
        let base = candidate
        let payload = try ImportPayloadBuilder.payload(from: base, name: "Rozvrh", bellScheduleName: "Zvonenie")
        #expect(payload.subjects.map(\.name) == ["Matematika", "Odborná prax", "Bio"])
        #expect(payload.bellSchedules[0].periods.map(\.key) == [1, 2])
        #expect(payload.lessons.count == 3)
        #expect(payload.timetable.enabledDays == [.monday, .tuesday])
        #expect(payload.timetable.fieldVisibility == [.room, .notes])
        var ids = SequentialIDGenerator(namespace: 0x1A)
        var clock = HybridLogicalClock(node: 0x1A)
        let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Date(timeIntervalSince1970: 0))
        #expect(imported.lessons.count == 3)
    }
}
