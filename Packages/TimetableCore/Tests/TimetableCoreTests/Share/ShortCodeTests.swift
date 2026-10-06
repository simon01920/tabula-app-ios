import Foundation
import Testing
@testable import TimetableCore

@Suite("ShortCode")
struct ShortCodeTests {
    @Test func alphabetExcludesAmbiguousCharacters() {
        let alphabet = Array(ShortCode.alphabet)
        #expect(alphabet.count == 31)
        #expect(Set(alphabet).count == 31)
        #expect(alphabet == alphabet.sorted())
        for excluded in "0O1IL" { #expect(!alphabet.contains(excluded)) }
        #expect(alphabet.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) })
    }

    @Test func randomCodesAreCanonicalAndDeterministic() {
        var a = TestRNG(seed: 2026), b = TestRNG(seed: 2026)
        for _ in 0..<1000 {
            let code = ShortCode.random(using: &a)
            #expect(code == ShortCode.random(using: &b))
            #expect(ShortCode(code.rawValue) == code)
            #expect(code.rawValue.count == 8)
        }
        // Golden values pin the algorithm (rejection sampling on 64-bit draws, own code, not stdlib's).
        var rng = TestRNG(seed: 1)
        let golden = (0..<3).map { _ in ShortCode.random(using: &rng).rawValue }
        var check = TestRNG(seed: 1)
        let alphabet = Array(ShortCode.alphabet)
        let manual = (0..<3).map { _ in String((0..<8).map { _ in alphabet[Int(check.next() % 31)] }) }
        #expect(golden == manual) // with this seed no draw hits the (≈ 9 × 10⁻¹⁹) rejection band
    }

    @Test func distributionIsUniform() {
        var rng = TestRNG(seed: 0x5EED)
        let codes = 20_000
        var counts: [Character: Int] = [:]
        var positional = Array(repeating: [Character: Int](), count: 8)
        var seen = Set<ShortCode>()
        for _ in 0..<codes {
            let code = ShortCode.random(using: &rng)
            seen.insert(code)
            for (index, character) in code.rawValue.enumerated() {
                counts[character, default: 0] += 1
                positional[index][character, default: 0] += 1
            }
        }
        #expect(seen.count == codes) // 20 000 codes out of 8.5 × 10¹¹: a collision would point at a broken generator
        #expect(counts.count == 31)
        let total = Double(codes * 8), expected = total / 31
        let sigma = (total * (1.0 / 31) * (30.0 / 31)).squareRoot()
        for (character, count) in counts {
            #expect(abs(Double(count) - expected) < 5 * sigma, "\(character): \(count) vs \(expected)")
        }
        // Chi-square with 30 degrees of freedom: 99.9th percentile ≈ 59.7.
        let chiSquare = counts.values.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
        #expect(chiSquare < 59.7, "chi² = \(chiSquare)")
        for position in positional {
            let expectedPerPosition = Double(codes) / 31
            let chi = position.values.reduce(0.0) { $0 + pow(Double($1) - expectedPerPosition, 2) / expectedPerPosition }
            #expect(position.count == 31 && chi < 59.7, "positional chi² = \(chi)")
        }
    }

    /// A generator that first returns values in the rejection band, then fixed values.
    struct ScriptedRNG: RandomNumberGenerator {
        var values: [UInt64]
        var calls = 0
        mutating func next() -> UInt64 {
            defer { calls += 1 }
            return values[calls % values.count]
        }
    }

    @Test func rejectionSamplingDiscardsBiasedDraws() {
        // The largest multiple of 31 below 2⁶⁴ is 2⁶⁴ − 16, so the 16 draws ≥ UInt64.max − 15 are rejected.
        var rng = ScriptedRNG(values: [UInt64.max, UInt64.max - 15, UInt64.max - 16, 0, 30, 31, 61, 62, 93, 1])
        let code = ShortCode.random(using: &rng)
        let alphabet = Array(ShortCode.alphabet)
        let expected = [UInt64.max - 16, 0, 30, 31, 61, 62, 93, 1].map { alphabet[Int($0 % 31)] }
        #expect(code.rawValue == String(expected))
        #expect(rng.calls == 10)
    }

    @Test(arguments: [
        ("ABCDEFGH", "ABCDEFGH"), ("abcdefgh", "ABCDEFGH"), ("abcd-efgh", "ABCDEFGH"), (" ab cd ef gh ", "ABCDEFGH"),
        ("ABCD–EFGH", "ABCDEFGH"), ("ABCD‐EFGH", "ABCDEFGH"), ("AB\tCD\nEF GH", "ABCDEFGH"), ("2345-6789", "23456789"),
        ("zyxw-vuts", "ZYXWVUTS"), ("\u{00A0}7KX2M9QH\u{3000}", "7KX2M9QH"), ("7kx2-m9qh", "7KX2M9QH"),
    ])
    func normalizeAccepts(_ input: String, _ expected: String) throws {
        #expect(ShortCode.normalize(input)?.rawValue == expected)
        #expect(try ShortCode.parse(input).rawValue == expected)
    }

    @Test(arguments: [
        "", "ABCDEFG", "ABCDEFGHJ", "ABCDEFG0", "ABCDEFGO", "ABCDEFG1", "ABCDEFGI", "ABCDEFGL", "abcdefgl", "ABCD_EFG",
        "ÀBCDEFGH", "ＡＢＣＤＥＦＧＨ", "ABCDEFGß", "ABCDEFG\u{0}", "ABCD.EFGH", "ABCD/EFGH", "ABC😀EFGH",
        String(repeating: " ", count: 100) + "ABCDEFGH",
    ])
    func normalizeRejects(_ input: String) {
        #expect(ShortCode.normalize(input) == nil)
        #expect(throws: ShareError.invalidShortCode) { try ShortCode.parse(input) }
    }

    @Test func strictInitAndFormatting() throws {
        #expect(ShortCode("abcdefgh") == nil) // lowercase is not canonical
        #expect(ShortCode("ABCD-EFGH") == nil)
        let code = try #require(ShortCode("7KX2M9QH"))
        #expect(code.formatted == "7KX2-M9QH")
        #expect(ShortCode.normalize(code.formatted) == code)
        #expect(try Fixture.roundTrip(code) == code)
        #expect(try Fixture.json(code) == "\"7KX2M9QH\"")
        #expect(throws: DecodingError.self) { try Fixture.decode(ShortCode.self, "\"7kx2m9qh\"") }
    }
}
