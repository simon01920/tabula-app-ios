import Foundation
import Testing
@testable import TimetableCore

@Suite("Share transport: raw DEFLATE and base64url")
struct ShareDeflateBase64Tests {
    @Test func deflateRoundTripsRandomAndRepetitiveData() throws {
        var rng = TestRNG(seed: 3)
        for length in [0, 1, 2, 100, 4096, 16_383, 16_384, 16_385, 70_000] {
            let random = (0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            let repetitive = (0..<length).map { UInt8($0 % 7) }
            for input in [random, repetitive] {
                let compressed = try ShareDeflate.compress(input)
                #expect(try ShareDeflate.decompress(compressed, maxOutput: max(length, 1)) == input)
            }
        }
    }

    @Test func rawStreamHasNoZlibHeader() throws {
        let compressed = try ShareDeflate.compress(Array("hello hello hello".utf8))
        // A zlib stream would start with 0x78; raw DEFLATE starts with a block header.
        #expect(compressed.first != 0x78)
        #expect(throws: ShareError.decompressionFailed) { try ShareDeflate.decompress([0x78, 0x9C, 0x03, 0x00], maxOutput: 100) }
        #expect(throws: ShareError.decompressionFailed) { try ShareDeflate.decompress([], maxOutput: 100) }
    }

    @Test func outputCapIsExact() throws {
        let input = [UInt8](repeating: 0x41, count: 50_000)
        let compressed = try ShareDeflate.compress(input)
        #expect(try ShareDeflate.decompress(compressed, maxOutput: 50_000) == input)
        #expect(throws: ShareError.decompressedTooLarge) { try ShareDeflate.decompress(compressed, maxOutput: 49_999) }
    }

    @Test(arguments: [("", ""), ("f", "Zg"), ("fo", "Zm8"), ("foo", "Zm9v"), ("foob", "Zm9vYg"), ("fooba", "Zm9vYmE"),
                      ("foobar", "Zm9vYmFy")])
    func base64urlVectors(_ plain: String, _ encoded: String) {
        #expect(Base64URL.encode(Array(plain.utf8)) == encoded)
        #expect(Base64URL.decode(Array(encoded.utf8)) == Array(plain.utf8))
    }

    @Test func base64urlUsesTheURLAlphabetAndIsStrict() {
        #expect(Base64URL.encode([0xFB, 0xFF]) == "-_8")
        #expect(Base64URL.decode(Array("-_8".utf8)) == [0xFB, 0xFF])
        for bad in ["Zg==", "Zh", "Zm9", "+/8", "Zm 9v", "A", "Zm9vY", "Zm9v\n", "Zm9vÄ"] {
            #expect(Base64URL.decode(Array(bad.utf8)) == nil, "\(bad)")
        }
        var rng = TestRNG(seed: 4)
        for length in 0..<200 {
            let bytes = (0..<length).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            let text = Base64URL.encode(bytes)
            #expect(!text.contains("=") && !text.contains("+") && !text.contains("/"))
            #expect(Base64URL.decode(Array(text.utf8)) == bytes)
        }
    }

    @Test func textPolicySanitizer() {
        let cleaned = ShareText.sanitize("a\u{202E}b\u{0}c", limit: 100)
        #expect(cleaned.text == "abc" && cleaned.removedCharacters && !cleaned.shortened)
        let short = ShareText.sanitize("ab👩‍🔬", limit: 4)
        #expect(short.text == "ab" && short.shortened) // the 3-scalar emoji is not split
        #expect(ShareText.sanitize("x\r\ny", limit: 10, kind: .multiLine).text == "x\ny")
        #expect(ShareText.sanitize("x\ty", limit: 10).text == "x y")
        let plain = ShareText.sanitize("plain", limit: 10)
        #expect(plain.text == "plain" && !plain.removedCharacters && !plain.shortened)
    }
}
