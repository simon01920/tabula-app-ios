import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4U U7: countdown durations and units (H2), short subject names (M29) (the ink and highlighter tokens are tested in DesignSystemTests).

private let u7Zone = SampleScenarios.timeZone
private let u7Renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: u7Zone),
    lookup: EnglishCatalog.lookup)
private let u7Builder = WidgetCountdownBuilder(renderer: u7Renderer)
private let u7Base = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Widget countdown (H2)")
struct WidgetCountdownTests {
    @Test func durationsAreWholeMinutesRoundedUpWithAbbreviatedUnits() {
        #expect(u7Builder.durationText(25 * 60) == "25 min")
        #expect(u7Builder.durationText(60 * 60) == "1 h")
        #expect(u7Builder.durationText(90 * 60) == "1 h 30 min")
        #expect(u7Builder.durationText(2 * 3600 + 5 * 60) == "2 h 5 min")
        #expect(u7Builder.durationText(20) == "1 min")        // 20 s left still reads as a minute, never seconds
        #expect(u7Builder.durationText(0) == "0 min")
        #expect(u7Builder.durationText(-30) == "0 min")
        #expect(!u7Builder.durationText(125.9).contains("s"))
    }

    @Test func modeSwitchesAtSixtyMinutesAndExamsNeverShowSeconds() {
        func make(_ minutes: Double, kind: WidgetCountdown.Kind = .left, seconds: Bool = true) -> WidgetCountdown {
            u7Builder.make(interval: u7Base...u7Base.addingTimeInterval(minutes * 60), now: u7Base, kind: kind,
                           allowsSeconds: seconds)
        }
        #expect(make(59.99).mode == .timer)
        #expect(make(60).mode == .minutes)
        #expect(make(90).mode == .minutes)
        #expect(make(5, seconds: false).mode == .minutes)        // exams: minutes only even at 5 minutes
        #expect(make(25).phrase == "25 min left" && make(25).unitLabel == "left")
        #expect(make(90, kind: .untilStart).phrase == "in 1 h 30 min")
        #expect(make(90, kind: .untilStart).unitLabel == "until start")
    }

    @Test func aCountdownStartedBeforeTheIntervalCountsFromItsStart() {
        // A clock before the interval's start (stale render): the whole interval remains.
        let countdown = u7Builder.make(interval: u7Base...u7Base.addingTimeInterval(45 * 60),
                                       now: u7Base.addingTimeInterval(-600), kind: .left, allowsSeconds: true)
        #expect(countdown.durationText == "45 min")
    }
}

@Suite("Short subject names (M29)")
struct SubjectAbbreviationTests {
    private func subject(_ name: String, short: String? = nil) -> SubjectSummary {
        SubjectSummary(id: Subject.ID(UUID()), name: name, shortName: short, color: ColorValue(red: 30, green: 90, blue: 200))
    }

    @Test func theShortNameWinsElseLettersAreDerived() {
        #expect(SubjectAbbreviation.short(for: subject("Slovenský jazyk a literatúra", short: "SJL")) == "SJL")
        #expect(SubjectAbbreviation.short(for: subject("Mathematics", short: "  ")) == "MAT")   // blank short name ignored
        #expect(SubjectAbbreviation.short(for: subject("Slovenský jazyk a literatúra")) == "SJL")
        #expect(SubjectAbbreviation.short(for: subject("Anglický jazyk")) == "AJ")
        #expect(SubjectAbbreviation.short(for: subject("Physical Education")) == "PE")
        #expect(SubjectAbbreviation.short(for: subject("Biology")) == "BIO")
        #expect(SubjectAbbreviation.short(for: subject("Art")) == "ART")
        #expect(SubjectAbbreviation.short(for: subject("Matematika a informatika pre život")) == "MIP")
        #expect(SubjectAbbreviation.short(for: subject("")) == "")
        #expect(SubjectAbbreviation.derived(from: "Dejepis").count <= SubjectAbbreviation.maxLength)
    }
}
