import Foundation
import Testing
@testable import TimetableCore

/// Keeps docs/specs/DOMAIN_MODEL.md in sync with the code it freezes.
@Suite("DOMAIN_MODEL.md")
struct DomainModelDocTests {
    /// Every String Catalog key Stage 1 code can emit.
    static var allL10nKeys: [String] {
        var keys = EntityType.allCases.map(\.l10nKey)
        keys += ValidationIssue.Code.allCases.map(\.l10nKey)
        keys += Conflict.Kind.allCases.map(\.l10nKey)
        keys += ProfilePreset.Terminology.allCases.map(\.l10nKey)
        for pack in PalettePack.all {
            keys.append(pack.nameKey)
            keys += pack.colors.map(\.nameKey)
        }
        keys += SampleData.allKeys
        return keys
    }

    @Test func everyL10nKeyIsListedInTheAppendix() throws {
        let doc = try RepositoryFile.text("docs/specs/DOMAIN_MODEL.md")
        let keys = Self.allL10nKeys
        #expect(Set(keys).count == keys.count, "duplicate l10n keys")
        let missing = keys.filter { !doc.contains("`\($0)`") }
        #expect(missing.isEmpty, "missing from DOMAIN_MODEL.md: \(missing)")
        #expect(doc.contains("Total: \(keys.count) keys"), "Appendix A total must be \(keys.count)")
    }

    @Test func everyEntityTypeAndUnionKindIsDocumented() throws {
        let doc = try RepositoryFile.text("docs/specs/DOMAIN_MODEL.md")
        for type in EntityType.allCases { #expect(doc.contains("`\(type.rawValue)`"), "\(type)") }
        for kind in ["cancelLesson", "modifyLesson", "addLesson", "cancelDay", "useBellSchedule", "followDay",
                     "minutesBefore", "daysBefore", "afterMinutes", "nextMorning", "isoWeekParity", "referenceWeek",
                     "weekCycle", "dayCycle", "bellSchedule", "freeForm", "period", "time", "always", "terms", "range",
                     "weekday", "cycleDay", "dateTime", "followDevice", "fixed", "emoji", "systemImage", "key", "literal",
                     "inherit", "custom"] {
            #expect(doc.contains("\"\(kind)\""), "kind \(kind) not documented")
        }
        #expect(doc.contains("schemaVersion"))
    }
}
