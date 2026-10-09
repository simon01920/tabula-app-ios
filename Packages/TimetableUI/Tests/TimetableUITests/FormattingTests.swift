import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

/// English values of Resources/Localizable.xcstrings (plural variations: "other"), so tests render what the app
/// renders in English and fail when a key the UI layer uses is missing from the catalog.
enum EnglishCatalog {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // Tests/TimetableUITests/x
        .deletingLastPathComponent().deletingLastPathComponent()                              // Packages/TimetableUI
        .appendingPathComponent("Resources/Localizable.xcstrings")

    static let values: [String: String] = {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in strings {
            guard let english = ((value as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            else { continue }
            if let unit = english["stringUnit"] as? [String: Any], let text = unit["value"] as? String {
                result[key] = text
            } else if let plural = (english["variations"] as? [String: Any])?["plural"] as? [String: Any],
                      let other = ((plural["other"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String {
                result[key] = other
            }
        }
        return result
    }()

    static let lookup: LocalizedTextRenderer.Lookup = { key in values[key] ?? key }
}

private let zone = TimeZone(identifier: "Europe/Bratislava")!

private func formatter(_ locale: String, _ cycle: HourCycle = .auto) -> TimetableFormatter {
    TimetableFormatter(locale: Locale(identifier: locale), hourCycle: cycle, timeZone: zone)
}

/// Replaces the narrow / thin spaces ICU puts around AM/PM and in ranges with plain spaces for readable asserts.
private func plain(_ text: String) -> String {
    String(text.unicodeScalars.map { [0x202F, 0x2009, 0x00A0].contains($0.value) ? " " : Character($0) })
}

@Suite("TimetableFormatter")
struct TimetableFormatterTests {
    private let afternoon = LocalTime(hour: 13, minute: 5)!

    @Test func hourCycleFollowsLocaleUnlessOverridden() {
        #expect(plain(formatter("en_US").time(afternoon)) == "1:05 PM")
        #expect(formatter("en_US", .h24).time(afternoon) == "13:05")
        #expect(formatter("sk_SK").time(afternoon) == "13:05")
        #expect(plain(formatter("sk_SK", .h12).time(afternoon)) == "1:05 PM")
        #expect(formatter("de_DE", HourCycle(rawValue: "future")).time(afternoon) == "13:05")   // unknown → auto
    }

    @Test func instantsUseTheContextZone() {
        // 2026-10-13 08:20 UTC = 10:20 CEST.
        #expect(formatter("sk_SK").time(Date(timeIntervalSince1970: 1_791_879_600)) == "10:20")
        // DST end night: 2026-10-25 00:30 UTC = 02:30 CEST, 01:30 UTC = 02:30 CET.
        #expect(formatter("sk_SK").time(Date(timeIntervalSince1970: 1_792_888_200)) == "2:30")
        #expect(formatter("sk_SK").time(Date(timeIntervalSince1970: 1_792_891_800)) == "2:30")
    }

    @Test func wallClockTimesIgnoreDST() {
        let start = LocalTime(hour: 8, minute: 55)!, end = LocalTime(hour: 9, minute: 40)!
        #expect(plain(formatter("sk_SK").timeRange(start, end)) == "8:55 – 9:40")
        #expect(plain(formatter("en_US").timeRange(start, end)) == "8:55 – 9:40 AM")
        #expect(formatter("de_DE").timeRange(start, end).hasSuffix("Uhr"))
    }

    @Test func dates() {
        let date = LocalDate(year: 2026, month: 10, day: 13)!
        #expect(formatter("en_US").date(date, style: .abbreviated) == "Oct 13, 2026")
        #expect(formatter("en_US").date(date, style: .numeric) == "10/13/2026")
        #expect(plain(formatter("sk_SK").date(date, style: .numeric)) == "13. 10. 2026")
        #expect(formatter("en_US").date(date, style: .full) == "Tuesday, October 13, 2026")
        #expect(formatter("en_US").weekdayName(.tuesday) == "Tuesday")
        #expect(formatter("sk_SK").weekdayName(.tuesday) == "utorok")
        #expect(formatter("en_US").weekdayName(.sunday, width: .abbreviated) == "Sun")
    }

    @Test func lists() {
        #expect(formatter("en_US").list(["kit", "shoes", "water"]) == "kit, shoes, and water")
        #expect(plain(formatter("sk_SK").list(["úbor", "prezuvky"])) == "úbor a prezuvky")
    }
}

@Suite("LocalizedTextRenderer")
struct LocalizedTextRendererTests {
    private let renderer = LocalizedTextRenderer(formatter: formatter("en_US", .h24), lookup: EnglishCatalog.lookup)

    @Test func catalogIsReadable() {
        #expect(EnglishCatalog.values.count > 200, "catalog not found at \(EnglishCatalog.url.path)")
    }

    @Test func coreTextWithArguments() {
        #expect(renderer.string(LocalizedText(key: "reminder.exam.title", args: [.string("Písomka")])) == "Exam: Písomka")
        let text = LocalizedText(key: "reminder.exam.inDaysAt", args: [
            .integer(3), .date(LocalDate(year: 2026, month: 10, day: 22)!), .time(LocalTime(hour: 10, minute: 0)!),
        ])
        // Linux path: positional substitution with the "other" form (plural choice is a device check).
        #expect(renderer.string(text) == "In 3 days, on Oct 22, 2026 at 10:00")
    }

    @Test func nestedTextAndMissingKey() {
        let nested = LocalizedText(key: "reminder.exam.title", args: [.text(LocalizedText(key: "terminology.lesson"))])
        #expect(renderer.string(nested) == "Exam: Lesson")
        #expect(renderer.string(LocalizedText(key: "no.such.key")) == "no.such.key")
        #expect(renderer.isMissing("no.such.key"))
    }

    @Test func substitutionEdgeCases() {
        #expect(CatalogFormat.substitute("%2$@ / %1$@", [.text("a"), .text("b")]) == "b / a")
        #expect(CatalogFormat.substitute("%lld%% of %@", [.integer(50), .text("x")]) == "50% of x")
        #expect(CatalogFormat.substitute("%@ and %@", [.text("only")]) == "only and ?")
        #expect(CatalogFormat.substitute("100%", []) == "100%")
    }
}
