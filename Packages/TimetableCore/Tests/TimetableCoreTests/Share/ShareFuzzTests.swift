import Foundation
import Testing
@testable import TimetableCore

/// Seeded fuzzing of the decode pipeline. Every input must either decode to a valid payload — which then must
/// re-encode losslessly and import as an error-free database — or throw a typed `ShareError`. A crash (trap)
/// fails the whole test process.
@Suite("Share fuzz")
struct ShareFuzzTests {
    /// Tally of outcomes, to show the fuzzer reached every layer.
    struct Outcomes {
        var errors: [String: Int] = [:]
        var accepted = 0
        var total = 0

        mutating func run(_ envelope: String) throws {
            total += 1
            let payload: SharePayloadV1
            do {
                payload = try ShareCodec.decode(envelope)
            } catch {
                errors[Self.name(error), default: 0] += 1
                return
            }
            accepted += 1
            try checkAccepted(payload)
        }

        static func name(_ error: ShareError) -> String {
            String(error.description.prefix { $0 != "(" })
        }

        private func checkAccepted(_ payload: SharePayloadV1) throws {
            let reencoded = try ShareCodec.encode(payload)
            #expect(try ShareCodec.decode(reencoded.text) == payload)
            let (db, _) = try ShareFixture.importIntoEmptyDatabase(payload)
            let errors = db.validate().filter { $0.severity == .error }
            #expect(errors.isEmpty, "accepted payload imports with errors: \(errors.prefix(3))")
        }
    }

    static let baseJSON: [UInt8] = {
        let payload = try! ShareFixture.payload(ShareFixture.secondary(), ShareFixture.secondaryTimetableID, includeTasks: true)
        return try! ShareCodec.canonicalJSON(payload)
    }()

    @Test func randomTextAndBytes() throws {
        var rng = TestRNG(seed: 0xF022_0001)
        var outcomes = Outcomes()
        let alphabet = Array("0123456789.ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_=+/ ".utf8)
        for _ in 0..<400 {
            let length = Int(rng.next() % 300)
            let bytes = (0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }
            try outcomes.run(String(decoding: bytes, as: UTF8.self))
            try outcomes.run("1." + String(decoding: bytes.filter { Base64URL.value(of: $0) != nil }, as: UTF8.self))
        }
        for _ in 0..<200 { // random bytes as the compressed stream
            let bytes = (0..<Int(1 + rng.next() % 2000)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            try outcomes.run("1." + Base64URL.encode(bytes))
        }
        for _ in 0..<100 { // random bytes as the JSON
            let bytes = (0..<Int(rng.next() % 500)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            try outcomes.run(try ShareFixture.envelope(bytes: bytes))
        }
        print("SHARE-FUZZ random: \(outcomes.total) inputs, accepted \(outcomes.accepted), errors \(outcomes.errors.sorted { $0.key < $1.key })")
        #expect(outcomes.total == 1100)
        #expect(outcomes.accepted == 0)
    }

    @Test func truncationsAndBitFlips() throws {
        var rng = TestRNG(seed: 0xF022_0002)
        var outcomes = Outcomes()
        let compressed = try ShareDeflate.compress(Self.baseJSON)
        let envelope = Array(("1." + Base64URL.encode(compressed)).utf8)
        for _ in 0..<300 { // truncated envelopes
            let cut = Int(rng.next() % UInt64(envelope.count))
            try outcomes.run(String(decoding: envelope.prefix(cut), as: UTF8.self))
        }
        for _ in 0..<400 { // bit flips in the compressed stream
            var bytes = compressed
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                let index = Int(rng.next() % UInt64(bytes.count))
                bytes[index] ^= UInt8(1) << UInt8(rng.next() % 8)
            }
            try outcomes.run("1." + Base64URL.encode(bytes))
        }
        for _ in 0..<400 { // bit flips in the JSON (reach UTF-8, JSON and validation layers)
            var bytes = Self.baseJSON
            for _ in 0..<(1 + Int(rng.next() % 2)) {
                let index = Int(rng.next() % UInt64(bytes.count))
                bytes[index] ^= UInt8(1) << UInt8(rng.next() % 8)
            }
            try outcomes.run(try ShareFixture.envelope(bytes: bytes))
        }
        print("SHARE-FUZZ flips: \(outcomes.total) inputs, accepted \(outcomes.accepted), errors \(outcomes.errors.sorted { $0.key < $1.key })")
        #expect(outcomes.total == 1100)
        for layer in ["decompressionFailed", "invalidUTF8", "malformedPayload"] {
            #expect((outcomes.errors[layer] ?? 0) > 0, "fuzzing never reached \(layer)")
        }
    }

    @Test func structuralMutations() throws {
        var rng = TestRNG(seed: 0xF022_0003)
        var outcomes = Outcomes()
        let base = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: Data(Self.baseJSON))
        for _ in 0..<1000 {
            var value = base
            for _ in 0..<(1 + Int(rng.next() % 3)) { Self.mutate(&value, rng: &rng, depth: 0) }
            let bytes = try TabulaJSON.makeEncoder().encode(value)
            try outcomes.run(try ShareFixture.envelope(bytes: [UInt8](bytes)))
        }
        print("SHARE-FUZZ structural: \(outcomes.total) inputs, accepted \(outcomes.accepted), errors \(outcomes.errors.sorted { $0.key < $1.key })")
        #expect(outcomes.total == 1000)
        #expect(outcomes.accepted > 0) // harmless mutations (e.g. an unknown key) must still decode
        #expect(outcomes.errors.count >= 6, "too few distinct error kinds: \(outcomes.errors.keys.sorted())")
    }

    /// Replaces, deletes or duplicates a random node of the JSON tree with hostile values.
    static func mutate(_ value: inout JSONValue, rng: inout TestRNG, depth: Int) {
        let descend = depth < 6 && rng.next() % 4 != 0
        switch value {
        case .object(var members) where descend && !members.isEmpty:
            let keys = members.keys.sorted()
            let key = keys[Int(rng.next() % UInt64(keys.count))]
            switch rng.next() % 6 {
            case 0: members[key] = nil
            case 1: members["zz\(rng.next() % 10)"] = hostile(&rng)
            default: mutate(&members[key]!, rng: &rng, depth: depth + 1)
            }
            value = .object(members)
        case .array(var items) where descend && !items.isEmpty:
            let index = Int(rng.next() % UInt64(items.count))
            switch rng.next() % 5 {
            case 0: items.remove(at: index)
            case 1: items.append(items[index])
            default: mutate(&items[index], rng: &rng, depth: depth + 1)
            }
            value = .array(items)
        case .integer where rng.next() % 4 != 0:
            // Same-type tweaks get past the JSON shape check and exercise validation.
            value = .integer([0, 1, 2, 3, 5, 7, 9, 10, 40, 41, 99, 1439, 1440, 2001, -1, Int64.max][Int(rng.next() % 16)])
        case .string(let text) where rng.next() % 4 != 0:
            value = rng.next() % 2 == 0 ? hostile(&rng) : .string(String(text.reversed()))
        default:
            value = hostile(&rng)
        }
    }

    static func hostile(_ rng: inout TestRNG) -> JSONValue {
        let strings = ["", "x", "\u{0}", "\u{202E}evil", String(repeating: "A", count: 5000), "08:00", "23:59", "24:00",
                       "2026-02-29", "2028-02-29", "9999-12-31", "#FFFFFF", "#GGGGGG", "palette.classic.color.red", "lecture",
                       "zz-future", "w", "b", "f", "iso", "ref", "d", "strict", "compact", ShareFixture.scalar(0xFFFF), "👩‍🔬", "1.AAAA"]
        switch rng.next() % 9 {
        case 0: return .null
        case 1: return .bool(rng.next() % 2 == 0)
        case 2: return .integer([0, 1, 2, 7, -1, 1439, 1440, 2001, Int64.max, Int64.min][Int(rng.next() % 10)])
        case 3: return .double([0.5, -0.0, 1e300, 3.0][Int(rng.next() % 4)])
        case 4, 5: return .string(strings[Int(rng.next() % UInt64(strings.count))])
        case 6: return .array((0..<Int(rng.next() % 4)).map { _ in .integer(Int64(rng.next() % 10)) })
        case 7: return .object(["k": .string(["w", "d", "n", "b", "f", "iso", "ref"][Int(rng.next() % 7)]), "n": .integer(2)])
        default: return .array([])
        }
    }
}
