import Foundation

/// The single place that configures JSON coding for everything Tabula persists or exchanges.
///
/// - Keys are sorted, slashes are not escaped, so equal values always produce identical bytes.
/// - `Date` is encoded as an **integer** number of milliseconds since 1970-01-01T00:00:00Z
///   (rounded to the nearest millisecond). Integers make decode → encode byte-stable; a floating
///   `millisecondsSince1970` value can drift by one ULP on every round trip.
/// - Decoding accepts integer or fractional millisecond numbers.
public enum TabulaJSON {
    /// Creates the canonical encoder. `pretty` adds indentation for tests and human-readable backups.
    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TabulaJSON.milliseconds(from: date))
        }
        return encoder
    }

    /// Creates the canonical decoder (dates as milliseconds since 1970).
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let millis = try? container.decode(Int64.self) {
                return TabulaJSON.date(fromMilliseconds: millis)
            }
            let value = try container.decode(Double.self)
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Non-finite date")
            }
            return TabulaJSON.date(fromMilliseconds: Int64(value.rounded()))
        }
        return decoder
    }

    /// Whole milliseconds since 1970 for `date`, rounded to the nearest millisecond.
    public static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The instant `millis` milliseconds after 1970-01-01T00:00:00Z.
    public static func date(fromMilliseconds millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }
}
