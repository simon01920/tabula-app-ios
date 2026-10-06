import Foundation

/// The single place that configures JSON coding for everything Tabula persists or exchanges.
///
/// - Keys are sorted, slashes are not escaped, so equal values always produce identical bytes.
/// - `Date` is encoded as an **integer** number of milliseconds since 1970-01-01T00:00:00Z
///   (rounded to the nearest millisecond). Integers make decode → encode byte-stable; a floating
///   `millisecondsSince1970` value can drift by one ULP on every round trip.
/// - Decoding accepts integer or fractional millisecond numbers inside `millisecondsRange`; anything else
///   (out of range, `1e300`, non-numbers) is a `DecodingError.dataCorrupted`, never a trap. Encoding a date
///   outside the range throws `EncodingError.invalidValue`, so the store never writes what it cannot read.
public enum TabulaJSON {
    /// The instants Tabula persists: 0001-01-02T00:00:00.000Z … 9999-12-30T23:59:59.999Z, in milliseconds.
    /// One day inside `LocalDate`'s years 1…9999 on each side, so every persisted instant has a wall-clock
    /// date in every time zone (offsets are below ±26 h) and `CalendarContext` never leaves its domain.
    public static let millisecondsRange: ClosedRange<Int64> = -62_135_510_400_000 ... 253_402_214_399_999

    /// Creates the canonical encoder. `pretty` adds indentation for tests and human-readable backups.
    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .custom { date, encoder in
            guard let millis = TabulaJSON.checkedMilliseconds(from: date) else {
                throw EncodingError.invalidValue(date, EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Date outside the persistable range (years 1…9999): \(date.timeIntervalSince1970) s"))
            }
            var container = encoder.singleValueContainer()
            try container.encode(millis)
        }
        return encoder
    }

    /// Creates the canonical decoder (dates as milliseconds since 1970, range-checked).
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let millis = try? container.decode(Int64.self) {
                guard millisecondsRange.contains(millis) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date out of range: \(millis) ms")
                }
                return TabulaJSON.date(fromMilliseconds: millis)
            }
            let value = try container.decode(Double.self)
            guard let millis = checkedMilliseconds(fromDouble: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date out of range: \(value) ms")
            }
            return TabulaJSON.date(fromMilliseconds: millis)
        }
        return decoder
    }

    /// Whole milliseconds since 1970 for `date`, rounded to the nearest millisecond, or `nil` when the result
    /// lies outside `millisecondsRange` (or `date` is not finite).
    public static func checkedMilliseconds(from date: Date) -> Int64? {
        checkedMilliseconds(fromDouble: date.timeIntervalSince1970 * 1000)
    }

    /// Whole milliseconds since 1970 for `date`, rounded to the nearest millisecond and **clamped** to
    /// `millisecondsRange` (a non-finite date gives the range's lower bound). Total: never traps.
    public static func milliseconds(from date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1000
        if let millis = checkedMilliseconds(fromDouble: value) { return millis }
        return value > 0 ? millisecondsRange.upperBound : millisecondsRange.lowerBound
    }

    /// The instant `millis` milliseconds after 1970-01-01T00:00:00Z.
    public static func date(fromMilliseconds millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    /// `value` rounded to whole milliseconds when finite and inside `millisecondsRange`. Both bounds are exact
    /// in `Double` (< 2^53), so the comparison happens before any integer conversion.
    static func checkedMilliseconds(fromDouble value: Double) -> Int64? {
        let rounded = value.rounded()
        guard rounded.isFinite, rounded >= Double(millisecondsRange.lowerBound),
              rounded <= Double(millisecondsRange.upperBound) else { return nil }
        return Int64(rounded)
    }
}
