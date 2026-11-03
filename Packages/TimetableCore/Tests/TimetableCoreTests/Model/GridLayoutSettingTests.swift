import Foundation
import Testing
@testable import TimetableCore

/// Human decision 2026-11-02: `AppSettings.gridLayout` (optional, open vocabulary). Stores and backups written before
/// it existed load with the default (days as rows); the value round-trips, merges field by field and survives an
/// older build that does not know the key.
@Suite("AppSettings.gridLayout")
struct GridLayoutSettingTests {
    @Test func oldStoresDecodeWithTheDefault() throws {
        let db = Fixture.fullDatabase()
        #expect(db.settings.gridLayout == nil)
        let bytes = try TabulaJSON.makeEncoder().encode(db)
        // Unset, the key is not written: files of older and newer builds stay byte-identical.
        #expect(!String(decoding: bytes, as: UTF8.self).contains("gridLayout"))
        let decoded = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: bytes)
        #expect(decoded.settings.gridLayout == nil)
        #expect(decoded.settings.effectiveGridLayout == .daysAsRows)
        #expect(AppSettings.untouchedDefaults.effectiveGridLayout == .daysAsRows)
    }

    @Test func choiceRoundTrips() throws {
        var db = Fixture.fullDatabase()
        db.settings.gridLayout = .periodsAsRows
        let bytes = try TabulaJSON.makeEncoder().encode(db)
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""gridLayout":"periodsAsRows""#))
        let decoded = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: bytes)
        #expect(decoded.settings.effectiveGridLayout == .periodsAsRows)
        #expect(try TabulaJSON.makeEncoder().encode(decoded) == bytes)
        #expect(!db.validate().contains { $0.field == "gridLayout" })
    }

    @Test func unknownValueIsKeptAndDrawnAsTheDefault() throws {
        var db = Fixture.fullDatabase()
        db.settings.gridLayout = GridLayoutStyle(rawValue: "spiral")
        let bytes = try TabulaJSON.makeEncoder().encode(db)
        let decoded = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: bytes)
        #expect(decoded.settings.gridLayout?.rawValue == "spiral")
        #expect(decoded.settings.effectiveGridLayout == .daysAsRows)
        let issue = db.validate().first { $0.code == .unknownValue && $0.field == "gridLayout" }
        #expect(issue?.severity == .info && issue?.value == "spiral")
    }

    /// An older build (no `gridLayout` in its catalog) treats the key like any newer settings key: kept in
    /// `unknownFields` and written back. Simulated with a key this build does not know either.
    @Test func olderBuildsKeepTheKeyInARoundTrip() throws {
        var db = Fixture.fullDatabase()
        db.settings.gridLayout = .periodsAsRows
        var object = try SyncJSONParser.parse(TabulaJSON.makeEncoder().encode(db))
        guard case .object(var root) = object, case .object(var settings)? = root["settings"] else {
            Issue.record("no settings object")
            return
        }
        settings["gridLayoutNext"] = settings["gridLayout"]   // what an older build sees: a key it does not know
        root["settings"] = .object(settings)
        object = .object(root)
        let older = try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: TabulaJSON.makeEncoder().encode(object))
        #expect(older.unknownFields.fields(of: older.settings)?.fields["gridLayoutNext"] == .string("periodsAsRows"))
        let resaved = String(decoding: try TabulaJSON.makeEncoder().encode(older), as: UTF8.self)
        #expect(resaved.contains(#""gridLayoutNext":"periodsAsRows""#))
        #expect(EntityFieldCatalog.fieldKeys(for: .settings).contains("gridLayout"))
    }

    @Test func choiceIsStampedAndMergesFieldByField() throws {
        var a = HybridLogicalClock(node: 1), b = HybridLogicalClock(node: 2)
        let draft = AppSettings(meta: Fixture.meta())
        let onA = try MutationStamper.stamp(old: nil, new: draft, clock: &a, now: SyncFixture.at(0))
        let onB = try MutationStamper.stamp(old: nil, new: draft, clock: &b, now: SyncFixture.at(10))
        var editedA = onA
        editedA.gridLayout = .periodsAsRows
        editedA = try MutationStamper.stamp(old: onA, new: editedA, clock: &a, now: SyncFixture.at(20))
        #expect(editedA.meta.clock(for: "gridLayout") == editedA.meta.updatedAt)
        var editedB = onB
        editedB.appearance = .dark
        editedB = try MutationStamper.stamp(old: onB, new: editedB, clock: &b, now: SyncFixture.at(30))
        let merged = try SyncMerge.merge(local: TabulaDatabase(settings: editedB), remote: TabulaDatabase(settings: editedA))
        #expect(merged.settings.gridLayout == .periodsAsRows && merged.settings.appearance == .dark)
    }
}
