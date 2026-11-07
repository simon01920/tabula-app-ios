import CZlib
import Foundation

/// A minimal Office Open XML workbook: one sheet and a minimal styles part (no shared strings).
///
/// - **Dates and times are numbers** (Phase 10): the date column holds Excel serial days (1900 date system) with the
///   `yyyy-mm-dd` format, start and end hold fractions of a day with `hh:mm`, so Excel and Numbers sort, filter
///   and compute with them. A date before 1900-01-01 (which Excel cannot represent) stays a `yyyy-MM-dd` string.
/// - **Text cells are inline strings**, which never evaluate as formulas, so shared subject names cannot inject
///   one. A text that the CSV writer would neutralise (`CSVExport.startsLikeFormula`) also gets the `quotePrefix`
///   style, so editing the cell in Excel keeps it text instead of turning it into a formula.
public enum XLSXExport {
    /// The `.xlsx` file of `rows` with `labels.header` as row 1. `sheetName` is sanitised to Excel's rules
    /// (no `[]:*?/\`, at most 31 characters, "Sheet1" when nothing is left).
    public static func data(rows: [ExportRow], labels: ExportLabels, sheetName: String = "Sheet1") -> Data {
        Data(Zip.archive(parts(rows: rows, labels: labels, sheetName: sheetName)))
    }

    static let declaration = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
    static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let docRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let columns = Array("ABCDEFG")  // shortcut: 7 fixed columns; a 27th needs two-letter references.

    /// The package parts in archive order.
    static func parts(rows: [ExportRow], labels: ExportLabels, sheetName: String) -> [(name: String, bytes: [UInt8])] {
        let contentTypes = declaration
            + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
            + #"<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
            + #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
            + "</Types>"
        let rootRels = declaration + #"<Relationships xmlns="\#(relNS)">"#
            + #"<Relationship Id="rId1" Type="\#(docRel)/officeDocument" Target="xl/workbook.xml"/></Relationships>"#
        let workbook = declaration + #"<workbook xmlns="\#(mainNS)" xmlns:r="\#(docRel)"><sheets>"#
            + #"<sheet name="\#(escape(sanitizedSheetName(sheetName)))" sheetId="1" r:id="rId1"/></sheets></workbook>"#
        let workbookRels = declaration + #"<Relationships xmlns="\#(relNS)">"#
            + #"<Relationship Id="rId1" Type="\#(docRel)/worksheet" Target="worksheets/sheet1.xml"/>"#
            + #"<Relationship Id="rId2" Type="\#(docRel)/styles" Target="styles.xml"/></Relationships>"#
        // Column A is widened so a formatted date never shows as "####" at the default width.
        var sheet = declaration + #"<worksheet xmlns="\#(mainNS)">"#
            + #"<cols><col min="1" max="1" width="12" customWidth="1"/></cols><sheetData>"#
        sheet += #"<row r="1">"#
        for (column, value) in labels.header.enumerated() { sheet += textCell("\(columns[column])1", value) }
        sheet += "</row>"
        for (index, row) in rows.enumerated() {
            let number = index + 2
            let cells = labels.cells(row)
            sheet += #"<row r="\#(number)">"#
            if let serial = serialDay(row.date) {
                sheet += numberCell("A\(number)", style: .date, String(serial))
            } else {
                sheet += textCell("A\(number)", cells[0])
            }
            sheet += numberCell("B\(number)", style: .time, dayFraction(row.start))
            sheet += numberCell("C\(number)", style: .time, dayFraction(row.end))
            for column in 3..<cells.count { sheet += textCell("\(columns[column])\(number)", cells[column]) }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        // The styles part goes last so the earlier parts keep their archive positions.
        return [("[Content_Types].xml", contentTypes), ("_rels/.rels", rootRels), ("xl/workbook.xml", workbook),
                ("xl/_rels/workbook.xml.rels", workbookRels), ("xl/worksheets/sheet1.xml", sheet),
                ("xl/styles.xml", styles)]
            .map { ($0.0, Array($0.1.utf8)) }
    }

    // MARK: Styles and typed cells

    /// Index of a cell format in the `cellXfs` of `styles` (the `s` attribute of a cell).
    enum CellStyle: Int, CaseIterable {
        /// General (header and ordinary text).
        case general = 0
        /// `yyyy-mm-dd` (custom number format 164).
        case date = 1
        /// `hh:mm` (custom number format 165).
        case time = 2
        /// General with `quotePrefix`: text that looks like a formula stays text when edited.
        case formulaLikeText = 3
    }

    /// First custom number format ID (0…163 are reserved for built-in formats).
    static let dateFormatID = 164
    static let timeFormatID = 165

    /// `xl/styles.xml`: the two number formats and one `cellXfs` entry per `CellStyle`, in its order, plus the
    /// font, fills, border and "Normal" style every SpreadsheetML style sheet must have (§18.8, element order).
    static let styles = declaration + #"<styleSheet xmlns="\#(mainNS)">"#
        + #"<numFmts count="2"><numFmt numFmtId="\#(dateFormatID)" formatCode="yyyy-mm-dd"/>"#
        + #"<numFmt numFmtId="\#(timeFormatID)" formatCode="hh:mm"/></numFmts>"#
        + #"<fonts count="1"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>"#
        + #"<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>"#
        + #"<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"#
        + #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
        + #"<cellXfs count="4">"#
        + #"<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>"#
        + #"<xf numFmtId="\#(dateFormatID)" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>"#
        + #"<xf numFmtId="\#(timeFormatID)" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>"#
        + #"<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" quotePrefix="1"/>"#
        + "</cellXfs>"
        + #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
        + "</styleSheet>"

    /// Days since 1970-01-01 of 1899-12-30, day 0 of Excel's 1900 date system for dates from 1900-03-01 on.
    static let serialEpochOffset = 25_569

    /// The Excel serial day of `date` (1900 date system): 1 = 1900-01-01. Excel counts the nonexistent
    /// 1900-02-29 as day 60 (Lotus 1-2-3 compatibility), so dates before 1900-03-01 are one lower than the plain
    /// day count; `nil` before 1900-01-01, which Excel cannot represent.
    static func serialDay(_ date: LocalDate) -> Int? {
        let days = date.daysSinceEpoch + serialEpochOffset  // 61 = 1900-03-01
        let serial = days < 61 ? days - 1 : days
        return serial >= 1 ? serial : nil
    }

    /// `time` as a fraction of a day (Excel's time value), in Swift's shortest round-trip decimal form.
    static func dayFraction(_ time: LocalTime) -> String {
        String(Double(time.minuteOfDay) / Double(LocalTime.minutesPerDay))
    }

    /// A number cell with `style`.
    static func numberCell(_ reference: String, style: CellStyle, _ value: String) -> String {
        #"<c r="\#(reference)" s="\#(style.rawValue)"><v>\#(value)</v></c>"#
    }

    /// An inline-string cell; formula-like text (the CSV writer's rule) gets `CellStyle.formulaLikeText`.
    static func textCell(_ reference: String, _ value: String) -> String {
        let style = CSVExport.startsLikeFormula(value) ? #" s="\#(CellStyle.formulaLikeText.rawValue)""# : ""
        return #"<c r="\#(reference)"\#(style) t="inlineStr"><is><t xml:space="preserve">"# + escape(value) + "</t></is></c>"
    }

    /// XML text/attribute escaping; drops characters XML 1.0 forbids (controls other than TAB, LF, CR, and
    /// U+FFFE/U+FFFF), which would make Excel reject the file.
    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func sanitizedSheetName(_ name: String) -> String {
        var cleaned = String(name.filter { !"[]:*?/\\".contains($0) }.prefix(31))
        // Excel rejects a name that starts or ends with an apostrophe and the reserved name "History".
        while cleaned.first == "'" { cleaned.removeFirst() }
        while cleaned.last == "'" { cleaned.removeLast() }
        if cleaned.lowercased() == "history" { cleaned += "_" }
        return cleaned.isEmpty ? "Sheet1" : cleaned
    }
}

/// A minimal ZIP writer (PKWARE APPNOTE 4.3): local headers, central directory, end record; no ZIP64, no
/// encryption. Each entry is DEFLATE-compressed through the system zlib when that is smaller, else stored.
/// Timestamps are fixed (1980-01-01 00:00) so the output is deterministic.
enum Zip {
    static func archive(_ entries: [(name: String, bytes: [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for entry in entries {
            let name = Array(entry.name.utf8)
            let checksum = crc32(entry.bytes)
            let deflated = try? ShareDeflate.compress(entry.bytes)
            let useDeflate = deflated.map { $0.count < entry.bytes.count } ?? false
            let payload = useDeflate ? deflated! : entry.bytes
            // version needed 2.0, flags 0, method, DOS time 00:00, DOS date 1980-01-01, CRC, sizes, name length.
            var common: [UInt8] = []
            common.le16(20); common.le16(0); common.le16(useDeflate ? 8 : 0); common.le16(0); common.le16(0x21)
            common.le32(checksum); common.le32(UInt32(payload.count)); common.le32(UInt32(entry.bytes.count))
            common.le16(UInt16(name.count))
            let offset = UInt32(out.count)
            out.le32(0x0403_4B50); out += common; out.le16(0); out += name; out += payload
            central.le32(0x0201_4B50); central.le16(20); central += common
            central.le16(0); central.le16(0); central.le16(0); central.le16(0); central.le32(0)  // extra, comment, disk, attrs
            central.le32(offset); central += name
        }
        let centralOffset = UInt32(out.count)
        out += central
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(centralOffset); out.le16(0)
        return out
    }

    /// CRC-32 (ISO-HDLC, as ZIP uses) from the system zlib.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(CZlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }
}

private extension Array where Element == UInt8 {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xFF)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) } }
}
