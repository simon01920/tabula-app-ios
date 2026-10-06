import Foundation

/// SHA-256 (FIPS 180-4) in pure Swift, used for the backup-archive checksum.
///
/// Why own code: Foundation has no hash API on Linux (CryptoKit is Apple-only; swift-crypto would be a
/// package dependency, which `TimetableCore` must not have). ~80 lines, tested against the FIPS 180-4 /
/// NIST example vectors. Integrity check only — not used for anything security-sensitive.
/// (Named `TabulaSHA256` so it never clashes with CryptoKit's `SHA256` in app targets.)
public enum TabulaSHA256 {
    /// The 32-byte digest of `data`.
    public static func digest(_ data: Data) -> [UInt8] {
        var state: [UInt32] = [0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
                               0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19]
        var schedule = [UInt32](repeating: 0, count: 64)
        let fullBlocks = data.count / 64
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for block in 0..<fullBlocks {
                compress(UnsafeRawBufferPointer(rebasing: raw[(block * 64)..<(block * 64 + 64)]),
                         state: &state, schedule: &schedule)
            }
        }
        // Padding: 0x80, zeros, 64-bit big-endian bit length.
        var tail = [UInt8](data.suffix(from: data.startIndex + fullBlocks * 64))
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        let bitLength = UInt64(data.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        tail.withUnsafeBytes { raw in
            for block in 0..<(raw.count / 64) {
                compress(UnsafeRawBufferPointer(rebasing: raw[(block * 64)..<(block * 64 + 64)]),
                         state: &state, schedule: &schedule)
            }
        }
        var digest: [UInt8] = []
        digest.reserveCapacity(32)
        for word in state {
            digest += [UInt8(truncatingIfNeeded: word >> 24), UInt8(truncatingIfNeeded: word >> 16),
                       UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)]
        }
        return digest
    }

    /// The digest as 64 lowercase hex digits.
    public static func hexDigest(_ data: Data) -> String {
        digest(data).map { PaddedNumber.hex(UInt64($0), width: 2, uppercase: false) }.joined()
    }

    private static let roundConstants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private static func compress(_ block: UnsafeRawBufferPointer, state: inout [UInt32], schedule w: inout [UInt32]) {
        for t in 0..<16 {
            let i = t * 4
            w[t] = UInt32(block[i]) << 24 | UInt32(block[i + 1]) << 16 | UInt32(block[i + 2]) << 8 | UInt32(block[i + 3])
        }
        for t in 16..<64 {
            let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
            let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
            w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for t in 0..<64 {
            let bigSigma1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let choose = (e & f) ^ (~e & g)
            let temp1 = h &+ bigSigma1 &+ choose &+ roundConstants[t] &+ w[t]
            let bigSigma0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = bigSigma0 &+ majority
            h = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }
        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }
}
