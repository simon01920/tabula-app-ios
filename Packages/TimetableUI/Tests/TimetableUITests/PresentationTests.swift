import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private func lesson(status: ResolvedLesson.Status = .scheduled, room: String? = "214", building: String? = nil,
                    teacher: String? = "Mgr. Horváth", type: LessonType? = nil, notes: String? = "  ",
                    bring: [String] = [], period: Int? = 2) -> ResolvedLesson {
    let date = LocalDate(year: 2026, month: 10, day: 13)!
    let subject = SubjectSummary(id: Subject.ID(UUID()), name: "Matematika", shortName: "MAT",
                                 color: PalettePack.classic.colors[0].value)
    return ResolvedLesson(id: OccurrenceID(rawValue: "x"), source: .lesson(Lesson.ID(UUID())), timetableID: Timetable.ID(UUID()),
                          date: date, subject: subject, startTime: LocalTime(hour: 8, minute: 55)!,
                          endTime: LocalTime(hour: 9, minute: 40)!, start: Date(), end: Date(),
                          periodNumber: period, room: room, building: building, teacher: teacher, lessonType: type,
                          notes: notes, bringList: bring, status: status)
}

@Suite("Lesson presentation")
struct LessonPresentationTests {
    private let renderer = LocalizedTextRenderer(
        formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .auto,
                                      timeZone: TimeZone(identifier: "Europe/Bratislava")!),
        lookup: EnglishCatalog.lookup)

    @Test func fieldRuleHidesDisabledAndEmptyFields() {
        let visibility = FieldVisibility([.room, .notes, .bringList])
        let fields = VisibleLessonFields(lesson: lesson(bring: ["kit", " "]), visibility: visibility)
        #expect(fields.room == "214")
        #expect(fields.teacher == nil)          // disabled
        #expect(fields.notes == nil)            // enabled but blank → absent
        #expect(fields.bringList == ["kit"])    // blank item dropped
        #expect(VisibleLessonFields(lesson: lesson(room: nil, notes: nil), visibility: FieldVisibility()).isEmpty)
    }

    @Test func statusBadges() {
        #expect(LessonStatusBadgeModel.make(status: .scheduled, reasons: []) == nil)
        #expect(LessonStatusBadgeModel.make(status: .cancelled, reasons: [])?.titleKey == "lesson.status.cancelled")
        #expect(LessonStatusBadgeModel.make(status: .added, reasons: [])?.symbolName == "plus.circle.fill")
        #expect(LessonStatusBadgeModel.make(status: .modified, reasons: [.roomChanged])?.titleKey == "schedule.change.roomChanged")
        #expect(LessonStatusBadgeModel.make(status: .modified, reasons: [.roomChanged, .teacherChanged])?.titleKey
                == "lesson.status.modified")
    }

    @Test func voiceOverSentence() {
        let visibility = FieldVisibility([.room, .teacher, .bringList])
        let label = LessonAccessibilityLabel.make(
            lesson: lesson(status: .modified, bring: ["kit", "water"]), visibility: visibility,
            reasons: [.roomChanged], renderer: renderer)
        #expect(label == "Matematika, period 2, 8:55 to 9:40, room 214, teacher Mgr. Horváth, bring kit and water, changed: Room changed")
    }

    @Test func voiceOverSentenceHonoursTheFieldRule() {
        let label = LessonAccessibilityLabel.make(lesson: lesson(status: .cancelled, period: nil), visibility: FieldVisibility(),
                                                  reasons: [], renderer: renderer)
        #expect(label == "Matematika, 8:55 to 9:40, canceled")
        let lecture = LessonAccessibilityLabel.parts(lesson: lesson(type: .lecture), visibility: FieldVisibility([.lessonType]),
                                                     reasons: [], renderer: renderer)
        #expect(lecture.last == "Lecture")
    }

    @Test func everyKeyTheUILayerUsesIsInTheCatalog() {
        var keys = ["a11y.separator", "a11y.lesson.period", "a11y.lesson.periodLabel", "a11y.lesson.time", "a11y.lesson.room",
                    "a11y.lesson.building", "a11y.lesson.teacher", "a11y.lesson.notes", "a11y.lesson.bring",
                    "a11y.lesson.cancelled", "a11y.lesson.added", "a11y.lesson.modified", "a11y.lesson.modifiedReasons",
                    "lesson.status.cancelled", "lesson.status.added", "lesson.status.modified"]
        keys += LessonType.knownValues.compactMap(VisibleLessonFields.nameKey(of:))
        let banners: [StoreBanner] = [.restoredFromBackup, .discardedIncompleteWrite, .readOnly(fileSchemaVersion: 2),
                                      .saveFailed, .changeRejected]
        keys += banners.flatMap { [$0.titleKey, $0.messageKey] }
        let problems: [StoreProblem] = [.unrecoverable, .newerVersion(fileSchemaVersion: 2), .other("")]
        keys += problems.flatMap { [$0.titleKey, $0.messageKey] }
        keys += ModificationReason.allCases.map(\.l10nKey)
        let missing = keys.filter { EnglishCatalog.values[$0] == nil }
        #expect(missing.isEmpty, "missing catalog keys: \(missing)")
    }
}

@Suite("LessonTileStyle")
struct LessonTileStyleTests {
    @Test func everyPaletteColourHasLegibleText() {
        for pack in PalettePack.all {
            for colour in pack.colors {
                let style = LessonTileStyle(color: colour.value)
                #expect(style.textContrast >= 4.5, "\(colour.nameKey)")
                #expect(style.foreground == .black || style.foreground == .white)
                // D4: a past (dimmed) tile keeps legible text in both appearances.
                for isDark in [false, true] {
                    let past = style.past(isDark: isDark)
                    #expect(past.textContrast >= 4.5, "\(colour.nameKey) past dark=\(isDark)")
                }
            }
        }
    }

    @Test func outlinesOnlyWhenTheTileMeltsIntoThePage() {
        let lemon = LessonTileStyle(color: ColorValue(hex: "#FDFFB6")!)
        #expect(lemon.needsOutline(isDark: false) && !lemon.needsOutline(isDark: true))
        let abyss = LessonTileStyle(color: ColorValue(hex: "#0B2545")!)
        #expect(!abyss.needsOutline(isDark: false) && abyss.needsOutline(isDark: true))
        let red = LessonTileStyle(color: ColorValue(hex: "#E53935")!)
        #expect(!red.needsOutline(isDark: false) && !red.needsOutline(isDark: true))
    }

    @Test func translucentColoursAreCompositedFirst() {
        let style = LessonTileStyle(color: ColorValue(red: 0, green: 0, blue: 0, alpha: 0))
        #expect(style.background == .white && style.foreground == .black)
        #expect(RGBA(ColorValue(red: 255, green: 0, blue: 51, alpha: 255)) == RGBA(ColorValue(hex: "#FF0033")!))
        #expect(RGBA(ColorValue(hex: "#FF000080")!).opacity == 128.0 / 255)
    }

    @Test func appearanceMapping() {
        #expect(AppearancePreference(.dark) == .dark)
        #expect(AppearancePreference(.auto) == .system)
        #expect(AppearancePreference(Appearance(rawValue: "sepia")) == .system)
    }
}
