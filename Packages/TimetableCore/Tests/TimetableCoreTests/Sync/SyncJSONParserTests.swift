import Foundation
import Testing
@testable import TimetableCore

@Suite("SyncJSONParser")
struct SyncJSONParserTests {
    /// The fast parser agrees with `JSONValue`'s `Decodable` init on real encoder output.
    @Test func agreesWithJSONValueDecoding() throws {
        var db = Fixture.fullDatabase()
        db.tasks[0].notes = "Quote \" backslash \\ newline \n tab \t emoji 😀 control \u{01} slash /"
        db.unknownFields.root["numbers"] = .array([.integer(.max), .integer(.min), .double(1.5), .double(-2.25e-7),
                                                   .bool(true), .bool(false), .null, .object([:]), .array([])])
        let data = try db.encoded(pretty: true)
        let reference = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: data)
        #expect(try SyncJSONParser.parse(data) == reference)
        #expect(try SyncJSONParser.parse(db.encoded()) == reference)
        // Serialising and decoding again round-trips the tree.
        #expect(try TabulaJSON.makeDecoder().decode(JSONValue.self, from: SyncJSONParser.serialize(reference)) == reference)
        #expect(try SyncJSONParser.parse(Data(#""\ud83d\ude00\u00e9""#.utf8)) == .string("😀é"))
    }

    @Test func rejectsMalformedInput() {
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "tru", "\"unterminated", "1 2", "{\"a\":1,}", "\"\\x\"",
                    "\"\\ud800\"", "-", "nan", "\"\u{01}\""] {
            #expect(throws: SyncJSONParser.ParseError.self, "\(bad)") { try SyncJSONParser.parse(Data(bad.utf8)) }
        }
        let deep = String(repeating: "[", count: 600) + String(repeating: "]", count: 600)
        #expect(throws: SyncJSONParser.ParseError.self) { try SyncJSONParser.parse(Data(deep.utf8)) }
    }
}
