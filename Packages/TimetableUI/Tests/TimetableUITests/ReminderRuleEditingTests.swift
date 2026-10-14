import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Reminder rule editing (B4)")
struct ReminderRuleEditingTests {
    private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }

    @Test func offsetTextUsesOneFormatPerShape() {
        #expect(ReminderOffsetEditing.text(.minutesBefore(0)).key == "reminders.offset.atDue")
        #expect(ReminderOffsetEditing.text(.minutesBefore(15)) ==
                LocalizedText(key: "reminders.offset.minutesBefore", args: [.integer(15)]))
        #expect(ReminderOffsetEditing.text(.minutesBefore(120)) ==
                LocalizedText(key: "reminders.offset.hoursBefore", args: [.integer(2)]))
        #expect(ReminderOffsetEditing.text(.minutesBefore(90)).key == "reminders.offset.minutesBefore")
        #expect(ReminderOffsetEditing.text(.daysBefore(0, at: time(7))) ==
                LocalizedText(key: "reminders.offset.sameDay", args: [.time(time(7))]))
        #expect(ReminderOffsetEditing.text(.daysBefore(1, at: time(18))) ==
                LocalizedText(key: "reminders.offset.daysBefore", args: [.integer(1), .time(time(18))]))
        #expect(ReminderOffsetEditing.text(.unknown(.null)).key == "reminders.offset.unsupported")
    }

    @Test func presetsAreNotOfferedTwice() {
        let existing: [ReminderOffset] = [.daysBefore(1, at: ReminderOffsetEditing.defaultEvening)]
        let available = ReminderOffsetEditing.availablePresets(excluding: existing)
        #expect(!available.contains(existing[0]))
        #expect(available.count == ReminderOffsetEditing.presets.count - 1)
        #expect(ReminderOffsetEditing.adding(existing[0], to: existing) == existing)
    }

    @Test func convertingKindsKeepsUnknownAndSeedsDefaults() {
        #expect(ReminderOffsetEditing.converting(.minutesBefore(5), to: .daysBefore)
                == .daysBefore(1, at: ReminderOffsetEditing.defaultEvening))
        #expect(ReminderOffsetEditing.converting(.daysBefore(2, at: time(9)), to: .minutesBefore) == .minutesBefore(30))
        #expect(ReminderOffsetEditing.converting(.minutesBefore(5), to: .minutesBefore) == .minutesBefore(5))
        let raw = ReminderOffset.unknown(.string("x"))
        #expect(ReminderOffsetEditing.converting(raw, to: .daysBefore) == raw)
        #expect(ReminderOffsetEditing.kind(of: raw) == nil)
    }

    @Test func ruleFollowUpChoicesKeepPayloadWhenKindIsUnchanged() {
        #expect(FollowUpEditing.followUp(choosing: .afterMinutes, current: nil) == .afterMinutes(120))
        #expect(FollowUpEditing.followUp(choosing: .afterMinutes, current: .afterMinutes(60)) == .afterMinutes(60))
        #expect(FollowUpEditing.followUp(choosing: .nextMorning, current: .afterMinutes(60)) == .nextMorning(at: time(7)))
        #expect(FollowUpEditing.followUp(choosing: .none, current: .afterMinutes(60)) == nil)
        let raw = FollowUp.unknown(.string("future"))
        #expect(FollowUpEditing.followUp(choosing: .unsupported, current: raw) == raw)
        #expect(FollowUpEditing.options(forOverride: false, current: .none) == [.none, .afterMinutes, .nextMorning])
        #expect(FollowUpEditing.options(forOverride: true, current: .unsupported).last == .unsupported)
        #expect(FollowUpEditing.options(forOverride: true, current: .inherit).first == .inherit)
    }

    @Test func overrideFollowUpMapsBothWays() {
        #expect(FollowUpEditing.kind(of: FollowUpOverride.inherit) == .inherit)
        #expect(FollowUpEditing.kind(of: FollowUpOverride.none) == .none)
        #expect(FollowUpEditing.kind(of: FollowUpOverride.custom(.afterMinutes(30))) == .afterMinutes)
        #expect(FollowUpEditing.override(choosing: .afterMinutes, current: .inherit) == .custom(.afterMinutes(120)))
        #expect(FollowUpEditing.override(choosing: .afterMinutes, current: .custom(.afterMinutes(30))) == .custom(.afterMinutes(30)))
        #expect(FollowUpEditing.override(choosing: .inherit, current: .custom(.afterMinutes(30))) == .inherit)
        #expect(FollowUpEditing.override(choosing: .none, current: .inherit) == .none)
        #expect(FollowUpEditing.minuteOptions(including: 45) == [30, 45, 60, 120, 180, 240, 360])
        #expect(FollowUpEditing.minuteOptions(including: 60) == FollowUpEditing.minuteOptions)
    }

    @Test func defaultsComeFromTheProfilePresetElseFallback() {
        let id = ReminderRule.ID(UUID())
        let homework = ReminderRuleDefaults.rule(for: .homework, profile: .secondary, id: id)
        #expect(homework.offsets == [.daysBefore(1, at: time(17))])
        #expect(homework.followUp == .nextMorning(at: time(7)))
        #expect(homework.isEnabled)
        #expect(homework.origin == .preset)
        let todo = ReminderRuleDefaults.rule(for: .todo, profile: .other, id: id)
        #expect(todo.offsets == [.daysBefore(1, at: time(18))])
        #expect(ReminderRuleDefaults.rule(for: .packTonight, profile: .university, id: id).offsets.count == 1)
    }

    @Test func editingMarksTheRuleUserMade() {
        let rule = ReminderRuleDefaults.rule(for: .exam, profile: .other, id: ReminderRule.ID(UUID()))
        #expect(rule.origin == .preset)
        #expect(ReminderRuleEditing.touched(rule).origin == .user)
        var empty = rule
        empty.offsets = []
        #expect(ReminderRuleEditing.isIncomplete(empty))
        empty.isEnabled = false
        #expect(!ReminderRuleEditing.isIncomplete(empty))
    }

    @Test func summaryNeverConcatenates() {
        var rule = ReminderRuleDefaults.rule(for: .exam, profile: .other, id: ReminderRule.ID(UUID()))
        #expect(ReminderRuleSummary.lines(rule).first?.key == "reminders.offset.daysBefore")
        rule.offsets.append(.minutesBefore(15))
        #expect(ReminderRuleSummary.lines(rule).first == LocalizedText(key: "reminders.summary.multiple", args: [.integer(2)]))
        rule.tier = .alarm
        #expect(ReminderRuleSummary.lines(rule).map(\.key).last == "settings.reminders.alarm.title")
        rule.isEnabled = false
        #expect(ReminderRuleSummary.lines(rule).isEmpty)
    }

    @Test func packTonightHiddenWithoutBringList() {
        let rule = ReminderRuleDefaults.rule(for: .packTonight, profile: .other, id: ReminderRule.ID(UUID()))
        #expect(!ReminderKindList.visibleTargets(bringListVisible: false, rules: []).contains(.packTonight))
        #expect(ReminderKindList.visibleTargets(bringListVisible: true, rules: []).contains(.packTonight))
        #expect(ReminderKindList.visibleTargets(bringListVisible: false, rules: [rule]).contains(.packTonight))
        var off = rule
        off.isEnabled = false
        #expect(!ReminderKindList.visibleTargets(bringListVisible: false, rules: [off]).contains(.packTonight))
    }

    @Test func tierKeysAndStatusKeysExistInTheCatalog() {
        let missing = ReminderUIKeys.allKeys.filter { EnglishCatalog.values[$0] == nil }
        #expect(missing.isEmpty, "Missing from Localizable.xcstrings: \(missing)")
        #expect(ReminderTierInfo.titleKey(.init(rawValue: "future")) == "settings.reminders.standard.title")
        #expect(ReminderHealthPresentation.testAlarmKey(.limitReached) == "health.test.alarm.limit")
    }
}
