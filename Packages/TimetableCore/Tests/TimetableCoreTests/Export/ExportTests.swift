import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
@testable import TimetableCore

/// Phase 8 E1: export rows, CSV, ICS and XLSX writers.
@Suite("Export writers")
struct ExportTests {
    static let labels = ExportLabels(date: "Date", start: "Start", end: "End", subject: "Subject", room: "Room",
                                     teacher: "Teacher", change: "Change") { row in
        row.status == .cancelled ? "Cancelled" : row.reasons.map(\.rawValue).joined(separator: " ")
    }

    /// A/B weeks (ISO week 43 = A, 44 = B) around the 25 Oct 2026 DST change in Bratislava, with a holiday on
    /// 29–30 Oct, a room change and an added lesson on 20 Oct, and a cancellation on 27 Oct.
    struct World {
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0))))
        let mathA: Lesson.ID, physicsB: Lesson.ID, englishTue: Lesson.ID, englishThu: Lesson.ID
        let added: ScheduleOverride.ID

        init() {
            mathA = world.lesson(world.math, .monday, period: 1, weeks: [1])
            physicsB = world.lesson(world.physics, .monday, period: 1, weeks: [2])
            englishTue = world.lesson(world.english, .tuesday, period: 2)
            englishThu = world.lesson(world.english, .thursday, period: 1)
            world.holiday("2026-10-29", "2026-10-30")
            world.override("2026-10-20", .modifyLesson(englishTue, LessonPatch(room: "B12")))
            added = world.override("2026-10-20", .addLesson(OneOffLesson(subjectID: world.physics, slot: .period(world.p[2], span: 1))))
            world.override("2026-10-27", .cancelLesson(englishTue))
        }

        var database: TabulaDatabase {
            TabulaDatabase(settings: AppSettings(meta: Fixture.meta()), timetables: [world.timetable],
                           subjects: world.subjects, bellSchedules: world.bellSchedules, lessons: world.lessons,
                           terms: world.terms, breaks: world.breaks, overrides: world.overrides)
        }

        var rows: [ExportRow] {
            ExportRows.build(database: database, timetableID: world.timetable.id,
                             range: LocalDateRange(start: Fixture.date("2026-10-19"), end: Fixture.date("2026-10-30")),
                             context: world.context)
        }
    }

    // MARK: Rows

    @Test func rowsFollowRotationHolidayAndOverrides() {
        let w = World()
        let rows = w.rows
        let summary = rows.map { "\($0.date) \($0.start)-\($0.end) \($0.subject) \($0.room ?? "-") \($0.status.rawValue)" }
        #expect(summary == [
            "2026-10-19 08:00-08:45 Math 101 scheduled",
            "2026-10-20 08:55-09:40 English B12 modified",
            "2026-10-20 10:00-10:45 Physics - added",
            "2026-10-22 08:00-08:45 English 201 scheduled",
            "2026-10-26 08:00-08:45 Physics - scheduled",
            "2026-10-27 08:55-09:40 English 201 cancelled",
        ])
        #expect(rows[0].teacher == "Novák" && rows[0].sourceID == w.mathA.uuid)
        #expect(rows[1].reasons == [.roomChanged] && rows[2].sourceID == w.added.uuid)
        #expect(rows[4].sourceID == w.physicsB.uuid)
    }

    @Test func rowsEmptyForUnknownTimetableOrEmptyRange() {
        let w = World()
        #expect(ExportRows.build(database: w.database, timetableID: Timetable.ID(UUID()),
                                 range: LocalDateRange(day: Fixture.date("2026-10-19")), context: w.world.context).isEmpty)
        #expect(ExportRows.build(database: w.database, timetableID: w.world.timetable.id,
                                 range: LocalDateRange(start: Fixture.date("2026-10-20"), end: Fixture.date("2026-10-19")),
                                 context: w.world.context).isEmpty)
    }

    /// Phase 10 WP3 (C5): the resolver entry point gives exactly the rows of the database entry point (same resolver
    /// inputs), across the A/B rotation, the DST change, the holiday and every override kind.
    @Test func resolverEntryPointMatchesDatabaseEntryPoint() throws {
        let w = World()
        let range = LocalDateRange(start: Fixture.date("2026-10-12"), end: Fixture.date("2026-11-08"))
        let resolver = try #require(ScheduleResolver(database: w.database, timetableID: w.world.timetable.id,
                                                     context: w.world.context))
        let viaDatabase = ExportRows.build(database: w.database, timetableID: w.world.timetable.id, range: range,
                                           context: w.world.context)
        // The pre-Phase-10 body of `build(database:…)`, kept here as the independent reference.
        let reference = range.days.flatMap { date in
            let resolution = resolver.resolution(for: date)
            return resolution.schedule.entries.map { entry in
                let sourceID: UUID
                switch entry.source {
                case .lesson(let id): sourceID = id.uuid
                case .oneOff(let id): sourceID = id.uuid
                }
                return ExportRow(occurrenceID: entry.id, sourceID: sourceID, date: entry.date, start: entry.startTime,
                                 end: entry.endTime, subject: entry.subject.name, room: entry.room,
                                 teacher: entry.teacher, status: entry.status, reasons: resolution.reasons(for: entry.id))
            }
        }
        #expect(!viaDatabase.isEmpty)
        #expect(viaDatabase == reference)
        #expect(ExportRows.build(resolver: resolver, range: range) == reference)
        #expect(ExportRows.build(resolver: resolver, range: LocalDateRange(start: Fixture.date("2026-10-20"),
                                                                           end: Fixture.date("2026-10-19"))).isEmpty)
    }

    // MARK: CSV

    @Test func csvQuotesPerRFC4180AndNeutralisesFormulas() {
        #expect(CSVExport.field("plain") == "plain")
        #expect(CSVExport.field("a,b") == "\"a,b\"")
        #expect(CSVExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.field("two\nlines") == "\"two\nlines\"")
        #expect(CSVExport.field("cr\r\nlf") == "\"cr\r\nlf\"")
        #expect(CSVExport.field("=1+1") == "'=1+1")
        #expect(CSVExport.field(" =1") == "' =1")
        #expect(CSVExport.field("\u{FF1D}1") == "'\u{FF1D}1")
        #expect(CSVExport.field("\u{FF20}SUM") == "'\u{FF20}SUM")
        #expect(CSVExport.field("@x,y") == "\"'@x,y\"")
        #expect(CSVExport.field("Fyzika č. 2") == "Fyzika č. 2")
    }

    @Test func csvFileHasBOMHeaderAndCRLFRecords() throws {
        let rows = World().rows
        let data = CSVExport.data(rows: rows, labels: Self.labels)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
        let records = text.components(separatedBy: "\r\n")
        #expect(records.count == rows.count + 2 && records.last == "")
        #expect(records[0] == "Date,Start,End,Subject,Room,Teacher,Change")
        #expect(records[1] == "2026-10-19,08:00,08:45,Math,101,Novák,")
        #expect(records[2] == "2026-10-20,08:55,09:40,English,B12,,roomChanged")
        #expect(records[6] == "2026-10-27,08:55,09:40,English,201,,Cancelled")
    }

    // MARK: ICS

    @Test func icsEscapesText() {
        #expect(ICSExport.escape(#"a,b;c\d"#) == #"a\,b\;c\\d"#)
        #expect(ICSExport.escape("x\ny\r\nz") == #"x\ny\nz"#)
    }

    @Test func icsFoldsAt75OctetsWithoutSplittingUTF8() {
        for line in [String(repeating: "x", count: 200), "SUMMARY:" + String(repeating: "čšž🎒", count: 40), "SHORT:ok"] {
            let folded = ICSExport.fold(line)
            #expect(folded.hasSuffix("\r\n"))
            let physical = folded.dropLast().components(separatedBy: "\r\n")
            for (index, part) in physical.enumerated() {
                #expect(part.utf8.count <= 75)
                #expect(index == 0 || part.hasPrefix(" "))
            }
            // Unfolding (remove CRLF + one space) restores the line, so no UTF-8 sequence was cut.
            #expect(folded.dropLast().replacingOccurrences(of: "\r\n ", with: "") == line)
        }
        #expect(ICSExport.fold(String(repeating: "y", count: 75)) == String(repeating: "y", count: 75) + "\r\n")
    }

    @Test func icsFixedZoneHasVTimezoneAcrossDSTChange() throws {
        let w = World()
        let stamp = Fixture.utc("2026-10-31", "12:34", seconds: 56)
        let data = ICSExport.data(rows: w.rows, labels: Self.labels, timeZone: Fixture.zone("Europe/Bratislava"),
                                  stamp: stamp, calendarName: "School, 2026")
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        let lines = Self.unfolded(text)
        #expect(lines.first == "BEGIN:VCALENDAR" && lines.last == "END:VCALENDAR")
        #expect(lines.contains(#"X-WR-CALNAME:School\, 2026"#))
        let vtimezone = Array(lines.drop { $0 != "BEGIN:VTIMEZONE" }.prefix { $0 != "END:VTIMEZONE" })
        #expect(vtimezone == [
            "BEGIN:VTIMEZONE", "TZID:Europe/Bratislava",
            "BEGIN:DAYLIGHT", "DTSTART:20261019T000000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0200", "END:DAYLIGHT",
            "BEGIN:STANDARD", "DTSTART:20261025T030000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100", "END:STANDARD",
        ])
        #expect(lines.filter { $0 == "BEGIN:VEVENT" }.count == 6)
        #expect(lines.filter { $0 == "DTSTAMP:20261031T123456Z" }.count == 6)
        #expect(lines.contains("UID:\(w.mathA.uuidString)-20261019@tabula"))
        #expect(lines.contains("UID:\(w.added.uuidString)-20261020@tabula"))
        #expect(lines.contains("DTSTART;TZID=Europe/Bratislava:20261019T080000"))
        #expect(lines.contains("DTSTART;TZID=Europe/Bratislava:20261026T080000"))
        #expect(lines.contains("DTEND;TZID=Europe/Bratislava:20261026T084500"))
        #expect(lines.contains("LOCATION:B12"))
        #expect(lines.contains(#"DESCRIPTION:Teacher: Novák"#))
        #expect(lines.contains("DESCRIPTION:roomChanged"))
        #expect(lines.filter { $0 == "STATUS:CANCELLED" }.count == 1)
        #expect(Set(lines.filter { $0.hasPrefix("UID:") }).count == 6)
    }

    @Test func icsVTimezoneWithoutTransitionAndSouthernZone() {
        let summer = ICSExport.vtimezone(Fixture.zone("Europe/Bratislava"), from: Fixture.date("2026-06-01"),
                                         through: Fixture.date("2026-06-30"))
        #expect(summer == ["BEGIN:VTIMEZONE", "TZID:Europe/Bratislava", "BEGIN:DAYLIGHT", "DTSTART:20260601T000000",
                           "TZOFFSETFROM:+0200", "TZOFFSETTO:+0200", "END:DAYLIGHT", "END:VTIMEZONE"])
        // Sydney starts DST on 4 Oct 2026 at 02:00 AEST (+1000 → +1100).
        let sydney = ICSExport.vtimezone(Fixture.zone("Australia/Sydney"), from: Fixture.date("2026-09-28"),
                                         through: Fixture.date("2026-10-09"))
        #expect(sydney.contains("DTSTART:20261004T020000") && sydney.contains("TZOFFSETTO:+1100"))
        #expect(ICSExport.offset(-12_600) == "-0330" && ICSExport.offset(3_661) == "+010101")
    }

    @Test func icsFollowDeviceUsesFloatingTimes() throws {
        let w = World()
        let data = ICSExport.data(rows: w.rows, labels: Self.labels, timeZone: nil, stamp: Fixture.now)
        let lines = Self.unfolded(try #require(String(data: data, encoding: .utf8)))
        #expect(!lines.contains("BEGIN:VTIMEZONE") && !lines.contains { $0.contains("TZID") })
        #expect(lines.contains("DTSTART:20261026T080000") && lines.contains("DTEND:20261026T084500"))
        #expect(!lines.contains { $0.hasPrefix("DTSTART") && $0.hasSuffix("Z") })
    }

    @Test func icsEmptyHasNoTimezone() throws {
        let data = ICSExport.data(rows: [], labels: Self.labels, timeZone: Fixture.zone("Europe/Bratislava"), stamp: Fixture.now)
        #expect(String(data: data, encoding: .utf8) == "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Tabula//Timetable Export//EN\r\nCALSCALE:GREGORIAN\r\nEND:VCALENDAR\r\n")
    }

    static func unfolded(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n ", with: "").components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    // MARK: XLSX

    @Test func xlsxIsAValidZipOfWellFormedParts() throws {
        var rows = World().rows
        rows[0].subject = "A&B <\"x\"> 'y' \u{0B}"
        let data = XLSXExport.data(rows: rows, labels: Self.labels, sheetName: "Rozvrh: 2026/27 [A]")
        let entries = try ZipReader.entries(Array(data))
        #expect(entries.map(\.name) == ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                        "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml", "xl/styles.xml"])
        for entry in entries {
            let xml = try #require(String(bytes: entry.bytes, encoding: .utf8))
            #expect(xml.hasPrefix("<?xml"))
            #expect(Self.isWellFormed(entry.bytes), "\(entry.name) is not well-formed XML")
        }
        let workbook = String(decoding: entries[2].bytes, as: UTF8.self)
        #expect(workbook.contains(#"<sheet name="Rozvrh 202627 A" sheetId="1" r:id="rId1"/>"#))
        let sheet = String(decoding: entries[4].bytes, as: UTF8.self)
        #expect(sheet.contains(#"<c r="A1" t="inlineStr"><is><t xml:space="preserve">Date</t></is></c>"#))
        #expect(sheet.contains("A&amp;B &lt;&quot;x&quot;&gt; &apos;y&apos; </t>"))
        #expect(sheet.contains(#"<c r="G7" t="inlineStr"><is><t xml:space="preserve">Cancelled</t>"#))
        #expect(sheet.components(separatedBy: "<row ").count - 1 == rows.count + 1)
        #expect(entries[4].method == 8)
    }

    @Test func zipStoresWhenDeflateDoesNotHelpAndMatchesKnownCRC() throws {
        #expect(Zip.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        let archive = Zip.archive([("a.txt", Array("x".utf8)), ("b.txt", Array(repeating: UInt8(ascii: "z"), count: 4096))])
        let entries = try ZipReader.entries(archive)
        #expect(entries.map(\.method) == [0, 8])
        #expect(entries[1].bytes.count == 4096 && entries[0].bytes == Array("x".utf8))
        #expect(XLSXExport.sanitizedSheetName("[]:*?/\\") == "Sheet1")
        #expect(XLSXExport.sanitizedSheetName(String(repeating: "n", count: 40)).count == 31)
        #expect(XLSXExport.sanitizedSheetName("'Math'") == "Math")
        #expect(XLSXExport.sanitizedSheetName("''") == "Sheet1")
        #expect(XLSXExport.sanitizedSheetName("history") == "history_")
        #expect(XLSXExport.sanitizedSheetName("History 2") == "History 2")
    }

    static func isWellFormed(_ bytes: [UInt8]) -> Bool {
        XMLParser(data: Data(bytes)).parse()
    }

    // MARK: Size

    @Test func fullTermStaysSmall() throws {
        var world = ScheduleWorld()
        for weekday in Weekday.workweek {
            for period in 1...6 { world.lesson([world.math, world.physics, world.english][period % 3], weekday, period: period) }
        }
        world.holiday("2026-12-23", "2027-01-06")
        let db = TabulaDatabase(settings: AppSettings(meta: Fixture.meta()), timetables: [world.timetable],
                                subjects: world.subjects, bellSchedules: world.bellSchedules, lessons: world.lessons,
                                breaks: world.breaks)
        let rows = ExportRows.build(database: db, timetableID: world.timetable.id,
                                    range: LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2027-01-31")),
                                    context: world.context)
        #expect(rows.count == 98 * 6)  // 109 weekdays, 11 of them in the 23 Dec–6 Jan break
        let csv = CSVExport.data(rows: rows, labels: Self.labels)
        let ics = ICSExport.data(rows: rows, labels: Self.labels, timeZone: world.context.timeZone, stamp: Fixture.now)
        let xlsx = XLSXExport.data(rows: rows, labels: Self.labels)
        #expect(csv.count < 60_000 && ics.count < 300_000 && xlsx.count < 40_000)
        #expect(try ZipReader.entries(Array(xlsx)).count == 6)
    }
}

/// Test-only ZIP reader: walks the central directory, cross-checks each local header, inflates and verifies the
/// CRC-32 with an independent bitwise implementation.
enum ZipReader {
    struct Entry { var name: String; var method: UInt16; var bytes: [UInt8] }
    struct Failure: Error, CustomStringConvertible { var description: String }

    static func entries(_ zip: [UInt8]) throws -> [Entry] {
        func u16(_ at: Int) -> Int { Int(zip[at]) | Int(zip[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
        let end = zip.count - 22
        guard end >= 0, u32(end) == 0x0605_4B50 else { throw Failure(description: "no end record") }
        let count = u16(end + 10)
        guard u16(end + 8) == count else { throw Failure(description: "entry counts differ") }
        var cursor = Int(u32(end + 16))
        guard cursor + Int(u32(end + 12)) == end else { throw Failure(description: "central directory size") }
        var result: [Entry] = []
        for _ in 0..<count {
            guard u32(cursor) == 0x0201_4B50 else { throw Failure(description: "central header signature") }
            let method = UInt16(u16(cursor + 10)), crc = u32(cursor + 16)
            let compressed = Int(u32(cursor + 20)), size = Int(u32(cursor + 24))
            let nameLength = u16(cursor + 28), extra = u16(cursor + 30), comment = u16(cursor + 32)
            let local = Int(u32(cursor + 42))
            let name = String(decoding: zip[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            // Local header repeats version…name length (26 bytes) of the central header from offset 6.
            guard u32(local) == 0x0403_4B50, Array(zip[(local + 4)..<(local + 30)]) == Array(zip[(cursor + 6)..<(cursor + 32)].prefix(26))
            else { throw Failure(description: "local header of \(name)") }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let payload = Array(zip[start..<(start + compressed)])
            let bytes: [UInt8]
            switch method {
            case 0: bytes = payload
            case 8: bytes = try ShareDeflate.decompress(payload, maxOutput: size)
            default: throw Failure(description: "method \(method)")
            }
            guard bytes.count == size, bitwiseCRC(bytes) == crc else { throw Failure(description: "size/CRC of \(name)") }
            result.append(Entry(name: name, method: method, bytes: bytes))
            cursor += 46 + nameLength + extra + comment
        }
        return result
    }

    static func bitwiseCRC(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
