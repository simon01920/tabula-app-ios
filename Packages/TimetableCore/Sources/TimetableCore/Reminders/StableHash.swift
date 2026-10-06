import Foundation

/// Platform-independent, process-independent hashing for reminder identifiers.
///
/// Swift's `Hasher` is randomly seeded per process, so it can never be used for identifiers that must
/// survive an app restart. FNV-1a (64-bit) over the UTF-8 bytes is tiny, fast and identical everywhere.
/// It is **not** cryptographic; it only has to make accidental collisions negligible (64 bits: for a plan of
/// 10 000 candidates the birthday bound is about 3 × 10⁻¹²).
enum StableHash {
    /// FNV-1a 64-bit offset basis.
    static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    /// FNV-1a 64-bit prime.
    static let prime: UInt64 = 0x0000_0100_0000_01B3

    /// FNV-1a 64 of the UTF-8 bytes of `string`.
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    /// 16 lowercase hex digits, zero-padded.
    static func hex(_ value: UInt64) -> String {
        PaddedNumber.hex(value, width: 16, uppercase: false)
    }

    /// A deterministic RFC 9562 version-8 ("custom") UUID derived from `string`.
    ///
    /// The 128 bits are two FNV-1a 64 hashes (of `string` and of `string` + a fixed suffix) with the
    /// version and variant bits overwritten. Used for AlarmKit, whose `Alarm.ID` is a `UUID`.
    static func uuid(_ string: String) -> UUID {
        let high = fnv1a64(string)
        let low = fnv1a64(string + "\u{1F}uuid")
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * UInt64(index)))
            bytes[8 + index] = UInt8(truncatingIfNeeded: low >> (56 - 8 * UInt64(index)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x80 // version 8
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122/9562 variant (10xx)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
