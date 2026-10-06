import Foundation
import Testing
@testable import TimetableCore

@Suite("EntityID")
struct EntityIDTests {
    @Test func codesAsPlainUUIDString() throws {
        let id = Lesson.ID(uuidString: "0000ABCD-0000-4000-8000-000000000001")!
        #expect(try Fixture.json(id) == "\"0000ABCD-0000-4000-8000-000000000001\"")
        #expect(try Fixture.decode(Lesson.ID.self, "\"0000abcd-0000-4000-8000-000000000001\"") == id)
        #expect(throws: DecodingError.self) { try Fixture.decode(Lesson.ID.self, "\"not-a-uuid\"") }
        #expect(Lesson.ID(uuidString: "nope") == nil)
        #expect(id.description == id.uuidString)
        #expect(id.retyped(as: Subject.self).uuid == id.uuid)
    }

    @Test func orderingIsUUIDByteOrder() {
        var rng = TestRNG(seed: 7)
        let ids = (0..<200).map { _ in
            Lesson.ID(UUID(uuid: (UInt8.random(in: 0...255, using: &rng), UInt8.random(in: 0...255, using: &rng),
                                  UInt8.random(in: 0...255, using: &rng), 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0,
                                  UInt8.random(in: 0...255, using: &rng))))
        }
        let sorted = ids.sorted()
        func bytes(_ id: Lesson.ID) -> [UInt8] { withUnsafeBytes(of: id.uuid.uuid) { Array($0) } }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            #expect(bytes(a).lexicographicallyPrecedes(bytes(b)) || bytes(a) == bytes(b))
        }
    }
}

@Suite("HLCTimestamp")
struct HLCTimestampTests {
    @Test func fixedWidthStringForm() throws {
        let ts = HLCTimestamp(physicalMillis: 1_791_273_600_000, logical: 3, node: 0xCAFE_BABE)
        #expect(ts.stringValue == "001791273600000-0000000003-00000000cafebabe")
        #expect(ts.stringValue.count == HLCTimestamp.stringLength)
        #expect(HLCTimestamp(ts.stringValue) == ts)
        #expect(try Fixture.json(ts) == "\"001791273600000-0000000003-00000000cafebabe\"")
        #expect(try Fixture.roundTrip(ts) == ts)
        let max = HLCTimestamp(physicalMillis: HLCTimestamp.maxPhysicalMillis, logical: .max, node: .max)
        #expect(max.stringValue == "999999999999999-4294967295-ffffffffffffffff")
        #expect(HLCTimestamp(max.stringValue) == max)
        #expect(HLCTimestamp.zero.stringValue == "000000000000000-0000000000-0000000000000000")
    }

    @Test func rejectsMalformedStrings() throws {
        for bad in ["001791273600000-0000000003-00000000CAFEBABE",   // uppercase hex
                    "001791273600000-0000000003-cafebabe",           // short node
                    "001791273600000_0000000003-00000000cafebabe",   // separator
                    "001791273600000-4294967296-00000000cafebabe",   // logical > UInt32.max
                    "00179127360000a-0000000003-00000000cafebabe",   // non-digit
                    ""] {
            #expect(HLCTimestamp(bad) == nil, "\(bad)")
        }
        #expect(throws: DecodingError.self) { try Fixture.decode(HLCTimestamp.self, "\"garbage\"") }
    }

    /// Property: string order equals timestamp order (and string equality equals equality).
    @Test func stringOrderEqualsTimeOrder() {
        var rng = TestRNG(seed: 2026)
        func random() -> HLCTimestamp {
            // Mix of nearby and far-apart values, including digit-count boundaries.
            let physical: Int64
            switch UInt8.random(in: 0...3, using: &rng) {
            case 0: physical = Int64.random(in: 0...HLCTimestamp.maxPhysicalMillis, using: &rng)
            case 1: physical = [999, 1000, 9_999, 10_000, 999_999_999_999, 1_000_000_000_000].randomElement(using: &rng)!
            default: physical = 1_791_273_600_000 + Int64.random(in: 0...3, using: &rng)
            }
            let logical = Bool.random(using: &rng) ? UInt32.random(in: 0...3, using: &rng) : UInt32.random(in: 0...UInt32.max, using: &rng)
            let node = Bool.random(using: &rng) ? UInt64.random(in: 0...3, using: &rng) : UInt64.random(in: 0...UInt64.max, using: &rng)
            return HLCTimestamp(physicalMillis: physical, logical: logical, node: node)
        }
        var budget = FailureBudget()
        for _ in 0..<5_000 {
            let a = random(), b = random()
            if (a < b) != (a.stringValue < b.stringValue) { budget.record("order mismatch \(a) vs \(b)") }
            if (a == b) != (a.stringValue == b.stringValue) { budget.record("equality mismatch \(a) vs \(b)") }
        }
        #expect(budget.count == 0)
    }

    @Test func tieBreakIsNode() {
        let a = HLCTimestamp(physicalMillis: 5, logical: 1, node: 1)
        let b = HLCTimestamp(physicalMillis: 5, logical: 1, node: 2)
        let c = HLCTimestamp(physicalMillis: 5, logical: 2, node: 0)
        #expect(a < b && b < c)
    }
}

@Suite("EntityMeta / SyncEntity")
struct EntityMetaTests {
    @Test func defaultsAndFieldClocks() throws {
        let t0 = HLCTimestamp(physicalMillis: 10, logical: 0, node: 1)
        let t1 = HLCTimestamp(physicalMillis: 20, logical: 0, node: 1)
        var meta = EntityMeta.created(at: t0)
        #expect(meta.createdAt == t0 && meta.updatedAt == t0 && !meta.isDeleted && meta.fieldClocks.isEmpty)
        meta.updatedAt = t1
        meta.fieldClocks["name"] = t1
        #expect(meta.clock(for: "name") == t1)
        #expect(meta.clock(for: "room") == t1)   // absent → updatedAt
        #expect(try Fixture.json(meta) == #"{"createdAt":"000000000000010-0000000000-0000000000000001","fieldClocks":{"name":"000000000000020-0000000000-0000000000000001"},"isDeleted":false,"updatedAt":"000000000000020-0000000000-0000000000000001"}"#)
        #expect(try Fixture.roundTrip(meta) == meta)
    }

    @Test func entityTypesAndSingletonSettings() {
        #expect(Timetable.entityType == .timetable && TaskItem.entityType == .task && AppSettings.entityType == .settings)
        #expect(EntityType.allCases.count == 11)
        #expect(EntityType.calendarBreak.l10nKey == "entityType.calendarBreak")
        #expect(AppSettings(meta: Fixture.meta()).id == AppSettings.singletonID)
        var deleted = Fixture.fullDatabase().lessons[0]
        #expect(!deleted.isDeleted)
        deleted.meta.isDeleted = true
        #expect(deleted.isDeleted)
    }
}
