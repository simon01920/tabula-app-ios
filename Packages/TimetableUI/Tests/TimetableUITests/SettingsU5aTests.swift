import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4U U5a: Time Sensitive availability (D7), health triage (H9/M4), "Apply to All Subjects" (M26), row summaries.

private let referenceNow = Date(timeIntervalSince1970: 1_791_879_600)
private let english = Locale(identifier: "en_US")

@Suite("Time Sensitive availability (D7)")
struct TimeSensitiveAvailabilityTests {
    @Test func onlySupportedStatesOfferTheTier() {
        #expect(TimeSensitiveAvailability.isAvailable(.enabled))
        #expect(TimeSensitiveAvailability.isAvailable(.disabled))
        #expect(!TimeSensitiveAvailability.isAvailable(.notSupported))
        #expect(!TimeSensitiveAvailability.isAvailable(.unknown))
        #expect(!TimeSensitiveAvailability.isAvailable(nil))
    }

    @Test func pickerOffersStandardAndAlarmWithoutTheEntitlement() {
        #expect(TimeSensitiveAvailability.offeredTiers(timeSensitiveAvailable: false) == [.standard, .alarm])
        #expect(TimeSensitiveAvailability.offeredTiers(timeSensitiveAvailable: true) == [.standard, .timeSensitive, .alarm])
    }

    @Test func savedTimeSensitiveIsShownAsStandardWithAFootnote() {
        #expect(TimeSensitiveAvailability.displayedTier(.timeSensitive, timeSensitiveAvailable: false) == .standard)
        #expect(TimeSensitiveAvailability.needsDowngradeFootnote(stored: .timeSensitive, timeSensitiveAvailable: false))
        #expect(TimeSensitiveAvailability.displayedTier(.timeSensitive, timeSensitiveAvailable: true) == .timeSensitive)
        #expect(!TimeSensitiveAvailability.needsDowngradeFootnote(stored: .timeSensitive, timeSensitiveAvailable: true))
        #expect(TimeSensitiveAvailability.displayedTier(.alarm, timeSensitiveAvailable: false) == .alarm)
        #expect(!TimeSensitiveAvailability.needsDowngradeFootnote(stored: .standard, timeSensitiveAvailable: false))
    }
}

@Suite("Reminder health triage (H9, M4)")
struct ReminderHealthTriageTests {
    private func input(auth: NotificationAuthorization = .authorized, timeSensitive: NotificationSettingState = .notSupported,
                       alarms: AlarmAuthorization = .authorized, lowPower: Bool = false,
                       refresh: BackgroundRefreshState = .available, plan: ReminderPlan? = nil) -> ReminderHealthInput {
        ReminderHealthInput(notifications: NotificationSettingsSnapshot(authorization: auth, timeSensitive: timeSensitive),
                            alarmAuthorization: alarms,
                            device: DeviceReminderState(isLowPowerModeEnabled: lowPower, backgroundRefresh: refresh),
                            pendingCount: 16, lastPlan: plan, usesTimeSensitive: true, usesLoudAlarms: true,
                            hasReminders: true)
    }

    private func kinds(_ items: [ReminderHealthItem]) -> [ReminderHealthItem.Kind] { items.map(\.kind) }

    @Test func unsupportedTimeSensitiveIsHiddenAndNeverAWarning() {
        let items = ReminderHealthCheck.evaluate(input())
        #expect(items.contains { $0.kind == .timeSensitive && $0.status == .warning })   // the raw row exists …
        #expect(!kinds(ReminderHealthTriage.checks(items)).contains(.timeSensitive))     // … but is not shown
        #expect(!kinds(ReminderHealthTriage.technical(items)).contains(.timeSensitive))
        #expect(ReminderHealthTriage.summaryStatus(items) == .ok)
        #expect(!ReminderHealthTriage.needsAttention(items))
    }

    @Test func timeSensitiveTurnedOffInSettingsIsUserFixable() {
        let items = ReminderHealthCheck.evaluate(input(timeSensitive: .disabled))
        #expect(kinds(ReminderHealthTriage.checks(items)).contains(.timeSensitive))
        #expect(ReminderHealthTriage.summaryStatus(items) == .warning)
    }

    @Test func permissionsAndDeviceSettingsRaiseTheSummary() {
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(auth: .denied))) == .problem)
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(auth: .notDetermined))) == .warning)
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(refresh: .denied))) == .warning)
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(lowPower: true))) == .warning)
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(alarms: .denied))) == .problem)
        // Restricted background refresh cannot be changed by the user: information, not a warning.
        #expect(ReminderHealthTriage.summaryStatus(ReminderHealthCheck.evaluate(input(refresh: .restricted))) == .ok)
    }

    @Test func appSideLimitsAreTechnicalDetailsOnly() async {
        let engine = await ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: InMemoryAlarmClient(limit: 0),
                                          store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        let items = ReminderHealthCheck.evaluate(input(alarms: .unavailable, plan: result.plan))
        let technical = kinds(ReminderHealthTriage.technical(items))
        #expect(technical.contains(.pending) && technical.contains(.alarmOverflow))
        #expect(technical.contains(.alarms) && technical.contains(.silentMode))
        #expect(Set(kinds(ReminderHealthTriage.checks(items))).isDisjoint(with: [.pending, .alarmOverflow, .saturation, .silentMode]))
        #expect(ReminderHealthTriage.summaryStatus(items) == .ok)       // warnings that carry no action never count
        let pending = items.first { $0.kind == .pending }
        #expect(pending?.detail == LocalizedText(key: "health.pending.detail", args: [.integer(16), .integer(64)]))
    }

    @Test func focusGetsAnOpenSettingsButton() {
        let items = ReminderHealthCheck.evaluate(input())
        let focus = items.first { $0.kind == .focus }
        #expect(focus.flatMap(ReminderHealthTriage.fallbackAction(for:)) == .openAppSettings)
        let pending = items.first { $0.kind == .pending }
        #expect(pending.flatMap(ReminderHealthTriage.fallbackAction(for:)) == nil)
    }

    @Test func keysAreInTheCatalog() throws {
        let catalog = try CatalogFile.keys()
        let missing = (TimeSensitiveAvailability.keys + ReminderHealthTriage.keys + SettingsSummaries.keys)
            .filter { !catalog.contains($0) }
        #expect(missing.isEmpty, "missing: \(missing)")
    }
}

@Suite("Apply palette to subjects (M26)")
struct PaletteRemapTests {
    private func scenario() -> (TabulaDatabase, Timetable.ID) {
        let scenario = SampleScenarios.secondary()
        return (scenario.database, scenario.timetable.id)
    }

    private func apply(_ mutation: DatabaseMutation, to database: TabulaDatabase,
                       clock: inout HybridLogicalClock) throws -> TabulaDatabase {
        clock.receive(database.latestTimestamp, now: referenceNow)
        return try mutation.apply(to: database, clock: &clock, now: referenceNow.addingTimeInterval(5))
    }

    @Test func subjectsTakeTheColourAtTheSameIndexAndUndoRestoresThem() throws {
        let (database, timetableID) = scenario()
        let before = TimetableManagement.subjects(of: timetableID, in: database, locale: english)
        let changed = PaletteRemap.remapped(in: database, to: .ocean, locale: english)
        #expect(!changed.isEmpty)
        for subject in changed {
            let old = try #require(before.first { $0.id == subject.id })
            let oldIndex = try #require(PaletteRemap.packIndex(of: old))     // sample subjects use palette colours
            #expect(subject.color == PalettePack.ocean.colors[oldIndex % PalettePack.ocean.colors.count].value)
            #expect(subject.colorName == .key(PalettePack.ocean.colors[oldIndex % PalettePack.ocean.colors.count].nameKey))
        }
        var clock = HybridLogicalClock(node: 0xA5)
        let applied = try apply(try #require(PaletteRemap.mutation(for: changed)), to: database, clock: &clock)
        for subject in changed {
            #expect(applied.subjects.first { $0.id == subject.id }?.color == subject.color)
        }
        #expect(applied.validate().filter { $0.severity == .error }.isEmpty)

        // Undo: the original versions go back through the same path.
        let originals = changed.compactMap { new in before.first { $0.id == new.id } }
        let undone = try apply(try #require(PaletteRemap.mutation(for: originals, label: "undo palette")), to: applied, clock: &clock)
        for original in originals {
            #expect(undone.subjects.first { $0.id == original.id }?.color == original.color)
        }
    }

    @Test func applyingTheCurrentPaletteChangesNothing() {
        let (database, _) = scenario()
        let first = PaletteRemap.remapped(in: database, to: .classic, locale: english)
        #expect(PaletteRemap.mutation(for: []) == nil)
        // Whatever the sample uses, a second remap onto the same pack from the remapped colours is a no-op.
        var remapped = database
        for subject in first { if let i = remapped.subjects.firstIndex(where: { $0.id == subject.id }) { remapped.subjects[i] = subject } }
        #expect(PaletteRemap.remapped(in: remapped, to: .classic, locale: english).isEmpty)
    }

    @Test func customColoursUseTheirPositionAndKeepUserNames() throws {
        let (base, timetableID) = scenario()
        var database = base
        let ordered = TimetableManagement.subjects(of: timetableID, in: database, locale: english)
        let target = try #require(ordered.last)
        let index = try #require(database.subjects.firstIndex { $0.id == target.id })
        database.subjects[index].color = try #require(ColorValue(hex: "#123457"))
        database.subjects[index].colorName = .literal("My blue")
        let changed = PaletteRemap.remapped(in: database, to: .pastel, locale: english)
        let moved = try #require(changed.first { $0.id == target.id })
        #expect(moved.color == PalettePack.pastel.colors[(ordered.count - 1) % PalettePack.pastel.colors.count].value)
        #expect(moved.colorName == .literal("My blue"))
    }
}

@Suite("Settings row summaries")
struct SettingsSummariesTests {
    @Test func timeFormatDefaultsToSystemAndUnknownStoredValuesBehaveAsSystem() {
        #expect(AppSettings.untouchedDefaults.hourCycle == .auto)
        #expect(SettingsSummaries.hourCycleKey(.auto) == "settings.calendar.hourcycle.system")
        #expect(SettingsSummaries.hourCycleKey(.h12) == "settings.calendar.hourcycle.h12")
        #expect(SettingsSummaries.hourCycleKey(.h24) == "settings.calendar.hourcycle.h24")
        #expect(SettingsSummaries.hourCycleKey(HourCycle(rawValue: "h23x")) == "settings.calendar.hourcycle.system")
    }

    @Test func countsComeFromTheActiveTimetable() throws {
        let scenario = SampleScenarios.secondary()
        let database = scenario.database
        #expect(SettingsSummaries.subjectCount(of: scenario.timetable.id, in: database)
                == database.subjects.filter { !$0.isDeleted && $0.timetableID == scenario.timetable.id }.count)
        let periods = SettingsSummaries.periodCount(of: scenario.timetable, in: database)
        #expect((periods ?? 0) > 0)
    }

    @Test func enabledKindsAreCounted() {
        #expect(SettingsSummaries.enabledReminderKinds([]) == 0)
        let rule = ReminderRuleDefaults.rule(for: .homework, profile: .secondary, id: ReminderRule.ID(UUID()))
        #expect(SettingsSummaries.enabledReminderKinds([rule]) == 1)
        var off = rule
        off.isEnabled = false
        #expect(SettingsSummaries.enabledReminderKinds([off]) == 0)
    }
}
