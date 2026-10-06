import Foundation
import Testing
@testable import TimetableCore

@Suite("JSONValue")
struct JSONValueTests {
    @Test func decodesEveryKindWithoutConfusingBoolsAndNumbers() throws {
        #expect(try Fixture.decode(JSONValue.self, "null") == .null)
        #expect(try Fixture.decode(JSONValue.self, "true") == .bool(true))
        #expect(try Fixture.decode(JSONValue.self, "false") == .bool(false))
        #expect(try Fixture.decode(JSONValue.self, "1") == .integer(1))
        #expect(try Fixture.decode(JSONValue.self, "0") == .integer(0))
        #expect(try Fixture.decode(JSONValue.self, "-42") == .integer(-42))
        #expect(try Fixture.decode(JSONValue.self, "1.5") == .double(1.5))
        #expect(try Fixture.decode(JSONValue.self, "9007199254740993") == .integer(9_007_199_254_740_993))
        #expect(try Fixture.decode(JSONValue.self, "\"x\"") == .string("x"))
        #expect(try Fixture.decode(JSONValue.self, "[1,\"a\",null]") == .array([.integer(1), .string("a"), .null]))
        #expect(try Fixture.decode(JSONValue.self, #"{"b":{"c":[]},"a":true}"#)
                == .object(["a": .bool(true), "b": .object(["c": .array([])])]))
    }

    @Test func encodesCanonically() throws {
        let value = JSONValue.object(["z": .integer(1), "a": .array([.double(0.25), .bool(false), .null]), "m": .string("é/ü")])
        #expect(try Fixture.json(value) == #"{"a":[0.25,false,null],"m":"é/ü","z":1}"#)
        #expect(try Fixture.roundTrip(value) == value)
    }

    @Test func bridgesTypedValues() throws {
        let range = LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2026-09-30"))
        let tree = try JSONValue(encoding: range)
        #expect(tree == .object(["start": .string("2026-09-01"), "end": .string("2026-09-30")]))
        #expect(tree["start"]?.stringValue == "2026-09-01")
        #expect(tree["missing"] == nil)
        #expect(JSONValue.string("x")["a"] == nil)
        #expect(try tree.decoded(as: LocalDateRange.self) == range)
    }
}

@Suite("TabulaJSON")
struct TabulaJSONTests {
    private struct Sample: Codable, Equatable {
        var b: Date
        var a: String
    }

    @Test func sortedKeysUnescapedSlashesIntegerMillis() throws {
        let sample = Sample(b: Date(timeIntervalSince1970: 1_759_742_400.123), a: "https://x/y")
        #expect(try Fixture.json(sample) == #"{"a":"https://x/y","b":1759742400123}"#)
        let pretty = String(decoding: try TabulaJSON.makeEncoder(pretty: true).encode(sample), as: UTF8.self)
        #expect(pretty.contains("\n"))
    }

    @Test func dateDecodingAcceptsFractionalMillisAndRounds() throws {
        let decoded = try Fixture.decode(Sample.self, #"{"a":"","b":1759742400123.6}"#)
        #expect(TabulaJSON.milliseconds(from: decoded.b) == 1_759_742_400_124)
        #expect(try Fixture.json(decoded) == #"{"a":"","b":1759742400124}"#)
    }

    /// Property: integer milliseconds survive decode → encode unchanged (no floating-point drift).
    @Test func millisecondRoundTripIsStable() throws {
        var rng = TestRNG(seed: 42)
        var budget = FailureBudget()
        for _ in 0..<2_000 {
            let millis = Int64.random(in: -2_000_000_000_000...32_503_680_000_000, using: &rng)   // ≈ 1906…3000
            let date = TabulaJSON.date(fromMilliseconds: millis)
            if TabulaJSON.milliseconds(from: date) != millis { budget.record("millis \(millis) drifted") }
            let json = "{\"a\":\"\",\"b\":\(millis)}"
            let reencoded = try Fixture.json(Fixture.decode(Sample.self, json))
            if reencoded != json { budget.record("\(json) → \(reencoded)") }
        }
        #expect(budget.count == 0)
    }
}

@Suite("IDGenerator")
struct IDGeneratorTests {
    @Test func sequentialIsDeterministicAndFormatted() {
        var a = SequentialIDGenerator()
        var b = SequentialIDGenerator()
        #expect(a.nextUUID().uuidString == "00000000-0000-4000-8000-000000000001")
        #expect(a.nextUUID().uuidString == "00000000-0000-4000-8000-000000000002")
        #expect(b.nextUUID().uuidString == "00000000-0000-4000-8000-000000000001")
        var namespaced = SequentialIDGenerator(namespace: 0xABCD, start: 0xFFFF)
        #expect(namespaced.nextUUID().uuidString == "0000ABCD-0000-4000-8000-00000000FFFF")
        #expect(namespaced.counter == 0x10000)
        var last = SequentialIDGenerator(start: SequentialIDGenerator.maxCounter)
        #expect(last.nextUUID().uuidString == "00000000-0000-4000-8000-FFFFFFFFFFFF")
    }

    @Test func typedIDsAndNamespacesDoNotCollide() {
        var a = SequentialIDGenerator(namespace: 1)
        var b = SequentialIDGenerator(namespace: 2)
        let lessonID: Lesson.ID = a.next()
        let subjectID = a.next(Subject.self)
        #expect(lessonID.uuid != subjectID.uuid)
        let first = Set((0..<100).map { _ in a.nextUUID() })
        let second = Set((0..<100).map { _ in b.nextUUID() })
        #expect(first.count == 100 && first.isDisjoint(with: second))
    }

    @Test func systemGeneratorProducesDistinctV4UUIDs() {
        var generator = SystemIDGenerator()
        let ids = (0..<1_000).map { _ in generator.nextUUID() }
        #expect(Set(ids).count == 1_000)
        #expect(ids.allSatisfy { Array($0.uuidString)[14] == "4" })
    }
}

@Suite("LocalizedText / TextValue")
struct LocalizedTextTests {
    @Test func jsonShapeAndRoundTrip() throws {
        let text = LocalizedText(key: "validation.danglingReference", args: [
            .text(LocalizedText(key: "entityType.lesson")), .string("subjectID"), .integer(3),
            .date(Fixture.date("2026-10-06")), .time(Fixture.time("08:00")),
        ])
        #expect(try Fixture.roundTrip(text) == text)
        #expect(try Fixture.json(LocalizedText(key: "k", args: [.integer(2)])) == #"{"args":[{"kind":"integer","value":2}],"key":"k"}"#)
        #expect(text.description.hasPrefix("validation.danglingReference(entityType.lesson, \"subjectID\", 3"))
    }

    @Test func textValueShape() throws {
        #expect(try Fixture.json(TextValue.key("palette.classic.color.red")) == #"{"kind":"key","value":"palette.classic.color.red"}"#)
        #expect(try Fixture.json(TextValue.literal("Brick")) == #"{"kind":"literal","value":"Brick"}"#)
        #expect(try Fixture.roundTrip(TextValue.literal("Brick")) == .literal("Brick"))
        #expect(throws: DecodingError.self) { try Fixture.decode(TextValue.self, #"{"kind":"emoji","value":"x"}"#) }
    }
}

@Suite("Open vocabularies")
struct OpenVocabularyTests {
    @Test func unknownValuesRoundTrip() throws {
        let type = try Fixture.decode(LessonType.self, "\"colloquium\"")
        #expect(!type.isKnown && type.rawValue == "colloquium")
        #expect(try Fixture.json(type) == "\"colloquium\"")
        #expect(LessonType.lecture.isKnown)
        #expect(try Fixture.decode([PeriodKind].self, #"["break","assembly"]"#) == [.breakTime, PeriodKind(rawValue: "assembly")])
    }

    @Test func knownValuesAreUniquePerVocabulary() {
        func unique<V: OpenVocabulary>(_: V.Type) -> Bool { Set(V.knownValues).count == V.knownValues.count && !V.knownValues.isEmpty }
        #expect(unique(LessonType.self) && unique(LessonField.self) && unique(TimetableViewKind.self))
        #expect(unique(PeriodKind.self) && unique(BreakKind.self) && unique(TaskKind.self) && unique(ExamKind.self))
        #expect(unique(AttachmentKind.self) && unique(ReminderTarget.self) && unique(RepeatFrequency.self))
        #expect(unique(PalettePackID.self))
        #expect(PeriodKind.breakTime.rawValue == "break")
        #expect(ExamKind.final.rawValue == "final")
    }

    @Test func orderingIsByRawValue() {
        #expect([LessonField.teacher, .room, .bringList].sorted() == [.bringList, .room, .teacher])
        #expect(TaskPriority.low < .normal && TaskPriority.high < .urgent)
        #expect(DeliveryTier.standard < .timeSensitive && DeliveryTier.timeSensitive < .alarm)
    }
}
