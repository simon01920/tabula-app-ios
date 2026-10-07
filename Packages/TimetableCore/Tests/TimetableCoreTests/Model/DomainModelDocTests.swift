import Foundation
import Testing
@testable import TimetableCore

/// Keeps docs/specs/DOMAIN_MODEL.md in sync with the code it freezes.
@Suite("DOMAIN_MODEL.md")
struct DomainModelDocTests {
    /// Every String Catalog key core code can emit, per source list (Appendix A section in the name).
    static var keyLists: [(name: String, keys: [String])] {
        [
            ("A.1–A.6 CoreL10n.modelKeys", CoreL10n.modelKeys),
            ("A.7 ScheduleL10n.allKeys", ScheduleL10n.allKeys),
            ("A.8 ReminderL10n.allKeys", ReminderL10n.allKeys),
            ("A.9 ShareError.allL10nKeys", ShareError.allL10nKeys),
            ("A.9 ShareWarning.allL10nKeys", ShareWarning.allL10nKeys),
        ]
    }

    @Test func everyL10nKeyIsListedInTheAppendix() throws {
        let doc = try RepositoryFile.text("docs/specs/DOMAIN_MODEL.md")
        let appendix = try #require(doc.range(of: "## Appendix A").map { String(doc[$0.lowerBound...]) })
        for (name, keys) in Self.keyLists {
            #expect(!keys.isEmpty, "\(name) is empty")
            let missing = keys.filter { !appendix.contains("`\($0)`") }
            #expect(missing.isEmpty, "\(name): missing from DOMAIN_MODEL.md Appendix A: \(missing)")
        }
        let all = CoreL10n.allKeys
        #expect(all == Self.keyLists.flatMap(\.keys), "CoreL10n.allKeys must be the union of the lists above")
        #expect(Set(all).count == all.count, "duplicate l10n keys")
        #expect(doc.contains("Total: \(all.count) keys"), "Appendix A total must be \(all.count)")
        // Sizes the orchestrator tracks per stage (a change here must be reflected in Appendix A).
        #expect(ScheduleL10n.allKeys.count == 18 && ReminderL10n.allKeys.count == 43 && CoreL10n.shareKeys.count == 27)
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
        for code in ValidationIssue.Code.allCases { #expect(doc.contains("| `\(code.rawValue)` |"), "validation code \(code)") }
    }
}

/// Every key core can emit has an English source entry in the app's String Catalog.
///
/// Why a core test (not `scripts/validate.sh`): the key lists live in Swift (`CoreL10n.allKeys`), so only Swift code
/// can enumerate them; reading the catalog through a repository-relative path works on Linux (`swift test`) and in CI,
/// exactly like `DomainModelDocTests` reads DOMAIN_MODEL.md. `scripts/l10n-compile.py` separately proves the catalog
/// compiles for the xtool path.
@Suite("String Catalog")
struct StringCatalogTests {
    static var integerSpecifier: Regex<Substring> { /%(?:\d+\$)?l{0,2}[dDiuU]/ }
    static var anySpecifier: Regex<Substring> { /%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp]/ }

    private func catalogStrings() throws -> [String: JSONValue] {
        let data = try Data(contentsOf: RepositoryFile.url("Resources/Localizable.xcstrings"))
        guard case .object(let root) = try SyncJSONParser.parse(data), root["sourceLanguage"]?.stringValue == "en",
              case .object(let strings)? = root["strings"] else {
            Issue.record("Localizable.xcstrings is not a String Catalog with source language en")
            return [:]
        }
        return strings
    }

    /// The English values of an entry: `[value]` for a plain unit, the plural forms (one, other) otherwise.
    private func englishValues(_ entry: JSONValue) -> (values: [String], isPlural: Bool)? {
        guard let english = entry["localizations"]?["en"] else { return nil }
        if let value = english["stringUnit"]?["value"]?.stringValue { return ([value], false) }
        guard let plural = english["variations"]?["plural"],
              let one = plural["one"]?["stringUnit"]?["value"]?.stringValue,
              let other = plural["other"]?["stringUnit"]?["value"]?.stringValue else { return nil }
        return ([one, other], true)
    }

    @Test func everyCoreKeyHasAnEnglishSourceAndComment() throws {
        let strings = try catalogStrings()
        var missing: [String] = []
        for key in CoreL10n.allKeys {
            guard let entry = strings[key], let (values, isPlural) = englishValues(entry) else {
                missing.append(key)
                continue
            }
            let comment = entry["comment"]?.stringValue ?? ""
            let extractionState = entry["extractionState"]?.stringValue ?? ""
            #expect(!comment.isEmpty, "\(key): translator comment missing")
            #expect(extractionState == "manual", "\(key): keys from core are manual")
            #expect(values.allSatisfy { !$0.isEmpty }, "\(key): empty English value")
            // A count needs plural variations, and the counted argument must be the first specifier of each form
            // (that is the argument `scripts/l10n-compile.py`'s single-variable stringsdict selects on).
            let hasCount = values.contains { $0.contains(Self.integerSpecifier) }
            #expect(hasCount == isPlural, "\(key): plural variations iff the text shows a count")
            if isPlural {
                for value in values {
                    let first = try #require(value.firstMatch(of: Self.anySpecifier)).output
                    #expect(first.contains(Self.integerSpecifier), "\(key): first specifier of \"\(value)\" is not the count")
                }
            }
        }
        #expect(missing.isEmpty, "keys missing from Resources/Localizable.xcstrings: \(missing)")
    }

    /// Pre-freeze QA: one plural axis per string (a second count needs its own key), and data-check messages never
    /// insert a translated noun (they take no arguments; the entity type name is a separate label).
    @Test func atMostOneCountPerKeyAndNoInsertedNouns() throws {
        let strings = try catalogStrings()
        for key in CoreL10n.allKeys {
            guard let entry = strings[key], let (values, _) = englishValues(entry) else { continue }
            for value in values {
                #expect(value.matches(of: Self.integerSpecifier).count <= 1, "\(key): more than one count in \"\(value)\"")
                if key.hasPrefix("validation.") || key.hasPrefix("entityType.") {
                    #expect(value.firstMatch(of: Self.anySpecifier) == nil, "\(key): must take no arguments")
                }
            }
        }
        for code in ValidationIssue.Code.allCases {
            let issue = ValidationIssue(severity: .error, code: code, entityType: .task, entityID: UUID(uuidString: "00000000-0000-4000-8000-000000000000")!)
            #expect(issue.message.args.isEmpty, "\(code)")
        }
        // Pack-tonight bodies carry exactly one count (the item number).
        let day = PackTonightDay(date: Fixture.date("2026-10-12"), firstLessonStart: Fixture.time("08:00"), subjects: [])
        for fire in ["2026-10-12", "2026-10-11", "2026-10-08"] {
            let body = ReminderContentBuilder.packTonight(day, fire: Fixture.date(fire)).body
            #expect(body.args.filter { if case .integer = $0 { return true } else { return false } }.count == 1, "\(body.key)")
        }
    }

    @Test func phaseZeroProbeStringsAreKept() throws {
        let strings = try catalogStrings()
        for key in ["probe.hello", "probe.lessons %lld", "probe.widget.name", "probe.intent.title"] {
            #expect(strings[key] != nil, "\(key)")
        }
    }
}
