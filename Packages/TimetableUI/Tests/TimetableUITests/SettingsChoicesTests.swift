import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Settings choices")
struct SettingsChoicesTests {
    @Test func weekStartRoundTrips() {
        #expect(WeekStartChoice(nil) == .system)
        #expect(WeekStartChoice(.sunday).override == .sunday)
        #expect(WeekStartChoice.system.override == nil)
        #expect(WeekStartChoice.options(including: nil) == [.system, .weekday(.monday), .weekday(.sunday), .weekday(.saturday)])
        #expect(WeekStartChoice.options(including: .tuesday).last == .weekday(.tuesday))
        #expect(WeekStartChoice.options(including: .sunday).count == 4)
    }

    @Test func hourCycleMapsAndDegrades() {
        #expect(HourCycleChoice(.auto) == .system)
        #expect(HourCycleChoice(HourCycle(rawValue: "h11")) == .system)
        #expect(HourCycleChoice(.h12).hourCycle == .h12)
        #expect(HourCycleChoice.system.hourCycle == .auto)
        #expect(HourCycleChoice.allCases.map { HourCycleChoice($0.hourCycle) } == HourCycleChoice.allCases)
    }

    @Test func timeZoneSwitchKeepsOrSeeds() {
        let device = TimeZone(identifier: "Europe/Bratislava")!
        #expect(TimeZoneChoices.mode(kind: .followDevice, current: .fixed(identifier: "Asia/Tokyo"), deviceZone: device) == .followDevice)
        #expect(TimeZoneChoices.mode(kind: .fixed, current: .followDevice, deviceZone: device) == .fixed(identifier: "Europe/Bratislava"))
        #expect(TimeZoneChoices.mode(kind: .fixed, current: .fixed(identifier: "Asia/Tokyo"), deviceZone: device) == .fixed(identifier: "Asia/Tokyo"))
        #expect(TimeZoneModeKind(.fixed(identifier: "X")) == .fixed)
    }

    @Test func timeZoneSearch() {
        let known = ["Europe/Berlin", "America/New_York", "Asia/Tokyo"]
        #expect(TimeZoneChoices.identifiers(matching: "", current: nil, known: known) == ["America/New_York", "Asia/Tokyo", "Europe/Berlin"])
        #expect(TimeZoneChoices.identifiers(matching: "new york", current: nil, known: known) == ["America/New_York"])
        #expect(TimeZoneChoices.identifiers(matching: "", current: "Asia/Tokyo", known: known).first == "Asia/Tokyo")
        #expect(TimeZoneChoices.identifiers(matching: "", current: "Mars/Olympus", known: known).first == "Mars/Olympus")
        #expect(TimeZoneChoices.identifiers(matching: "zzz", current: "Asia/Tokyo", known: known).isEmpty)
        #expect(TimeZoneChoices.displayName("America/New_York") == "America / New York")
    }

    @Test func palettePacksGateOnEntitlement() {
        let free = PalettePackChoice.all { _ in false }
        #expect(free.map { $0.isSelectable } == [true, false, false, false])
        let all = PalettePackChoice.all { _ in true }
        #expect(all.allSatisfy { $0.isSelectable })
        #expect(PalettePackChoice.displayedPack(for: PalettePackID(rawValue: "future")).id == .classic)
        #expect(PalettePackChoice.displayedPack(for: .ocean).id == .ocean)
        #expect(PalettePack.all.allSatisfy { LessonTileStyle(color: PalettePackChoice.previewColor(of: $0).value).textContrast >= 4.5 })
    }

    @Test func profilesAndTerminology() {
        #expect(ProfileChoices.selection(for: UserProfile(rawValue: "future")) == .other)
        #expect(ProfileChoices.terminologyKey(for: .university) == "terminology.classLecture")
        #expect(ProfileChoices.terminologyKey(for: .secondary) == "terminology.lesson")
        #expect(ProfileChoices.offered == UserProfile.knownValues)
    }
}
