import Foundation

/// A small, strict UTF-8 JSON parser producing `JSONValue`, used by the sync layer to turn freshly encoded
/// entities into JSON trees.
///
/// Why: `JSONValue`'s `Decodable` init probes each value with `try?` decodes (null, Bool, Int64, Double,
/// String, array, object), which throws and discards several errors per object — about 10× slower, and the
/// stamper/merge convert every entity they touch. Number semantics match `JSONValue`'s decoder: a number
/// without fraction/exponent that fits `Int64` is `.integer`, everything else `.double`.
enum SyncJSONParser {
    struct ParseError: Error, CustomStringConvertible {
        let offset: Int
        let reason: String
        var description: String { "JSON parse error at byte \(offset): \(reason)" }
    }

    /// Compact JSON bytes of `value` for feeding a `JSONDecoder` (keys unsorted — not canonical; use
    /// `TabulaJSON` for anything persisted or compared).
    static func serialize(_ value: JSONValue) -> Data {
        var out: [UInt8] = []
        out.reserveCapacity(512)
        write(value, into: &out)
        return Data(out)
    }

    private static func write(_ value: JSONValue, into out: inout [UInt8]) {
        switch value {
        case .null: out += Array("null".utf8)
        case .bool(let flag): out += Array((flag ? "true" : "false").utf8)
        case .integer(let number): out += Array(String(number).utf8)
        case .double(let number): out += Array((number.isFinite ? "\(number)" : "null").utf8)
        case .string(let text): writeString(text, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (offset, item) in items.enumerated() {
                if offset > 0 { out.append(UInt8(ascii: ",")) }
                write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let members):
            out.append(UInt8(ascii: "{"))
            var first = true
            for (key, member) in members {
                if !first { out.append(UInt8(ascii: ",")) }
                first = false
                writeString(key, into: &out)
                out.append(UInt8(ascii: ":"))
                write(member, into: &out)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func writeString(_ text: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""): out += [UInt8(ascii: "\\"), UInt8(ascii: "\"")]
            case UInt8(ascii: "\\"): out += [UInt8(ascii: "\\"), UInt8(ascii: "\\")]
            case 0..<0x20:
                out += Array("\\u00".utf8)
                out.append(Array("0123456789abcdef".utf8)[Int(byte >> 4)])
                out.append(Array("0123456789abcdef".utf8)[Int(byte & 0x0F)])
            default: out.append(byte)
            }
        }
        out.append(UInt8(ascii: "\""))
    }

    static func parse(_ data: Data) throws -> JSONValue {
        try data.withUnsafeBytes { raw in
            var parser = Parser(bytes: raw.bindMemory(to: UInt8.self))
            parser.skipWhitespace()
            let value = try parser.value(depth: 0)
            parser.skipWhitespace()
            guard parser.index == parser.bytes.count else { throw parser.error("trailing characters") }
            return value
        }
    }

    private struct Parser {
        let bytes: UnsafeBufferPointer<UInt8>
        var index = 0
        static let maxDepth = 512

        init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        func error(_ reason: String) -> ParseError { ParseError(offset: index, reason: reason) }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < Self.maxDepth else { throw error("nesting too deep") }
            guard index < bytes.count else { throw error("unexpected end") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ text: StaticString) throws {
            let count = text.utf8CodeUnitCount
            guard index + count <= bytes.count else { throw error("unexpected end") }
            for offset in 0..<count where bytes[index + offset] != text.utf8Start[offset] {
                throw error("invalid literal")
            }
            index += count
        }

        mutating func object(depth: Int) throws -> JSONValue {
            index += 1
            var members: [String: JSONValue] = [:]
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("expected key") }
                let key = try string()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("expected ':'") }
                index += 1
                skipWhitespace()
                members[key] = try value(depth: depth + 1)
                skipWhitespace()
                guard index < bytes.count else { throw error("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw error("expected ',' or '}'")
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw error("unexpected end") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw error("expected ',' or ']'")
            }
        }

        mutating func string() throws -> String {
            index += 1                                   // opening quote
            var scalars = String.UnicodeScalarView()
            var runStart = index
            func flushRun(_ end: Int, into scalars: inout String.UnicodeScalarView) throws {
                guard end > runStart else { return }
                guard let text = String(validating: UnsafeBufferPointer(rebasing: bytes[runStart..<end]),
                                        as: UTF8.self) else { throw error("invalid UTF-8") }
                scalars.append(contentsOf: text.unicodeScalars)
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    try flushRun(index, into: &scalars)
                    index += 1
                    return String(scalars)
                }
                if byte == UInt8(ascii: "\\") {
                    try flushRun(index, into: &scalars)
                    index += 1
                    guard index < bytes.count else { throw error("unexpected end") }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): scalars.append("\"")
                    case UInt8(ascii: "\\"): scalars.append("\\")
                    case UInt8(ascii: "/"): scalars.append("/")
                    case UInt8(ascii: "b"): scalars.append("\u{08}")
                    case UInt8(ascii: "f"): scalars.append("\u{0C}")
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "u"):
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code) {
                            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                                  bytes[index + 1] == UInt8(ascii: "u") else { throw error("lone surrogate") }
                            index += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("invalid surrogate pair") }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let scalar = Unicode.Scalar(code) else { throw error("invalid code point") }
                        scalars.append(scalar)
                    default:
                        throw error("invalid escape")
                    }
                    runStart = index
                    continue
                }
                guard byte >= 0x20 else { throw error("control character in string") }
                index += 1
            }
            throw error("unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("unexpected end") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
                default: throw error("invalid \\u escape")
                }
                value = value << 4 | digit
                index += 1
            }
            return value
        }

        mutating func number() throws -> JSONValue {
            let start = index
            var isInteger = true
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            var digits = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                    digits += 1
                } else if byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")
                            || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") {
                    isInteger = false
                } else {
                    break
                }
                index += 1
            }
            guard digits > 0 else { throw error("invalid value") }
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
            if isInteger, let value = Int64(text) { return .integer(value) }
            guard let value = Double(text), value.isFinite else { throw error("invalid number") }
            return .double(value)
        }
    }
}
