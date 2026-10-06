/// Strict base64url (RFC 4648 §5) without padding.
///
/// Decoding accepts only the canonical encoding: the alphabet `A–Z a–z 0–9 - _`, no `=` padding, no
/// whitespace, a length that is not 1 mod 4, and zero bits in the unused low bits of the last character.
/// Encoding and decoding are therefore exact inverses (one byte string ↔ one text).
enum Base64URL {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// The 6-bit value of an alphabet byte, else `nil`.
    static func value(of byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return byte - UInt8(ascii: "A")
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return byte - UInt8(ascii: "a") + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0") + 52
        case UInt8(ascii: "-"): return 62
        case UInt8(ascii: "_"): return 63
        default: return nil
        }
    }

    /// Encodes `bytes` without padding.
    static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count * 4 + 2) / 3)
        var index = 0
        while index + 3 <= bytes.count {
            let n = UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2])
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)])
            out.append(alphabet[Int(n & 63)])
            index += 3
        }
        switch bytes.count - index {
        case 1:
            let n = UInt32(bytes[index]) << 16
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
        case 2:
            let n = UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8
            out.append(alphabet[Int(n >> 18 & 63)])
            out.append(alphabet[Int(n >> 12 & 63)])
            out.append(alphabet[Int(n >> 6 & 63)])
        default:
            break
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Decodes canonical unpadded base64url, or `nil` for anything else.
    static func decode<S: Collection>(_ text: S) -> [UInt8]? where S.Element == UInt8 {
        let count = text.count
        guard count % 4 != 1 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(count * 3 / 4)
        var accumulator: UInt32 = 0
        var bits = 0
        for byte in text {
            guard let value = value(of: byte) else { return nil }
            accumulator = accumulator << 6 | UInt32(value)
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(truncatingIfNeeded: accumulator >> UInt32(bits)))
                accumulator &= (1 << UInt32(bits)) - 1
            }
        }
        // Leftover bits (2 or 4) must be zero for the encoding to be canonical.
        guard accumulator == 0 else { return nil }
        return out
    }
}
