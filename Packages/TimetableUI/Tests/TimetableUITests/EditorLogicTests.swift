import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let now = Date(timeIntervalSince1970: 1_791_879_600)

private func apply(_ mutation: DatabaseMutation, to database: TabulaDatabase) throws -> TabulaDatabase {
    var clock = HybridLogicalClock(node: 0xB3)
    clock.receive(database.latestTimestamp, now: now)
    return try mutation.apply(to: database, clock: &clock, now: now)
}

private func errors(_ database: TabulaDatabase) -> [ValidationIssue] {
    database.validate().filter { $0.severity == .error }
}

@Suite("Editor field rule and text")
struct EditorBasicsTests {
    /// D10 (UX overhaul): the display setting no longer removes fields from editors (EditorU5bTests has the details).
    @Test func everyFieldIsOfferedInEditors() {
        #expect(EditorFieldPolicy.editorFields == [.room, .building, .teacher, .lessonType, .notes, .bringList])
    }

    @Test func blankTextBecomesAbsent() {
        #expect(EditorText.trimmedOrNil("  \n") == nil)
        #expect(EditorText.trimmedOrNil(" 214 ") == "214")
        #expect(EditorText.cleanedList(["a", " ", " b "]) == ["a", "b"])
        #expect(EditorText.firstCharacter("🧪x") == "🧪")
        #expect(EditorText.firstCharacter("") == nil)
    }

    @Test func dateBridgeRoundTrips() throws {
        let date = try #require(LocalDate(year: 2026, month: 10, day: 15))
        let time = try #require(LocalTime(hour: 8, minute: 55)!)
        let instant = LocalDateBridge.instant(date, time)
        #expect(LocalDateBridge.time(instant) == time)
        #expect(LocalDateBridge.date(instant, fallback: .earliest) == date)
    }

    @Test func dayChoicesFollowTheRotation() {
        let scenario = SampleScenarios.secondary()
        let keys = DayChoices.keys(for: scenario.timetable, firstWeekday: .monday)
        #expect(keys == Weekday.workweek.sorted().map { DayKey.weekday($0) })
        var cycle = scenario.timetable
        cycle.rotation = .dayCycle(DayCycle(length: 3, anchorDate: .earliest))
        #expect(DayChoices.keys(for: cycle, firstWeekday: .monday) == [.cycleDay(1), .cycleDay(2), .cycleDay(3)])
        #expect(DayChoices.label(at: 2, in: ["A", " ", "C"]) == nil)
        #expect(DayChoices.label(at: 3, in: ["A", " ", "C"]) == "C")
    }
}

@Suite("Lesson draft")
struct LessonDraftTests {
    private let scenario = SampleScenarios.secondary()
    static let today = LocalDate(year: 2027, month: 2, day: 10)!

    private var existing: Lesson { scenario.database.lessons.first { !$0.isDeleted }! }

    @Test func roundTripOfUnchangedDraftEqualsTheLesson() throws {
        let timetable = scenario.timetable
        var visibility = timetable
        visibility.fieldVisibility = .all
        let draft = LessonDraft(lesson: existing, timetable: visibility, today: Self.today)
        let made = try #require(draft.makeLesson(in: visibility))
        var expected = existing
        expected.bringList = EditorText.cleanedList(existing.bringList)
        #expect(made == expected)
    }

    /// D10: a field hidden in summaries is still edited (and an untouched one keeps its value).
    @Test func fieldsHiddenInSummariesAreStillEdited() throws {
        var timetable = scenario.timetable
        timetable.fieldVisibility = FieldVisibility([.room])
        var lesson = existing
        lesson.teacher = "Mgr. X"
        lesson.notes = "keep me"
        var draft = LessonDraft(lesson: lesson, timetable: timetable, today: Self.today)
        draft.teacher = "changed while hidden"
        draft.room = "  301 "
        let made = try #require(draft.makeLesson(in: timetable))
        #expect(made.teacher == "changed while hidden")
        #expect(made.notes == "keep me")
        #expect(made.room == "301")
    }

    @Test func emptyEnabledFieldIsStoredAsAbsent() throws {
        var timetable = scenario.timetable
        timetable.fieldVisibility = .all
        var draft = LessonDraft(lesson: existing, timetable: timetable, today: Self.today)
        draft.room = "   "
        draft.bringList = ["", "  "]
        let made = try #require(draft.makeLesson(in: timetable))
        #expect(made.room == nil)
        #expect(made.bringList.isEmpty)
    }

    @Test func blockingIssues() {
        let timetable = scenario.timetable
        var draft = LessonDraft(lesson: existing, timetable: timetable, today: Self.today)
        draft.subjectID = nil
        #expect(draft.issues(in: timetable) == [.noSubject])
        #expect(draft.makeLesson(in: timetable) == nil)
        draft.subjectID = existing.subjectID
        draft.validityMode = .terms
        draft.termIDs = []
        #expect(draft.issues(in: timetable) == [.noTerms])
        draft.validityMode = .range
        draft.rangeEnd = draft.rangeStart.adding(days: -1)
        #expect(draft.issues(in: timetable) == [.emptyRange])
        draft.slot.setMode(.time, schedule: nil)
        draft.slot.end = draft.slot.start
        #expect(draft.slotIssues == [.endBeforeStart])
        #expect(!draft.canSave(in: timetable))
    }

    @Test func cycleWeeksOnlyForWeekRotation() throws {
        let timetable = scenario.timetable   // odd/even week rotation
        guard case .weekCycle(let cycle) = timetable.rotation else { Issue.record("expected week cycle"); return }
        var draft = LessonDraft(lesson: existing, timetable: timetable, today: Self.today)
        draft.cycleWeeks = [1]
        #expect(try #require(draft.makeLesson(in: timetable)).occurrence.cycleWeeks == [1])
        draft.cycleWeeks = Set(1...cycle.length)
        #expect(try #require(draft.makeLesson(in: timetable)).occurrence.cycleWeeks == nil)
        var plain = timetable
        plain.rotation = .none
        draft.cycleWeeks = [1]
        #expect(try #require(draft.makeLesson(in: plain)).occurrence.cycleWeeks == nil)
    }

    @Test func slotModeSwitchCarriesTimes() throws {
        let schedule = scenario.regularBell
        let periods = SlotDraft.lessonPeriods(of: schedule)
        var slot = SlotDraft(slot: .period(periods[1].id, span: 2))
        slot.setMode(.time, schedule: schedule)
        #expect(slot.start == periods[1].start)
        #expect(slot.end == periods[2].end)
        slot.setMode(.period, schedule: schedule)
        #expect(slot.periodID == periods[1].id)
        #expect(slot.span == 1)
        #expect(slot.maxSpan(in: schedule) == periods.count - 1)
    }

    @Test func newLessonUsesContextAndSubjectDefaults() throws {
        var timetable = scenario.timetable
        timetable.fieldVisibility = FieldVisibility([.room, .teacher])
        let subject = try #require(scenario.database.subjects.first { $0.defaultRoom != nil })
        let period = SlotDraft.lessonPeriods(of: scenario.regularBell)[2]
        let id = Lesson.ID(UUID())
        let draft = LessonDraft(newIn: timetable,
                                context: NewLessonContext(day: .weekday(.wednesday), slot: .period(period.id, span: 1)),
                                schedule: scenario.regularBell, subject: subject, firstWeekday: .monday, id: id, today: Self.today)
        #expect(draft.day == .weekday(.wednesday))
        #expect(draft.slot.periodID == period.id)
        #expect(draft.room == (subject.defaultRoom ?? ""))
        #expect(draft.building == (subject.defaultBuilding ?? ""))   // D10: prefilled even when hidden in summaries
        let made = try #require(draft.makeLesson(in: timetable))
        #expect(made.id == id)
        #expect(made.building == subject.defaultBuilding.flatMap(EditorText.trimmedOrNil))
    }

    @Test func savedNewLessonValidates() throws {
        let database = scenario.database
        let timetable = scenario.timetable
        let subject = database.subjects[0]
        let draft = LessonDraft(newIn: timetable, context: NewLessonContext(day: .weekday(.friday)),
                                schedule: scenario.regularBell, subject: subject, firstWeekday: .monday,
                                id: Lesson.ID(UUID()), today: Self.today)
        let lesson = try #require(draft.makeLesson(in: timetable))
        let stored = try apply(.upsert(lesson), to: database)
        #expect(errors(stored).isEmpty)
        #expect(stored.lessons.contains { $0.id == lesson.id })
    }

    @Test func conflictsAreReportedWithOtherSubjects() throws {
        let database = scenario.database
        let timetable = scenario.timetable
        let other = try #require(database.lessons.first { !$0.isDeleted && $0.occurrence.cycleWeeks == nil })
        var lesson = other
        lesson.id = Lesson.ID(UUID())
        lesson.subjectID = try #require(database.subjects.first { $0.id != other.subjectID }).id
        let conflicts = LessonConflicts.conflicts(for: lesson, in: database, context: scenario.context)
        #expect(!conflicts.isEmpty)
        let name = try #require(database.subjects.first { $0.id == other.subjectID }).name
        #expect(conflicts.contains { $0.otherSubjectNames.contains(name) })
        // A conflict never lists the lesson being edited itself.
        let own = LessonConflicts.conflicts(for: other, in: database, context: scenario.context)
        #expect(own.allSatisfy { !$0.otherSubjectNames.isEmpty })
        _ = timetable
    }
}

@Suite("Subject draft")
struct SubjectDraftTests {
    private let scenario = SampleScenarios.secondary()

    @Test func newSubjectPicksAFreePaletteColour() {
        let used = [PalettePack.classic.colors[0].value, PalettePack.classic.colors[1].value]
        let draft = SubjectDraft(newIn: scenario.timetable, pack: .classic, usedColors: used, id: Subject.ID(UUID()))
        #expect(draft.color == PalettePack.classic.colors[2].value)
        #expect(!draft.canSave)
        #expect(draft.issues == [.noName])
    }

    @Test func paletteColourStoresItsNameKey() throws {
        var draft = SubjectDraft(newIn: scenario.timetable, pack: .classic, usedColors: [], id: Subject.ID(UUID()))
        draft.name = "  Fyzika "
        draft.shortName = " "
        let subject = try #require(draft.makeSubject())
        #expect(subject.name == "Fyzika")
        #expect(subject.shortName == nil)
        #expect(subject.colorName == .key(PalettePack.classic.colors[0].nameKey))
    }

    @Test func customColourDropsThePaletteName() throws {
        var subject = scenario.database.subjects[0]
        subject.colorName = .key("palette.classic.color.red")
        var draft = SubjectDraft(subject: subject)
        draft.colorChoice = .custom(try #require(ColorValue(hex: "#123456")))
        let made = try #require(draft.makeSubject())
        #expect(made.colorName == nil)
        #expect(made.color.hexString.lowercased().contains("123456"))
    }

    @Test func existingPaletteColourIsRecognised() {
        let color = PalettePack.ocean.colors[3]
        #expect(SubjectDraft.choice(for: color.value) == .palette(pack: .ocean, colorID: color.id))
        let custom = ColorValue(red: 1, green: 2, blue: 3)
        #expect(SubjectDraft.choice(for: custom) == .custom(custom))
    }

    @Test func contrastWarningThresholdAndTileColours() {
        var draft = SubjectDraft(newIn: scenario.timetable, pack: .classic, usedColors: [], id: Subject.ID(UUID()))
        draft.colorChoice = .custom(ColorValue(red: 119, green: 119, blue: 119))   // worst case for black/white
        #expect(draft.contrastRatio >= 4.5)        // black/white always reach AA on opaque colours
        #expect(!draft.hasLowContrast)
        #expect(SubjectDraft.isLowContrast(4.4) && !SubjectDraft.isLowContrast(4.5))
        draft.colorChoice = .custom(.black)
        #expect(draft.tileTextColor == .white)
        #expect(draft.blendsIntoBackground(isDark: true) && !draft.blendsIntoBackground(isDark: false))  // black tile on a dark page
        draft.colorChoice = .custom(ColorValue(red: 255, green: 250, blue: 250))
        #expect(draft.blendsIntoBackground(isDark: false) && !draft.blendsIntoBackground(isDark: true) && draft.tileTextColor == .black)
        draft.colorChoice = .custom(ColorValue(red: 119, green: 119, blue: 119))
        #expect(!draft.blendsIntoBackground(isDark: false) && !draft.blendsIntoBackground(isDark: true))
        draft.colorChoice = .custom(ColorValue(red: 255, green: 221, blue: 0))     // yellow: outline in light only
        #expect(draft.blendsIntoBackground(isDark: false) == draft.tileStyle.needsOutline(isDark: false))
        #expect(!draft.blendsIntoBackground(isDark: true))
    }

    @Test func symbolKinds() {
        var draft = SubjectDraft(newIn: scenario.timetable, pack: .classic, usedColors: [], id: Subject.ID(UUID()))
        #expect(draft.symbol == nil)
        draft.symbolKind = .emoji
        draft.emoji = "🧪 lab"
        #expect(draft.symbol == .emoji("🧪"))
        draft.symbolKind = .systemImage
        draft.systemImage = " atom "
        #expect(draft.symbol == .systemImage("atom"))
        #expect(SubjectDraft.symbolSuggestions.count == Set(SubjectDraft.symbolSuggestions).count)
    }

    @Test func paletteColoursOfAllPacksMeetTheContrastBar() {
        // Documents the palette contract the editor warning relies on (preferredTextColor on shipped colours).
        for pack in PalettePack.all {
            for colour in pack.colors {
                #expect(Contrast.ratio(colour.textColor, colour.value) >= 3.0, "\(pack.id) \(colour.id)")
            }
        }
    }
}

@Suite("Bell schedule draft")
struct BellSetDraftTests {
    private let scenario = SampleScenarios.secondary()

    private func draft() -> BellSetDraft {
        BellSetDraft(timetable: scenario.timetable, schedules: scenario.database.bellSchedules,
                     defaultScheduleName: "Regular", ids: { BellSchedule.ID(UUID()) })
    }

    @Test func loadsDefaultAndVariants() {
        let draft = draft()
        #expect(draft.defaultEntry.id == scenario.regularBell.id)
        #expect(draft.defaultEntry.periods == scenario.regularBell.periods)
        #expect(!draft.hasBlockingIssues)
    }

    @Test func addPeriodAppendsAfterTheLastOne() {
        var draft = draft()
        let last = draft.defaultEntry.periods.max { $0.end < $1.end }!
        let id = Period.ID(UUID())
        draft.addPeriod(to: draft.defaultEntry.id, id: id)
        let added = draft.defaultEntry.periods.first { $0.id == id }!
        #expect(added.start == last.end.adding(minutes: 5))
        #expect(added.end == added.start.adding(minutes: 45))
    }

    @Test func overlapIsAWarningAndInvertedTimesBlock() {
        var draft = draft()
        var period = draft.defaultEntry.periods[1]
        period.start = draft.defaultEntry.periods[0].start
        draft.setPeriod(period, in: draft.defaultEntry.id)
        let issues = BellSetDraft.issues(of: draft.defaultEntry)
        #expect(issues[period.id] == .overlaps)
        #expect(draft.hasOverlaps)
        #expect(!draft.hasBlockingIssues)
        period.end = period.start
        draft.setPeriod(period, in: draft.defaultEntry.id)
        #expect(draft.hasBlockingIssues)
        #expect(BellSetDraft.issues(of: draft.defaultEntry)[period.id] == .endBeforeStart)
    }

    @Test func periodsUsedByLessonsCannotBeRemoved() throws {
        var draft = draft()
        let locked = BellSetDraft.lockedPeriods(lessons: scenario.database.lessons, timetableID: scenario.timetable.id)
        let used = try #require(locked.first)
        let count = draft.defaultEntry.periods.count
        draft.removePeriod(used, from: draft.defaultEntry.id, locked: locked)
        #expect(draft.defaultEntry.periods.count == count)
        let free = Period.ID(UUID())
        draft.addPeriod(to: draft.defaultEntry.id, id: free)
        draft.removePeriod(free, from: draft.defaultEntry.id, locked: locked)
        #expect(draft.defaultEntry.periods.count == count)
    }

    @Test func variantCopiesKeepPeriodIDsAndStoreValidly() throws {
        var draft = draft()
        let variantID = BellSchedule.ID(UUID())
        draft.addVariant(copying: draft.defaultEntry.id, weekdays: [.wednesday], name: "Wednesday", id: variantID)
        #expect(draft.variants.first?.periods.map(\.id) == draft.defaultEntry.periods.map(\.id))
        draft.assign([.thursday, .wednesday], to: variantID)
        #expect(draft.freeWeekdays(enabledDays: Weekday.workweek).count == 3)
        let stored = try draft.mutations(for: scenario.timetable).reduce(scenario.database) { try apply($1, to: $0) }
        #expect(errors(stored).isEmpty)
        let timetable = try #require(stored.timetables.first { $0.id == scenario.timetable.id })
        #expect(timetable.timeStructure.bellScheduleID(for: .wednesday) == variantID)
        #expect(timetable.timeStructure.bellScheduleID(for: .monday) == scenario.regularBell.id)
        // Remove the variant again: schedule is tombstoned and the timetable uses the default for every day.
        var next = BellSetDraft(timetable: timetable, schedules: stored.bellSchedules, defaultScheduleName: "x",
                                ids: { BellSchedule.ID(UUID()) })
        #expect(next.variants.contains { $0.id == variantID })
        next.removeVariant(variantID)
        let cleared = try next.mutations(for: timetable).reduce(stored) { try apply($1, to: $0) }
        #expect(errors(cleared).isEmpty)
        #expect(cleared.bellSchedules.first { $0.id == variantID }?.isDeleted == true)
    }

    @Test func weekdaysBelongToOneVariant() {
        var draft = draft()
        let a = BellSchedule.ID(UUID()), b = BellSchedule.ID(UUID())
        draft.addVariant(copying: draft.defaultEntry.id, weekdays: [.monday, .tuesday], name: "A", id: a)
        draft.addVariant(copying: draft.defaultEntry.id, weekdays: [.tuesday], name: "B", id: b)
        #expect(draft.variants.first { $0.id == a }?.weekdays == [.monday])
        #expect(draft.variants.first { $0.id == b }?.weekdays == [.tuesday])
    }
}

@Suite("Timetable draft")
struct TimetableDraftTests {
    private let scenario = SampleScenarios.secondary()
    private let today = LocalDate(year: 2026, month: 10, day: 13)!

    @Test func unchangedDraftReproducesTheTimetable() throws {
        let draft = TimetableDraft(timetable: scenario.timetable, today: today)
        let made = try #require(draft.makeTimetable(timeStructure: scenario.timetable.timeStructure))
        #expect(made == scenario.timetable)
    }

    @Test func rotationRoundTripsForAllKinds() throws {
        var draft = TimetableDraft(timetable: scenario.timetable, today: today)
        draft.rotationKind = .weekCycle
        draft.weekLength = 3
        draft.anchorKind = .referenceWeek
        draft.referenceDate = today
        draft.referenceWeek = 2
        draft.weekLabels = ["A", "B", "C"]
        guard case .weekCycle(let week) = draft.rotation else { Issue.record("week"); return }
        #expect(week.length == 3)
        #expect(week.anchor == .referenceWeek(date: today, cycleWeek: 2))
        #expect(week.labels == ["A", "B", "C"])
        draft.anchorKind = .continuousParity
        draft.parityOffset = 1
        guard case .weekCycle(let continuous) = draft.rotation else { Issue.record("week"); return }
        #expect(continuous.anchor == .isoWeekParity(policy: .continuous, offset: 1))
        draft.rotationKind = .dayCycle
        draft.dayLength = 6
        draft.dayLabels = ["", "", "", "", "", ""]
        guard case .dayCycle(let day) = draft.rotation else { Issue.record("day"); return }
        #expect(day.length == 6 && day.labels == nil && day.schoolDays == Weekday.workweek)
        draft.rotationKind = .none
        #expect(draft.rotation == .none)
    }

    @Test func blockingIssues() {
        var draft = TimetableDraft(timetable: scenario.timetable, today: today)
        draft.name = "  "
        draft.enabledDays = []
        draft.rotationKind = .dayCycle
        draft.daySchoolDays = []
        #expect(Set(draft.issues) == [.noName, .noDays, .noSchoolDays])
        #expect(draft.makeTimetable(timeStructure: scenario.timetable.timeStructure) == nil)
    }

    @Test func rotationFamilyAndMinimumLengthGuards() {
        #expect(TimetableDraft.isFamilyChange(from: .none, to: .dayCycle))
        #expect(!TimetableDraft.isFamilyChange(from: .none, to: .weekCycle))
        #expect(!TimetableDraft.isFamilyChange(from: .dayCycle, to: .dayCycle))
        #expect(TimetableDraft.canChangeRotationFamily(lessonCount: 0))
        #expect(!TimetableDraft.canChangeRotationFamily(lessonCount: 1))
        var lesson = scenario.database.lessons[0]
        lesson.occurrence = LessonOccurrenceRule(day: .weekday(.monday), cycleWeeks: [3])
        #expect(TimetableDraft.minimumWeekCycleLength(lessons: [lesson], timetableID: lesson.timetableID) == 3)
        lesson.occurrence = LessonOccurrenceRule(day: .cycleDay(5))
        #expect(TimetableDraft.minimumDayCycleLength(lessons: [lesson], timetableID: lesson.timetableID) == 5)
    }

    @Test func staleDraftDoesNotOverwriteABellScheduleEditedFromInsideTheEditor() throws {
        let opened = scenario.timetable
        guard case .bellSchedule(let defaultID, _) = opened.timeStructure else { Issue.record("bell"); return }
        // The editor opened with `opened`; the nested bell-schedule sheet then saved a Friday variant.
        var draft = TimetableDraft(timetable: opened, today: today)
        draft.name = "Renamed"
        var stored = opened
        let variant = BellSchedule.ID(UUID())
        stored.timeStructure = .bellSchedule(defaultID: defaultID, perWeekday: [.friday: variant])
        var ids = SequentialIDGenerator(namespace: 0xB4)
        let resolved = draft.resolveTimeStructure(existingSchedules: [], scheduleName: "x", ids: &ids, current: stored)
        #expect(resolved.structure == stored.timeStructure)
        #expect(resolved.extra.isEmpty)
        let made = try #require(draft.makeTimetable(timeStructure: resolved.structure, onto: stored))
        #expect(made.name == "Renamed")
        #expect(made.timeStructure.bellScheduleID(for: .friday) == variant)
        // Without `current` the stale copy would win (the old behaviour).
        let stale = try #require(draft.makeTimetable(timeStructure: draft.resolveTimeStructure(
            existingSchedules: [], scheduleName: "x", ids: &ids).structure))
        #expect(stale.timeStructure.bellScheduleID(for: .friday) != variant)
    }

    @Test func freeFormMinutesNotEditedHereKeepTheStoredValue() {
        var opened = scenario.timetable
        opened.timeStructure = .freeForm(defaultDurationMinutes: 50)
        let draft = TimetableDraft(timetable: opened, today: today)
        var stored = opened
        stored.timeStructure = .freeForm(defaultDurationMinutes: 70)
        var ids = SequentialIDGenerator(namespace: 0xB5)
        #expect(draft.resolveTimeStructure(existingSchedules: [], scheduleName: "x", ids: &ids, current: stored).structure
            == .freeForm(defaultDurationMinutes: 70))
    }

    @Test func countsLessonsThatNeedBellPeriods() {
        let id = scenario.timetable.id
        let lessons = scenario.database.lessons
        let periodBased = lessons.filter { lesson in
            if case .period = lesson.slot { return !lesson.isDeleted && lesson.timetableID == id }
            return false
        }.count
        #expect(TimetableDraft.periodLessonCount(lessons: lessons, timetableID: id) == periodBased)
        #expect(periodBased > 0)
        #expect(TimetableDraft.periodLessonCount(lessons: lessons, timetableID: Timetable.ID(UUID())) == 0)
    }

    @Test func switchingToBellScheduleCreatesADefaultOne() throws {
        var timetable = scenario.timetable
        timetable.timeStructure = .freeForm(defaultDurationMinutes: 50)
        var draft = TimetableDraft(timetable: timetable, today: today)
        #expect(draft.timeKind == .freeForm)
        draft.timeKind = .bellSchedule
        var ids = SequentialIDGenerator(namespace: 0xB3)
        let result = draft.resolveTimeStructure(existingSchedules: [], scheduleName: "Regular", ids: &ids)
        #expect(result.extra.count == 1)
        guard case .bellSchedule = result.structure else { Issue.record("expected bell schedule"); return }
        // Existing schedule is reused instead.
        let reused = draft.resolveTimeStructure(existingSchedules: [scenario.regularBell], scheduleName: "x", ids: &ids)
        #expect(reused.extra.isEmpty)
        #expect(reused.structure.bellScheduleID(for: .monday) == scenario.regularBell.id)
        draft.timeKind = .freeForm
        draft.freeMinutes = 9999
        #expect(draft.resolveTimeStructure(existingSchedules: [], scheduleName: "x", ids: &ids).structure
            == .freeForm(defaultDurationMinutes: 1439))
    }
}

@Suite("Day change draft")
struct DayChangeDraftTests {
    private let scenario = SampleScenarios.secondary()

    private func draft(lessonID: Lesson.ID? = nil) -> DayChangeDraft {
        DayChangeDraft(timetable: scenario.timetable, date: scenario.overrideDate, lessonID: lessonID,
                       schedule: scenario.regularBell, id: ScheduleOverride.ID(UUID()))
    }

    @Test func startsWithTheRightKind() {
        #expect(draft().kind == .cancelDay)
        #expect(draft(lessonID: scenario.database.lessons[0].id).kind == .changeLesson)
    }

    @Test func eachKindBuildsItsOverrideAndValidates() throws {
        let lesson = scenario.database.lessons.first { !$0.isDeleted }!
        let subject = scenario.database.subjects[1]
        var draft = draft(lessonID: lesson.id)
        draft.kind = .cancelLesson
        #expect(draft.makeOverride()?.change == .cancelLesson(lesson.id))
        draft.kind = .changeLesson
        #expect(draft.issues == [.nothingChanged])
        draft.room = " 301 "
        draft.teacher = "substitute"          // D10: every field is used whatever the display setting
        #expect(draft.makeOverride()?.change == .modifyLesson(lesson.id, LessonPatch(room: "301", teacher: "substitute")))
        draft.kind = .cancelDay
        draft.note = " Trip "
        #expect(draft.makeOverride()?.change == .cancelDay(note: "Trip"))
        draft.kind = .shortDay
        #expect(draft.issues == [.noBellSchedule])
        draft.bellScheduleID = scenario.shortBell.id
        #expect(draft.makeOverride()?.change == .useBellSchedule(scenario.shortBell.id))
        draft.kind = .followDay
        #expect(draft.issues == [.noFollowDay])
        draft.followDay = .weekday(.monday)
        #expect(draft.makeOverride()?.change == .followDay(.weekday(.monday), cycleWeek: nil))
        draft.kind = .extraLesson
        #expect(draft.issues == [.noSubject])
        draft.extraSubjectID = subject.id
        draft.extraRoom = "A1"
        let override = try #require(draft.makeOverride())
        guard case .addLesson(let oneOff) = override.change else { Issue.record("addLesson"); return }
        #expect(oneOff.subjectID == subject.id && oneOff.room == "A1" && oneOff.teacher == nil)
        let stored = try apply(.upsert(override), to: scenario.database)
        #expect(errors(stored).isEmpty)
    }
}

@Suite("Terms draft")
struct TermsDraftTests {
    private let scenario = SampleScenarios.secondary()

    @Test func addEditDeleteRoundTrip() throws {
        var draft = TermsDraft(timetableID: scenario.timetable.id, database: scenario.database)
        let start = LocalDate(year: 2027, month: 2, day: 1)!
        let termID = Term.ID(UUID())
        draft.addTerm(name: "Summer", start: start, id: termID)
        draft.addBreak(name: "Spring", kind: .vacation, start: start, id: CalendarBreak.ID(UUID()))
        #expect(draft.canSave)
        let stored = try draft.mutations().reduce(scenario.database) { try apply($1, to: $0) }
        #expect(errors(stored).isEmpty)
        #expect(stored.terms.contains { $0.id == termID && !$0.isDeleted })
        var next = TermsDraft(timetableID: scenario.timetable.id, database: stored)
        next.terms.removeAll { $0.id == termID }
        let removed = try next.mutations().reduce(stored) { try apply($1, to: $0) }
        #expect(removed.terms.first { $0.id == termID }?.isDeleted == true)
    }

    @Test func invalidRangesBlockAndUsedTermsAreLocked() throws {
        var draft = TermsDraft(timetableID: scenario.timetable.id, database: scenario.database)
        let start = LocalDate(year: 2027, month: 2, day: 1)!
        let id = Term.ID(UUID())
        draft.addTerm(name: "", start: start, id: id)
        draft.terms[draft.terms.count - 1].range = LocalDateRange(start: start, end: start.adding(days: -2))
        #expect(Set(draft.issues.map { "\($0)" }).count == 2)
        #expect(!draft.canSave)
        var lesson = scenario.database.lessons[0]
        lesson.validity = .terms([id])
        #expect(TermsDraft.lockedTerms(lessons: [lesson], timetableID: lesson.timetableID) == [id])
    }
}

@Suite("Timetable management")
struct TimetableManagementTests {
    private func twoTimetables() throws -> (database: TabulaDatabase, first: Timetable, second: Timetable) {
        let scenario = SampleScenarios.secondary()
        var ids = SequentialIDGenerator(namespace: 0xB3B3)
        let (mutation, id) = try #require(TimetableManagement.duplicateMutation(
            scenario.timetable.id, name: "Copy", in: scenario.database, ids: &ids))
        let database = try apply(mutation, to: scenario.database)
        return (database, scenario.timetable, try #require(database.timetables.first { $0.id == id }))
    }

    @Test func lastRemainingTimetableCannotBeDeleted() {
        let database = SampleScenarios.secondary().database
        let only = database.timetables[0]
        #expect(TimetableManagement.deletionGuard(only.id, in: database) == .lastRemaining)
        #expect(TimetableManagement.deleteMutation(only.id, in: database) == nil)
        #expect(TimetableManagement.deletionGuard(Timetable.ID(UUID()), in: database) == .notFound)
    }

    @Test func deletionGuardCountsOnlyLiveTimetables() throws {
        let (database, first, second) = try twoTimetables()
        #expect(TimetableManagement.deletionGuard(first.id, in: database) == .allowed)
        let afterFirst = try apply(try #require(TimetableManagement.deleteMutation(first.id, in: database)), to: database)
        #expect(TimetableManagement.deletionGuard(second.id, in: afterFirst) == .lastRemaining)
        #expect(TimetableManagement.deleteMutation(second.id, in: afterFirst) == nil)
    }

    @Test func duplicateIsAnIndependentValidCopy() throws {
        let (database, first, second) = try twoTimetables()
        #expect(errors(database).isEmpty)
        #expect(second.name == "Copy" && second.sortIndex > first.sortIndex)
        func live<T: DatabaseStoredEntity>(_ type: T.Type, _ id: Timetable.ID, _ key: (T) -> Timetable.ID?) -> Int {
            database[keyPath: T.collection].filter { !$0.isDeleted && key($0) == id }.count
        }
        #expect(live(Lesson.self, first.id) { $0.timetableID } == live(Lesson.self, second.id) { $0.timetableID })
        #expect(live(Subject.self, first.id) { $0.timetableID } == live(Subject.self, second.id) { $0.timetableID })
        #expect(live(ScheduleOverride.self, first.id) { $0.timetableID } == live(ScheduleOverride.self, second.id) { $0.timetableID })
        // Copies reference their own subjects/bell schedules only.
        let copiedSubjects = Set(database.subjects.filter { $0.timetableID == second.id }.map(\.id))
        for lesson in database.lessons where lesson.timetableID == second.id {
            #expect(copiedSubjects.contains(lesson.subjectID))
        }
        // The copy resolves the same lessons as the original.
        let scenario = SampleScenarios.secondary()
        let a = try #require(ScheduleResolver(database: database, timetableID: first.id, context: scenario.context))
        let b = try #require(ScheduleResolver(database: database, timetableID: second.id, context: scenario.context))
        let date = scenario.overrideDate
        #expect(a.day(date).entries.map(\.subject.name) == b.day(date).entries.map(\.subject.name))
        #expect(a.day(date).entries.map(\.startTime) == b.day(date).entries.map(\.startTime))
    }

    @Test func deleteRemovesEverythingOfOneTimetableAndKeepsTheOther() throws {
        var (database, first, second) = try twoTimetables()
        database.settings.activeTimetableID = second.id
        let impact = TimetableManagement.impact(of: second.id, in: database)
        #expect(impact.lessons > 0 && impact.subjects > 0 && impact.bellSchedules > 0)
        let result = try apply(try #require(TimetableManagement.deleteMutation(second.id, in: database)), to: database)
        #expect(errors(result).isEmpty)
        #expect(result.timetables.first { $0.id == second.id }?.isDeleted == true)
        #expect(result.lessons.filter { $0.timetableID == second.id }.allSatisfy { $0.isDeleted })
        #expect(result.lessons.filter { $0.timetableID == first.id && !$0.isDeleted }.count == impact.lessons)
        #expect(result.settings.activeTimetableID == first.id)   // active moved in the same batch
        #expect(ActiveTimetable.resolve(result)?.id == first.id)
        #expect(result.validate().filter { $0.severity == .warning && $0.code == .referencesDeletedEntity }.isEmpty)
    }

    @Test func deleteKeepsLinkedTasksAndExamsButDropsTheLink() throws {
        var (database, _, second) = try twoTimetables()
        let subject = try #require(database.subjects.first { $0.timetableID == second.id })
        var task = TaskItem(id: TaskItem.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "Homework",
                            subjectID: subject.id, timetableID: second.id)
        task.linkedLesson = LessonLink(lessonID: try #require(database.lessons.first { $0.timetableID == second.id }).id,
                                       date: SampleScenarios.secondary().overrideDate)
        database = try apply(.upsert(task), to: database)
        let result = try apply(try #require(TimetableManagement.deleteMutation(second.id, in: database)), to: database)
        let stored = try #require(result.tasks.first { $0.id == task.id })
        #expect(!stored.isDeleted)
        #expect(stored.timetableID == nil && stored.subjectID == nil && stored.linkedLesson == nil)
        #expect(result.validate().filter { $0.severity == .warning && $0.code == .referencesDeletedEntity }.isEmpty)
    }

    @Test func resetClearsLessonsAndTheirChangesButKeepsStructure() throws {
        let scenario = SampleScenarios.secondary()
        let database = scenario.database
        let id = scenario.timetable.id
        let preview = TimetableManagement.resetImpact(of: id, in: database)
        #expect(preview.lessons > 0)
        let result = try apply(TimetableManagement.resetMutation(id, in: database), to: database)
        #expect(result.lessons.filter { $0.timetableID == id && !$0.isDeleted }.isEmpty)
        #expect(result.timetables.first { $0.id == id }?.isDeleted == false)
        #expect(result.subjects.filter { !$0.isDeleted }.count == database.subjects.filter { !$0.isDeleted }.count)
        #expect(errors(result).isEmpty)
        #expect(result.validate().filter { $0.code == .referencesDeletedEntity }.isEmpty)
        #expect(ActiveTimetable.resolve(result)?.id == id)   // still a live timetable: the shell does not onboard
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: result) == .main)
    }

    @Test func reorderAndSetActive() throws {
        let (database, first, second) = try twoTimetables()
        let reordered = try apply(TimetableManagement.reorderMutation([second.id, first.id], in: database), to: database)
        #expect(ActiveTimetable.ordered(reordered).map(\.id) == [second.id, first.id])
        let active = try apply(TimetableManagement.setActiveMutation(second.id), to: reordered)
        #expect(ActiveTimetable.resolve(active)?.id == second.id)
    }

    @Test func addCreatesAValidTimetable() throws {
        let scenario = SampleScenarios.secondary()
        var ids = SequentialIDGenerator(namespace: 0xADD)
        for structure in [NewTimetableStructure.freeForm(minutes: 45),
                          .template(.secondary, scheduleName: "Regular"),
                          .copyBellSchedule(of: scenario.timetable.id, scheduleName: "Copy")] {
            let (mutation, id) = TimetableManagement.addMutation(name: "Sport", emoji: "⚽", structure: structure,
                                                                 like: scenario.timetable, in: scenario.database, ids: &ids)
            let result = try apply(mutation, to: scenario.database)
            #expect(errors(result).isEmpty)
            let added = try #require(result.timetables.first { $0.id == id })
            #expect(added.name == "Sport" && added.fieldVisibility == scenario.timetable.fieldVisibility)
            #expect(ActiveTimetable.ordered(result).last?.id == id)
        }
    }

    @Test func limitControlsAdding() {
        let database = SampleScenarios.secondary().database
        #expect(TimetableManagement.canAdd(to: database, limit: nil))
        #expect(TimetableManagement.canAdd(to: database, limit: 2))
        #expect(!TimetableManagement.canAdd(to: database, limit: 1))
    }

    @Test func deletingASubjectRemovesItsLessonsAndChanges() throws {
        let scenario = SampleScenarios.secondary()
        let database = scenario.database
        let subject = try #require(database.subjects.first { subject in
            database.lessons.contains { $0.subjectID == subject.id && !$0.isDeleted }
        })
        let impact = TimetableManagement.subjectImpact(of: subject.id, in: database)
        #expect(impact.lessons > 0)
        let result = try apply(TimetableManagement.deleteSubjectMutation(subject.id, in: database), to: database)
        #expect(result.subjects.first { $0.id == subject.id }?.isDeleted == true)
        #expect(result.lessons.filter { $0.subjectID == subject.id && !$0.isDeleted }.isEmpty)
        #expect(errors(result).isEmpty)
        #expect(result.validate().filter { $0.code == .referencesDeletedEntity }.isEmpty)
    }
}

@Suite("EditorLaunchTarget")
struct EditorLaunchTargetTests {
    let tt = Timetable.ID(UUID())

    @Test func nilContextIsNil() {
        #expect(EditorLaunchTarget(nil) == nil)
    }

    @Test func lessonAndSubjectAndDayChange() {
        let lesson = Lesson.ID(UUID())
        let date = LocalDate(year: 2026, month: 10, day: 13)!
        #expect(EditorLaunchTarget(EditorContext(timetableID: tt, target: .lesson(lesson))) == .editLesson(lesson, timetableID: tt))
        #expect(EditorLaunchTarget(EditorContext(timetableID: tt, target: .newSubject)) == .newSubject(timetableID: tt))
        #expect(EditorLaunchTarget(EditorContext(timetableID: tt, target: .dayChange(date: date, occurrence: nil, lessonID: lesson)))
                == .dayChange(date: date, lessonID: lesson, timetableID: tt))
    }

    @Test func newLessonCarriesDaySlotAndCycleWeek() {
        let period = Period.ID(UUID())
        let date = LocalDate(year: 2026, month: 10, day: 14)!
        let withPeriod = QuickAddTarget(timetableID: tt, date: date, dayKey: .weekday(.wednesday), cycleWeek: 2,
                                        periodID: period, lessonNumber: 3, start: LocalTime(hour: 9, minute: 0)!,
                                        end: LocalTime(hour: 9, minute: 45)!)
        #expect(EditorLaunchTarget(EditorContext(timetableID: tt, target: .newLesson(withPeriod)))
                == .newLesson(NewLessonContext(day: .weekday(.wednesday), slot: .period(period, span: 1), cycleWeek: 2), timetableID: tt))
        var free = withPeriod
        free.periodID = nil
        free.cycleWeek = nil
        #expect(EditorLaunchTarget(EditorContext(timetableID: tt, target: .newLesson(free)))
                == .newLesson(NewLessonContext(day: .weekday(.wednesday),
                                               slot: .time(start: LocalTime(hour: 9, minute: 0)!, end: LocalTime(hour: 9, minute: 45)!)),
                              timetableID: tt))
    }
}
