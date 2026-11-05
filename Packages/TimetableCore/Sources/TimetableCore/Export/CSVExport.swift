import Foundation

/// RFC 4180 CSV: UTF-8 with BOM (so Excel detects the encoding), CRLF after every record, header first.
public enum CSVExport {
    /// The CSV file of `rows` with `labels.header` as the first record.
    public static func data(rows: [ExportRow], labels: ExportLabels) -> Data {
        var text = record(labels.header)
        for row in rows { text += record(labels.cells(row)) }
        return Data([0xEF, 0xBB, 0xBF] + Array(text.utf8))
    }

    static func record(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }

    /// One field: formula-neutralised, then quoted when it contains a comma, quote, CR or LF.
    static func field(_ value: String) -> String {
        // Subjects can come from someone else's share code: a leading = + - @ TAB CR would run as a spreadsheet
        // formula (CSV injection), so it gets a leading apostrophe (OWASP); XLSX inline strings never evaluate.
        var value = value
        if startsLikeFormula(value) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `true` when a spreadsheet could read `value` as a formula: it starts with = + - @ TAB CR, a space (some
    /// apps trim it first) or the full-width ＝＋－＠ (Excel normalises them). Shared with `XLSXExport`.
    static func startsLikeFormula(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        return "=+-@\t\r \u{FF1D}\u{FF0B}\u{FF0D}\u{FF20}".unicodeScalars.contains(first)
    }
}
