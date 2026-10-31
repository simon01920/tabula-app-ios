import CZlib
import Foundation

/// A minimal Office Open XML workbook: one sheet, every cell an inline string (no shared strings, no styles).
/// Inline strings never evaluate as formulas, so shared subject names cannot inject one.
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
            + "</Types>"
        let rootRels = declaration + #"<Relationships xmlns="\#(relNS)">"#
            + #"<Relationship Id="rId1" Type="\#(docRel)/officeDocument" Target="xl/workbook.xml"/></Relationships>"#
        let workbook = declaration + #"<workbook xmlns="\#(mainNS)" xmlns:r="\#(docRel)"><sheets>"#
            + #"<sheet name="\#(escape(sanitizedSheetName(sheetName)))" sheetId="1" r:id="rId1"/></sheets></workbook>"#
        let workbookRels = declaration + #"<Relationships xmlns="\#(relNS)">"#
            + #"<Relationship Id="rId1" Type="\#(docRel)/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#
        var sheet = declaration + #"<worksheet xmlns="\#(mainNS)"><sheetData>"#
        for (index, cells) in ([labels.header] + rows.map(labels.cells)).enumerated() {
            let number = index + 1
            sheet += #"<row r="\#(number)">"#
            for (column, value) in cells.enumerated() {
                sheet += #"<c r="\#(columns[column])\#(number)" t="inlineStr"><is><t xml:space="preserve">"#
                    + escape(value) + "</t></is></c>"
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        return [("[Content_Types].xml", contentTypes), ("_rels/.rels", rootRels), ("xl/workbook.xml", workbook),
                ("xl/_rels/workbook.xml.rels", workbookRels), ("xl/worksheets/sheet1.xml", sheet)]
            .map { ($0.0, Array($0.1.utf8)) }
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
        let cleaned = String(name.filter { !"[]:*?/\\".contains($0) }.prefix(31))
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
