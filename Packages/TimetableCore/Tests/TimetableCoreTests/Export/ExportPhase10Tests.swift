import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
@testable import TimetableCore

/// Phase 10 WP4: ICS line folding fast path (C7), VTIMEZONE from offset changes (K1), XLSX styles part.
@Suite("Export writers — Phase 10")
struct ExportPhase10Tests {
    // MARK: C7 folding

    /// The pre-Phase-10 `ICSExport.fold`, verbatim.
    static func referenceFold(_ line: String) -> String {
        var out = ""
        var octets = 0
        for scalar in line.unicodeScalars {
            let width = UTF8.width(scalar)
            if octets + width > 75 {
                out += "\r\n "
                octets = 1
            }
            out.unicodeScalars.append(scalar)
            octets += width
        }
        return out + "\r\n"
    }

    @Test func foldEqualsReferenceByteForByte() {
        var lines = (0...200).map { String(repeating: "x", count: $0) }
        // Scalars of every UTF-8 width, and a combining mark (String equality would hide a reordering).
        let alphabet: [Unicode.Scalar] = ["a", ";", "\u{E9}", "\u{10D}", "\u{301}", "\u{20AC}", "\u{6642}", "\u{1F392}"]
        var rng = TestRNG(seed: 0xC7)
        for _ in 0..<2_000 {
            var line = ""
            for _ in 0..<Int.random(in: 0...90, using: &rng) { line.unicodeScalars.append(alphabet.randomElement(using: &rng)!) }
            lines.append(line)
        }
        for line in lines {
            #expect(Array(ICSExport.fold(line).utf8) == Array(Self.referenceFold(line).utf8), "\(line.utf8.count) octets")
        }
    }

    // MARK: K1 VTIMEZONE

    /// The pre-Phase-10 `ICSExport.vtimezone` (transitions from `nextDaylightSavingTimeTransition`).
    static func referenceVTimezone(_ zone: TimeZone, from first: LocalDate, through last: LocalDate) -> [String] {
        let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
        let start = context.startOfDay(first)
        let end = context.startOfDay(last.adding(days: 1))
        var lines = ["BEGIN:VTIMEZONE", "TZID:" + zone.identifier]
        func observance(at instant: Date, offsetFrom: Int, offsetTo: Int, onset: String) {
            let kind = zone.isDaylightSavingTime(for: instant) ? "DAYLIGHT" : "STANDARD"
            lines += ["BEGIN:" + kind, "DTSTART:" + onset, "TZOFFSETFROM:" + ICSExport.offset(offsetFrom),
                      "TZOFFSETTO:" + ICSExport.offset(offsetTo), "END:" + kind]
        }
        let initial = zone.secondsFromGMT(for: start)
        observance(at: start, offsetFrom: initial, offsetTo: initial, onset: ICSExport.format(first, .midnight))
        var cursor = start
        while let transition = zone.nextDaylightSavingTimeTransition(after: cursor), transition < end {
            let from = zone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let to = zone.secondsFromGMT(for: transition)
            if from != to {
                observance(at: transition, offsetFrom: from, offsetTo: to,
                           onset: ICSExport.format(localSeconds: CalendarContext.floorSeconds(transition) + Int64(from)))
            }
            cursor = transition
        }
        return lines + ["END:VTIMEZONE"]
    }

    @Test(arguments: ["Europe/Bratislava", "America/New_York", "Australia/Sydney"])
    func vtimezoneUnchangedForDSTOnlyZones(zoneID: String) {
        let zone = Fixture.zone(zoneID)
        for year in 2020...2030 {
            let ranges = [(LocalDate(year: year, month: 1, day: 1)!, LocalDate(year: year, month: 12, day: 31)!),
                          (LocalDate(year: year, month: 3, day: 20)!, LocalDate(year: year, month: 4, day: 10)!),
                          (LocalDate(year: year, month: 9, day: 25)!, LocalDate(year: year, month: 11, day: 5)!)]
            for (first, last) in ranges {
                #expect(ICSExport.vtimezone(zone, from: first, through: last) == Self.referenceVTimezone(zone, from: first, through: last),
                        "\(zoneID) \(first)…\(last)")
            }
        }
    }

    @Test func vtimezoneHasStandardOffsetChangeCaracas2016() {
        // Venezuela moved from −04:30 to −04:00 at 02:30 local on 1 May 2016: no DST involved.
        let lines = ICSExport.vtimezone(Fixture.zone("America/Caracas"), from: Fixture.date("2016-04-25"),
                                        through: Fixture.date("2016-05-05"))
        #expect(lines == ["BEGIN:VTIMEZONE", "TZID:America/Caracas",
                          "BEGIN:STANDARD", "DTSTART:20160425T000000", "TZOFFSETFROM:-0430", "TZOFFSETTO:-0430", "END:STANDARD",
                          "BEGIN:STANDARD", "DTSTART:20160501T023000", "TZOFFSETFROM:-0430", "TZOFFSETTO:-0400", "END:STANDARD",
                          "END:VTIMEZONE"])
    }

    @Test func vtimezoneHasStandardOffsetChangeVolgograd2020() {
        // Volgograd returned from +04 to +03 (MSK) at 02:00 local on 27 Dec 2020.
        let lines = ICSExport.vtimezone(Fixture.zone("Europe/Volgograd"), from: Fixture.date("2020-12-20"),
                                        through: Fixture.date("2021-01-05"))
        #expect(lines == ["BEGIN:VTIMEZONE", "TZID:Europe/Volgograd",
                          "BEGIN:STANDARD", "DTSTART:20201220T000000", "TZOFFSETFROM:+0400", "TZOFFSETTO:+0400", "END:STANDARD",
                          "BEGIN:STANDARD", "DTSTART:20201227T020000", "TZOFFSETFROM:+0400", "TZOFFSETTO:+0300", "END:STANDARD",
                          "END:VTIMEZONE"])
    }

    @Test func vtimezoneHasSamoaSkippedDay() {
        // Samoa skipped 30 Dec 2011: 29 Dec 24:00 at −10:00 became 31 Dec 00:00 at +14:00.
        let lines = ICSExport.vtimezone(Fixture.zone("Pacific/Apia"), from: Fixture.date("2011-12-26"),
                                        through: Fixture.date("2012-01-02"))
        #expect(lines.filter { $0.hasPrefix("BEGIN:") }.count == 3)  // VTIMEZONE, initial, the change
        let change = Array(lines.drop { $0 != "DTSTART:20111230T000000" }.prefix(3))
        #expect(change == ["DTSTART:20111230T000000", "TZOFFSETFROM:-1000", "TZOFFSETTO:+1400"])
    }

    @Test(arguments: ["Australia/Lord_Howe", "America/Santiago", "Asia/Gaza", "Pacific/Apia", "Europe/Volgograd",
                      "America/Caracas", "Asia/Tokyo"])
    func offsetChangesAreExactAndComplete(zoneID: String) {
        let zone = Fixture.zone(zoneID)
        func offset(_ seconds: Int64) -> Int { zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))) }
        let lower = Int64(Fixture.date("2011-01-01").daysSinceEpoch) * 86_400
        let upper = Int64(Fixture.date("2031-01-01").daysSinceEpoch) * 86_400
        let changes = ICSExport.offsetChanges(zone, after: lower, before: upper)
        for change in changes {
            #expect(change.from == offset(change.utcSeconds - 1) && change.to == offset(change.utcSeconds) && change.from != change.to,
                    "\(zoneID) \(change)")
        }
        #expect(changes.map(\.utcSeconds) == changes.map(\.utcSeconds).sorted())
        // As many changes as days on which the offset at UTC midnight differs from the next day's.
        var dailyChanges = 0
        var previous = offset(lower)
        for day in stride(from: lower + 86_400, to: upper + 1, by: 86_400) {
            let current = offset(day)
            if current != previous { dailyChanges += 1 }
            previous = current
        }
        #expect(changes.count == dailyChanges, "\(zoneID)")
        #expect(ICSExport.offsetChanges(zone, after: lower, before: lower + 1).isEmpty)
    }

    // MARK: XLSX styles part

    @Test func serialDaysFollowTheExcel1900System() {
        #expect(XLSXExport.serialDay(Fixture.date("1899-12-31")) == nil)
        #expect(XLSXExport.serialDay(Fixture.date("1900-01-01")) == 1)
        #expect(XLSXExport.serialDay(Fixture.date("1900-02-28")) == 59)
        // Serial 60 is Excel's nonexistent 1900-02-29 (Lotus 1-2-3 bug), so 1 March is 61.
        #expect(XLSXExport.serialDay(Fixture.date("1900-03-01")) == 61)
        #expect(XLSXExport.serialDay(Fixture.date("1970-01-01")) == 25_569)
        #expect(XLSXExport.serialDay(Fixture.date("2000-01-01")) == 36_526)
        #expect(XLSXExport.serialDay(Fixture.date("2026-10-19")) == 46_314)
        #expect(XLSXExport.serialDay(Fixture.date("9999-12-31")) == 2_958_465)
    }

    @Test func timesAreExactDayFractions() {
        #expect(XLSXExport.dayFraction(Fixture.time("00:00")) == "0.0")
        #expect(XLSXExport.dayFraction(Fixture.time("06:00")) == "0.25")
        #expect(XLSXExport.dayFraction(Fixture.time("12:00")) == "0.5")
        #expect(XLSXExport.dayFraction(Fixture.time("08:00")) == "0.3333333333333333")
        for minute in 0..<LocalTime.minutesPerDay {
            let text = XLSXExport.dayFraction(LocalTime(minuteOfDay: minute)!)
            let value = Double(text)
            #expect(value.map { Int(($0 * 1440).rounded()) } == minute, "\(minute) → \(text)")
        }
    }

    @Test func workbookDeclaresAWellFormedStylesPart() throws {
        let data = XLSXExport.data(rows: ExportTests.World().rows, labels: ExportTests.labels)
        let entries = try ZipReader.entries(Array(data))
        let parts = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, String(decoding: $0.bytes, as: UTF8.self)) })
        let styles = try #require(parts["xl/styles.xml"])
        #expect(ExportTests.isWellFormed(Array(styles.utf8)))
        let contentTypes = try #require(parts["[Content_Types].xml"])
        #expect(contentTypes.contains(
            #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#))
        let workbookRels = try #require(parts["xl/_rels/workbook.xml.rels"])
        #expect(workbookRels.contains(
            #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#))
        #expect(styles.contains(#"<numFmt numFmtId="164" formatCode="yyyy-mm-dd"/>"#))
        #expect(styles.contains(#"<numFmt numFmtId="165" formatCode="hh:mm"/>"#))
        // One cellXfs entry per CellStyle, in raw-value order.
        let cellXfs = try #require(styles.components(separatedBy: "<cellXfs").last?.components(separatedBy: "</cellXfs>").first)
        #expect(cellXfs.hasPrefix(#" count="\#(XLSXExport.CellStyle.allCases.count)">"#))
        let xfs = cellXfs.components(separatedBy: "<xf ").dropFirst()
        #expect(xfs.count == XLSXExport.CellStyle.allCases.count)
        #expect(Array(xfs)[XLSXExport.CellStyle.date.rawValue].hasPrefix(#"numFmtId="164""#))
        #expect(Array(xfs)[XLSXExport.CellStyle.time.rawValue].hasPrefix(#"numFmtId="165""#))
        #expect(Array(xfs)[XLSXExport.CellStyle.formulaLikeText.rawValue].contains(#"quotePrefix="1""#))
        // Section order of CT_Stylesheet.
        let positions = ["<numFmts", "<fonts", "<fills", "<borders", "<cellStyleXfs", "<cellXfs", "<cellStyles"]
            .compactMap { styles.range(of: $0)?.lowerBound }
        #expect(positions.count == 7 && positions == positions.sorted())
    }

    @Test func datesAndTimesAreNumbersTextStaysInline() throws {
        var rows = ExportTests.World().rows
        rows[1].subject = "=HYPERLINK(\"x\")"
        rows[2].subject = "\u{FF0B}1"
        let entries = try ZipReader.entries(Array(XLSXExport.data(rows: rows, labels: ExportTests.labels)))
        let sheet = try #require(entries.first { $0.name == "xl/worksheets/sheet1.xml" }).bytes
        let xml = String(decoding: sheet, as: UTF8.self)
        #expect(ExportTests.isWellFormed(sheet))
        #expect(xml.contains(#"<cols><col min="1" max="1" width="12" customWidth="1"/></cols>"#))
        // Header stays text; row 2 is Monday 19 Oct 2026, 08:00–08:45.
        #expect(xml.contains(#"<c r="A1" t="inlineStr"><is><t xml:space="preserve">Date</t></is></c>"#))
        #expect(xml.contains(#"<c r="A2" s="1"><v>46314</v></c><c r="B2" s="2"><v>0.3333333333333333</v></c>"#))
        #expect(xml.contains(#"<c r="C2" s="2"><v>0.3645833333333333</v></c><c r="D2" t="inlineStr">"#))
        #expect(xml.components(separatedBy: #" s="1"><v>"#).count - 1 == rows.count)
        #expect(xml.components(separatedBy: #" s="2"><v>"#).count - 1 == 2 * rows.count)
        // Formula-like text: still an inline string (never a formula), with the quotePrefix style.
        #expect(xml.contains(#"<c r="D3" s="3" t="inlineStr"><is><t xml:space="preserve">=HYPERLINK(&quot;x&quot;)</t>"#))
        #expect(xml.contains(#"<c r="D4" s="3" t="inlineStr"><is><t xml:space="preserve">"# + "\u{FF0B}1</t>"))
        #expect(!xml.contains("<f>") && !xml.contains("<f "))
    }

    @Test func dateBefore1900StaysText() throws {
        var rows = ExportTests.World().rows
        rows[0].date = Fixture.date("1899-12-31")
        let entries = try ZipReader.entries(Array(XLSXExport.data(rows: Array(rows.prefix(1)), labels: ExportTests.labels)))
        let xml = String(decoding: try #require(entries.first { $0.name == "xl/worksheets/sheet1.xml" }).bytes, as: UTF8.self)
        #expect(xml.contains(#"<c r="A2" t="inlineStr"><is><t xml:space="preserve">1899-12-31</t></is></c>"#))
    }

    @Test func csvFormulaRuleIsShared() {
        for value in ["=1", "+1", "-1", "@x", "\t1", "\r1", " 1", "\u{FF1D}1", "\u{FF0B}1", "\u{FF0D}1", "\u{FF20}1"] {
            #expect(CSVExport.startsLikeFormula(value), "\(value)")
            let field = CSVExport.field(value)
            #expect(field.hasPrefix("'") || field.hasPrefix("\"'"), "\(value)")
        }
        for value in ["", "Math", "1-2", "'quoted"] { #expect(!CSVExport.startsLikeFormula(value), "\(value)") }
    }
}
