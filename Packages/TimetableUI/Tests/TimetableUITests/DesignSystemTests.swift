// Phase 4U U1: pure checks of the design foundation. WCAG contrast of every token pair the app relies on, the
// AppSymbol table, the hour-cycle locale (D4 / H1) and dates without the current year (L1).
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private typealias Ref = DesignTokens.Reference
private typealias Min = DesignTokens.Minimum

@Suite("Design tokens: contrast")
struct DesignTokenContrastTests {
    /// `foreground` on every surface of its appearance reaches `minimum`, in all four variants of `token`.
    private func expectOnSurfaces(_ token: ColorToken, minimum: Double, _ name: String) {
        for variant in token.variants {
            for surface in Ref.surfaces(isDark: variant.isDark) {
                let ratio = variant.color.contrastRatio(with: surface)
                #expect(ratio >= minimum, "\(name) \(variant.color) on \(surface): \(ratio)")
            }
        }
    }

    @Test func inkIsReadableTextOnEveryCard() {
        expectOnSurfaces(DesignTokens.ink, minimum: Min.text, "ink")
        #expect(DesignTokens.ink.light.contrastRatio(with: .white) >= 8.4)          // Opus §9: 8.5:1
        #expect(DesignTokens.ink.dark.contrastRatio(with: Ref.darkCard) >= 7.0)     // 7.1:1
    }

    @Test func increaseContrastInkIsStrongerThanDefault() {
        let ink = DesignTokens.ink
        #expect(ink.lightIncreasedContrast.contrastRatio(with: .white) > ink.light.contrastRatio(with: .white))
        #expect(ink.darkIncreasedContrast.contrastRatio(with: Ref.darkCard) > ink.dark.contrastRatio(with: Ref.darkCard))
        #expect(ink.lightIncreasedContrast == ColorValue(hex: "#1A2F85"))
    }

    @Test func labelsOnInkFill() {
        for variant in DesignTokens.ink.variants {
            let label = DesignTokens.onInk.resolved(isDark: variant.isDark, increasedContrast: variant.increasedContrast)
            #expect(label.contrastRatio(with: variant.color) >= Min.text, "onInk on \(variant.color)")
        }
        // Why onInk exists: white on the dark-mode ink would fail.
        #expect(ColorValue.white.contrastRatio(with: DesignTokens.ink.dark) < Min.largeText)
        #expect(ColorValue.white.contrastRatio(with: DesignTokens.ink.light) >= 8.4)
    }

    @Test func correctionIsReadableOnEveryCard() {
        expectOnSurfaces(DesignTokens.correction, minimum: Min.text, "correction")
        #expect(DesignTokens.correction.light.contrastRatio(with: .white) >= 5.6)
        #expect(DesignTokens.correction.dark.contrastRatio(with: Ref.darkCard) >= 6.0)
    }

    @Test func blackOnHighlighter() {
        for variant in DesignTokens.highlighter.variants {
            let text = DesignTokens.onHighlighter.resolved(isDark: variant.isDark, increasedContrast: variant.increasedContrast)
            #expect(text.contrastRatio(with: variant.color) >= 16)
        }
    }

    @Test func pencilReachesBodyTextContrastOnCards() {
        expectOnSurfaces(DesignTokens.pencil, minimum: Min.text, "pencil")
        // The system secondary label it replaces for data: 3.44:1 on white (Opus §13), below 4.5.
        #expect(Ref.lightSecondaryLabel.contrastRatio(with: .white) < Min.text)
    }

    @Test func proBadgeTextOnItsTintedCapsule() {
        for variant in DesignTokens.ink.variants {
            for surface in Ref.surfaces(isDark: variant.isDark) {
                var fill = variant.color
                fill.alpha = DesignTokens.proBadgeFillAlpha
                let capsule = fill.composited(over: surface)
                #expect(variant.color.contrastRatio(with: capsule) >= Min.text, "Pro on \(capsule)")
            }
        }
    }

    @Test func neutralRingsAndOutlinesReachNonTextMinimum() {
        // Task checkbox ring and empty-slot outline use the secondary label colour (C2).
        for surface in Ref.lightSurfaces {
            #expect(Ref.lightSecondaryLabel.contrastRatio(with: surface) >= Min.nonText, "ring on \(surface)")
        }
        for surface in Ref.darkSurfaces {
            #expect(Ref.darkSecondaryLabel.contrastRatio(with: surface) >= Min.nonText, "ring on \(surface)")
        }
        // Tertiary label (suggested in the review) would not be enough: documents the deviation.
        #expect(Ref.lightTertiaryLabel.contrastRatio(with: .white) < Min.nonText)
    }

    @Test func checkedCheckboxUsesInkWithOnInkTick() {
        for variant in DesignTokens.ink.variants {
            for surface in Ref.surfaces(isDark: variant.isDark) {
                #expect(variant.color.contrastRatio(with: surface) >= Min.nonText)
            }
        }
    }

    @Test func tokenResolution() {
        let token = ColorToken(light: .white, dark: .black)
        #expect(token.resolved(isDark: false, increasedContrast: true) == .white)   // defaults to the base variant
        #expect(token.resolved(isDark: true, increasedContrast: true) == .black)
        #expect(token.variants.count == 4)
    }
}

@Suite("AppSymbol")
struct AppSymbolTests {
    @Test func oneSymbolPerConcept() {
        let names = AppSymbol.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count, "two concepts share a symbol")
    }

    @Test func namesAreWellFormed() {
        for symbol in AppSymbol.allCases {
            let ok = symbol.rawValue.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)*$"#, options: .regularExpression) != nil
            #expect(ok, "\(symbol.rawValue)")
        }
    }

    @Test func reviewMappings() {
        #expect(AppSymbol.room.rawValue == "mappin.and.ellipse")          // M8: one room symbol everywhere
        #expect(AppSymbol.repeats.rawValue == "repeat")
        #expect(AppSymbol.timeChanged.rawValue == "clock.badge.exclamationmark")
        #expect(AppSymbol.roomChanged.rawValue == "arrow.right.square")
        #expect(AppSymbol.substitute.rawValue == "person.2.badge.gearshape")
        #expect(AppSymbol.cancelled.rawValue == "xmark.circle.fill")
        #expect(AppSymbol.extraLesson.rawValue == "plus.circle.fill")
        // ↻ no longer means "changed" (it is the repeat / sync glyph elsewhere, H5).
        #expect(!AppSymbol.allCases.map(\.rawValue).contains("arrow.triangle.2.circlepath"))
    }

    @Test func changeSymbolPerReason() {
        #expect(AppSymbol.change(for: [.timeChanged]) == .timeChanged)
        #expect(AppSymbol.change(for: [.roomChanged]) == .roomChanged)
        #expect(AppSymbol.change(for: [.buildingChanged]) == .roomChanged)
        #expect(AppSymbol.change(for: [.teacherChanged]) == .substitute)
        #expect(AppSymbol.change(for: [.subjectChanged]) == .subjectChanged)
        #expect(AppSymbol.change(for: [.notesChanged]) == .changed)
        #expect(AppSymbol.change(for: [.timeChanged, .roomChanged]) == .changed)
        #expect(AppSymbol.change(for: []) == .changed)
        for reason in ModificationReason.allCases { _ = AppSymbol.change(for: [reason]) }   // total
    }

    @Test func statusSymbols() {
        #expect(AppSymbol.status(.scheduled, reasons: []) == nil)
        #expect(AppSymbol.status(.cancelled, reasons: []) == .cancelled)
        #expect(AppSymbol.status(.added, reasons: []) == .extraLesson)
        #expect(AppSymbol.status(.modified, reasons: [.teacherChanged]) == .substitute)
        // The badge model and the symbol table agree.
        #expect(LessonStatusBadgeModel.make(status: .modified, reasons: [.timeChanged])?.symbolName
                == AppSymbol.timeChanged.rawValue)
        #expect(LessonStatusBadgeModel.make(status: .cancelled, reasons: [])?.symbolName == AppSymbol.cancelled.rawValue)
    }

    @Test func sharedModelsUseTheTable() {
        #expect(LessonFieldLine.room("214").symbolName == "mappin.and.ellipse")
        #expect(LessonBadges.taskSymbol == AppSymbol.task.rawValue)
        #expect(DayChangeDraft.Kind.cancelLesson.symbol == .cancelled)
        #expect(DayChangeDraft.Kind.shortDay.symbol == .timeChanged)
        #expect(AppSymbol.Tab.tasks == .task && AppSymbol.Tab.exams == .exam)
    }
}

@Suite("Time-format locale (D4 / H1)")
struct TimeFormatLocaleTests {
    @Test func systemIsTheDefault() {
        #expect(AppSettings(meta: EntityMeta(createdAt: .zero, updatedAt: .zero)).hourCycle == .auto)
        #expect(TimeFormatLocale.effectiveChoice(AppSettings(meta: EntityMeta(createdAt: .zero, updatedAt: .zero)).hourCycle) == .system)
        #expect(TimeFormatLocale.effectiveChoice(HourCycle(rawValue: "future")) == .system)   // newer app's value
        #expect(TimeFormatLocale.effectiveChoice(.h24) == .h24)
    }

    @Test func systemKeepsTheDeviceClock() {
        let us = Locale(identifier: "en_US")
        #expect(TimeFormatLocale.locale(system: us, setting: .auto) == us)
        #expect(TimeFormatLocale.locale(system: us, setting: HourCycle(rawValue: "x")) == us)
    }

    @Test func settingOverridesTheHourCycleOnly() {
        let us = TimeFormatLocale.locale(system: Locale(identifier: "en_US"), setting: .h24)
        #expect(us.hourCycle == .zeroToTwentyThree)
        #expect(us.language.languageCode?.identifier == "en")
        #expect(us.region?.identifier == "US")
        let sk = TimeFormatLocale.locale(system: Locale(identifier: "sk_SK"), setting: .h12)
        #expect(sk.hourCycle == .oneToTwelve)
        #expect(sk.language.languageCode?.identifier == "sk")
    }

    @Test(arguments: ["sr-Latn_RS", "zh-Hans_CN", "pt_BR", "en_GB", "sk_SK", "en_US@fw=mon"])
    func overrideKeepsScriptRegionAndWeekStart(identifier: String) {
        let system = Locale(identifier: identifier)
        for setting in [HourCycle.h12, .h24] {
            let result = TimeFormatLocale.locale(system: system, setting: setting)
            #expect(result.hourCycle == (setting == .h24 ? .zeroToTwentyThree : .oneToTwelve), "\(identifier)")
            #expect(result.language.languageCode == system.language.languageCode, "\(identifier) language")
            #expect(result.language.script == system.language.script, "\(identifier) script")
            #expect(result.region == system.region, "\(identifier) region")
            #expect(result.firstDayOfWeek == system.firstDayOfWeek, "\(identifier) first weekday")
            #expect(result.calendar.identifier == system.calendar.identifier, "\(identifier) calendar")
        }
    }

    @Test func scriptSurvivesInFormattedText() {
        let zone = TimeZone(identifier: "Europe/Belgrade")!
        let latin = TimetableFormatter(locale: Locale(identifier: "sr-Latn_RS"), hourCycle: .h24, timeZone: zone)
        let date = LocalDate(year: 2026, month: 10, day: 13)!
        let text = latin.contextualDate(date, today: date)
        // Latin script ("utorak"), not Cyrillic ("уторак").
        #expect(text.unicodeScalars.allSatisfy { $0.value < 0x0400 || $0.value > 0x04FF }, "\(text)")
    }

    @Test func formatterAndInjectedLocaleAgree() {
        let zone = TimeZone(identifier: "Europe/Bratislava")!
        let formatter = TimetableFormatter(locale: Locale(identifier: "en_US"), hourCycle: .h24, timeZone: zone)
        #expect(formatter.locale == TimeFormatLocale.locale(system: Locale(identifier: "en_US"), setting: .h24))
        #expect(formatter.time(LocalTime(hour: 17, minute: 0)!) == "17:00")
    }
}

@Suite("Validation visibility (M5)")
struct ValidationVisibilityTests {
    @Test func hintsShowFromTheStartErrorsAfterTheFirstEdit() {
        // Untouched editor: the hint explains the disabled Save; no red error yet.
        #expect(ValidationVisibility.isShown(.hint, hasEdited: false))
        #expect(!ValidationVisibility.isShown(.error, hasEdited: false))
        // After the first edit: both.
        #expect(ValidationVisibility.isShown(.hint, hasEdited: true))
        #expect(ValidationVisibility.isShown(.error, hasEdited: true))
        #expect(!ValidationVisibility.errorsVisible(hasEdited: false))
        #expect(ValidationVisibility.errorsVisible(hasEdited: true))
    }

    @Test func dayChangeMissingChoicesAreHints() {
        #expect(DayChangeDraft.Issue.nothingChanged.severity == .hint)
        #expect(DayChangeDraft.Issue.noLesson.severity == .hint)
        #expect(DayChangeDraft.Issue.noFollowDay.severity == .hint)
        #expect(DayChangeDraft.Issue.noSubject.severity == .hint)
        #expect(DayChangeDraft.Issue.noBellSchedule.severity == .error)
        // "Enter at least one change." is never red on a form nobody touched.
        #expect(!(DayChangeDraft.Issue.nothingChanged.severity == .error
                  && ValidationVisibility.isShown(.error, hasEdited: false)))
    }
}

@Suite("Dates without the current year (L1)")
struct ContextualDateTests {
    private let zone = TimeZone(identifier: "Europe/Bratislava")!
    private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
    private func formatter(_ id: String) -> TimetableFormatter {
        TimetableFormatter(locale: Locale(identifier: id), hourCycle: .auto, timeZone: zone)
    }

    @Test func currentYearIsOmitted() {
        let text = formatter("en_US").contextualDate(date(2026, 10, 13), today: date(2026, 10, 13))
        #expect(text.contains("Tuesday") && text.contains("October") && text.contains("13"))
        #expect(!text.contains("2026"))
    }

    @Test func otherYearIsShown() {
        let text = formatter("en_US").contextualDate(date(2027, 1, 4), today: date(2026, 12, 31))
        #expect(text.contains("2027") && text.contains("January") && text.contains("Monday"))
    }

    @Test func yearBoundaryBothWays() {
        let f = formatter("en_US")
        // New Year's Eve seen from New Year's Day: last year's date carries its year.
        #expect(f.contextualDate(date(2026, 12, 31), today: date(2027, 1, 1)).contains("2026"))
        // 1 January seen from 1 January: same year, no year.
        #expect(!f.contextualDate(date(2027, 1, 1), today: date(2027, 1, 1)).contains("2027"))
        // Same day of the year, different years.
        #expect(f.contextualDate(date(2026, 3, 1), today: date(2027, 3, 1), style: .dayMonth).contains("2026"))
    }

    @Test func stylesAndLocales() {
        let sk = formatter("sk_SK").contextualDate(date(2026, 10, 13), today: date(2026, 10, 1))
        #expect(sk.contains("utorok") && !sk.contains("2026"))
        let short = formatter("en_US").contextualDate(date(2026, 10, 13), today: date(2026, 1, 1), style: .abbreviated)
        #expect(short.contains("Tue") && short.contains("Oct") && !short.contains("Tuesday"))
        let dayMonth = formatter("de_DE").contextualDate(date(2026, 10, 13), today: date(2026, 5, 5), style: .dayMonth)
        #expect(dayMonth.contains("13") && !dayMonth.contains("Dienstag") && !dayMonth.contains("2026"))
    }
}
