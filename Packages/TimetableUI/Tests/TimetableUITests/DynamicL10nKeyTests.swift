import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("Dynamic localisation keys")
struct DynamicL10nKeyTests {
    @Test func everyDynamicKeyIsInTheCatalog() {
        let missing = DynamicL10nKeys.allKeys.filter { EnglishCatalog.values[$0] == nil }
        #expect(missing.isEmpty, "Missing from Localizable.xcstrings: \(missing)")
        #expect(DynamicL10nKeys.allKeys.count > 40)
    }

    @Test func issueAndFamilyKeysExist() {
        var keys: [String] = []
        keys += DayChangeDraft.Kind.allCases.map(\.l10nKey)
        keys += TimetableViewKind.knownValues.map(TimetableViewChoice.nameKey)
        keys += TimetableDraft.RotationKind.allCases.map(DynamicL10nKeys.rotationKind)
        let missing = keys.filter { EnglishCatalog.values[$0] == nil }
        #expect(missing.isEmpty, "Missing: \(missing)")
    }

    @Test func profileKeysMatchWhatSettingsShows() {
        for profile in ProfileChoices.offered {
            #expect(EnglishCatalog.values[DynamicL10nKeys.profile(profile)] != nil)
        }
    }
}
