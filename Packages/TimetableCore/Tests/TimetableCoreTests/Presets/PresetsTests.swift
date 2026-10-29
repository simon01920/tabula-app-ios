import Foundation
import Testing
@testable import TimetableCore

@Suite("Profile presets (PRODUCT.md table)")
struct ProfilePresetTests {
    /// Parses the "Profile presets" table of PRODUCT.md and checks every cell against the preset data, so
    /// an edit to either side fails this test.
    @Test func matchesProductMdTableCellByCell() throws {
        let product = try RepositoryFile.text("docs/specs/PRODUCT.md")
        let rows = product.split(whereSeparator: \.isNewline).map(String.init)
            .drop { !$0.hasPrefix("### Profile presets") }.dropFirst()
            .drop { !$0.hasPrefix("|") }
            .prefix { $0.hasPrefix("|") }
            .map { $0.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) } }
        guard let header = rows.first, header.count == 5 else {
            Issue.record("Profile presets table not found or malformed")
            return
        }
        let columns: [UserProfile] = header.dropFirst().map {
            switch $0 {
            case "Elementary": return .elementary
            case "Secondary": return .secondary
            case "University": return .university
            default: return .other
            }
        }
        #expect(columns == [.elementary, .secondary, .university, .other])
        var table: [String: [String]] = [:]
        for row in rows.dropFirst() where row.count == 5 && !row[0].hasPrefix("-") { table[row[0]] = Array(row.dropFirst()) }
        #expect(Set(table.keys) == ["Time structure", "Fields on", "Rotation prompt", "Default view", "Exams", "Terminology"])

        let fieldNames: [String: LessonField] = ["Room": .room, "Teacher": .teacher, "Bring": .bringList, "Notes": .notes,
                                                 "Building/Faculty": .building, "Type": .lessonType]
        for (index, profile) in columns.enumerated() {
            let preset = ProfilePreset.for(profile)
            switch table["Time structure"]?[index] ?? "" {
            case "Bell schedule, 45-min periods":
                guard case .bellSchedule(let template)? = preset.timeStructure else { Issue.record("\(profile)"); break }
                #expect(template.lessonMinutes == 45)
            case "Free-form, 90-min default blocks": #expect(preset.timeStructure == .freeForm(defaultDurationMinutes: 90))
            case "Ask": #expect(preset.timeStructure == nil)
            case let other: Issue.record("unmapped time structure '\(other)'")
            }
            let fieldsCell = table["Fields on"]?[index] ?? ""
            let fields: Set<LessonField> = fieldsCell == "All off" ? [] :
                Set(fieldsCell.components(separatedBy: ", ").compactMap { fieldNames[$0] })
            #expect(fieldsCell == "All off" || fields.count == fieldsCell.components(separatedBy: ", ").count, "\(fieldsCell)")
            #expect(preset.visibleFields == fields, "\(profile)")
            let rotation: [String: ProfilePreset.RotationPrompt] = ["Light": .light, "Yes": .standard,
                                                                    "Yes + semester range + odd/even": .extended, "Ask": .ask]
            #expect(rotation[table["Rotation prompt"]?[index] ?? ""] == preset.rotationPrompt, "\(profile)")
            let views: [String: TimetableViewKind] = ["Big vertical tiles": .tiles, "Grid": .grid, "Week time-blocks": .timeBlocks]
            #expect(views[table["Default view"]?[index] ?? ""] == preset.defaultView, "\(profile)")
            let exams: [String: ProfilePreset.ExamProminence] = ["Simple": .simple, "Prominent": .prominent,
                                                                 "Prominent + exam period": .prominentWithExamPeriod]
            #expect(exams[table["Exams"]?[index] ?? ""] == preset.examProminence, "\(profile)")
            let terms: [String: ProfilePreset.Terminology] = ["Lesson": .lesson, "Class/Lecture": .classLecture]
            #expect(terms[table["Terminology"]?[index] ?? ""] == preset.terminology, "\(profile)")
        }
    }

    @Test func timeStructureRow() {
        // Elementary/Secondary: bell schedule, 45-min periods · University: free-form 90 · Other: Ask.
        for profile in [UserProfile.elementary, .secondary] {
            guard case .bellSchedule(let template)? = ProfilePreset.for(profile).timeStructure else {
                Issue.record("\(profile) must use a bell schedule")
                continue
            }
            #expect(template.lessonMinutes == 45)
        }
        #expect(ProfilePreset.for(.university).timeStructure == .freeForm(defaultDurationMinutes: 90))
        #expect(ProfilePreset.for(.other).timeStructure == nil)
    }

    @Test func fieldsRow() {
        #expect(ProfilePreset.for(.elementary).visibleFields == [.room, .teacher, .bringList])
        #expect(ProfilePreset.for(.secondary).visibleFields == [.room, .teacher, .notes])
        #expect(ProfilePreset.for(.university).visibleFields == [.building, .room, .teacher, .lessonType, .notes])
        #expect(ProfilePreset.for(.other).visibleFields == [.room, .teacher])
    }

    @Test func rotationViewExamsTerminologyRows() {
        let expected: [UserProfile: (ProfilePreset.RotationPrompt, TimetableViewKind, ProfilePreset.ExamProminence, String)] = [
            .elementary: (.light, .tiles, .simple, "terminology.lesson"),
            .secondary: (.standard, .grid, .prominent, "terminology.lesson"),
            .university: (.extended, .timeBlocks, .prominentWithExamPeriod, "terminology.classLecture"),
            .other: (.ask, .grid, .simple, "terminology.lesson"),
        ]
        for profile in UserProfile.knownValues {
            let preset = ProfilePreset.for(profile)
            let row = expected[profile]!
            #expect(preset.profile == profile)
            #expect(preset.rotationPrompt == row.0, "\(profile)")
            #expect(preset.defaultView == row.1, "\(profile)")
            #expect(preset.examProminence == row.2, "\(profile)")
            #expect(preset.terminologyKey == row.3, "\(profile)")
            #expect(preset.enabledDays == Weekday.workweek)
        }
    }

    @Test func noPresetRuleEverUsesTheAlarmTier() {
        for profile in UserProfile.knownValues {
            let rules = ProfilePreset.for(profile).reminderRules
            #expect(!rules.isEmpty)
            #expect(rules.allSatisfy { $0.tier != .alarm }, "\(profile)")
            #expect(rules.allSatisfy { !$0.offsets.isEmpty })
            #expect(Set(rules.map(\.target)).count == rules.count, "one rule per target in \(profile)")
        }
    }

    @Test func timeSensitivePresetsHaveShortLeadTimes() {
        // The planner downgrades Time Sensitive reminders with lead > 60 min; presets should not rely on that.
        for profile in UserProfile.knownValues {
            for rule in ProfilePreset.for(profile).reminderRules where rule.tier == .timeSensitive {
                for offset in rule.offsets {
                    guard case .minutesBefore(let minutes) = offset else {
                        Issue.record("\(profile) \(rule.target): time-sensitive rule with a day offset")
                        continue
                    }
                    #expect(minutes <= 60)
                }
            }
        }
    }

    @Test func materialisedRulesArePresetOrigin() {
        let preset = ProfilePreset.for(.secondary).reminderRules[0]
        let rule = preset.makeRule(id: ReminderRule.ID(UUID()), meta: Fixture.meta())
        #expect(rule.origin == .preset && rule.isEnabled == preset.isEnabled && rule.tier == preset.tier)
        #expect(!preset.makeRule(id: ReminderRule.ID(UUID()), meta: Fixture.meta(), isEnabled: false).isEnabled)
    }
}

@Suite("BellScheduleTemplate")
struct BellScheduleTemplateTests {
    @Test func secondaryTemplateTimes() {
        let times = BellScheduleTemplate.secondary.lessonTimes()
        #expect(times.count == 8)
        let rendered = times.map { "\($0.start)-\($0.end)" }
        #expect(rendered == ["08:00-08:45", "08:55-09:40", "10:00-10:45", "10:55-11:40",
                             "11:50-12:35", "12:45-13:30", "13:40-14:25", "14:35-15:20"])
        #expect(BellScheduleTemplate.elementary.lessonTimes().count == 6)
    }

    @Test func breakArrayRepeatsLastValueAndHandlesEmpty() {
        let template = BellScheduleTemplate(firstStart: Fixture.time("07:00"), lessonMinutes: 50, breakMinutes: [5, 15], count: 4)
        #expect(template.breakAfter(lesson: 0) == 5 && template.breakAfter(lesson: 1) == 15 && template.breakAfter(lesson: 5) == 15)
        #expect(template.lessonTimes().map(\.start) == ["07:00", "07:55", "09:00", "10:05"].map(Fixture.time))
        let noBreaks = BellScheduleTemplate(firstStart: Fixture.time("08:00"), lessonMinutes: 60, breakMinutes: [], count: 3)
        #expect(noBreaks.lessonTimes().map(\.end) == ["09:00", "10:00", "11:00"].map(Fixture.time))
    }

    @Test func truncatesBeforeMidnightAndRejectsNonsense() {
        let late = BellScheduleTemplate(firstStart: Fixture.time("21:00"), lessonMinutes: 90, breakMinutes: [15], count: 5)
        #expect(late.lessonTimes().map { "\($0.start)-\($0.end)" } == ["21:00-22:30"])
        #expect(BellScheduleTemplate(firstStart: .midnight, lessonMinutes: 0, breakMinutes: [], count: 3).lessonTimes().isEmpty)
        #expect(BellScheduleTemplate(firstStart: .midnight, lessonMinutes: 45, breakMinutes: [-5], count: 3).lessonTimes().isEmpty)
        #expect(BellScheduleTemplate(firstStart: .midnight, lessonMinutes: 45, breakMinutes: [], count: 0).lessonTimes().isEmpty)
    }

    @Test func makesLessonPeriodsWithFreshIDs() {
        var ids = SequentialIDGenerator()
        let periods = BellScheduleTemplate.elementary.makePeriods(ids: &ids)
        #expect(periods.count == 6 && Set(periods.map(\.id)).count == 6)
        #expect(periods.allSatisfy { $0.kind == .lesson && $0.label == nil && $0.durationMinutes == 45 })
    }
}

@Suite("OnboardingBuilder")
struct OnboardingBuilderTests {
    private func answers(_ profile: UserProfile) -> OnboardingAnswers {
        OnboardingAnswers(profile: profile, timetableName: "School", bellScheduleName: "Normal day")
    }

    private func build(_ answers: OnboardingAnswers, namespace: UInt32 = 1) -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: namespace)
        var clock = TestClock()
        return OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: Fixture.now)
    }

    @Test(arguments: UserProfile.knownValues)
    func producesValidDatabaseForEveryProfile(profile: UserProfile) {
        let db = build(answers(profile))
        let problems = db.validate().filter { $0.severity != .info }
        #expect(problems.isEmpty, "\(problems)")
        #expect(db.validate().allSatisfy { $0.code == .emptyScheduleDay })   // no lessons yet
        #expect(db.timetables.count == 1)
        #expect(db.settings.activeTimetableID == db.timetables[0].id)
        #expect(db.settings.profile == profile)
        #expect(db.settings.onboardingCompletedAt == Fixture.now)
        #expect(db.settings.id == AppSettings.singletonID)
        #expect(db.reminderRules.count == ProfilePreset.for(profile).reminderRules.count)
        #expect(db.reminderRules.allSatisfy { $0.origin == .preset && $0.tier != .alarm })
        let preset = ProfilePreset.for(profile)
        #expect(db.timetables[0].fieldVisibility.visibleFields == preset.visibleFields)
        #expect(db.timetables[0].defaultView == preset.defaultView)
    }

    @Test func timeStructureFollowsPresetOrFallback() {
        let university = build(answers(.university))
        #expect(university.bellSchedules.isEmpty)
        #expect(university.timetables[0].timeStructure == .freeForm(defaultDurationMinutes: 90))
        let secondary = build(answers(.secondary))
        #expect(secondary.bellSchedules.count == 1 && secondary.bellSchedules[0].periods.count == 8)
        #expect(secondary.bellSchedules[0].name == "Normal day")
        #expect(secondary.timetables[0].timeStructure == .bellSchedule(defaultID: secondary.bellSchedules[0].id, perWeekday: [:]))
        let other = build(answers(.other))   // "Ask" without an answer → secondary template
        #expect(other.bellSchedules.count == 1 && other.bellSchedules[0].periods.count == 8)
    }

    @Test func answersOverridePresets() {
        var custom = answers(.university)
        custom.timeStructure = .bellSchedule(BellScheduleTemplate(firstStart: Fixture.time("07:30"), lessonMinutes: 90,
                                                                  breakMinutes: [15], count: 5))
        custom.visibleFields = [.room]
        custom.enabledDays = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        custom.defaultView = .agenda
        custom.rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        custom.term = .init(name: "Winter semester", range: LocalDateRange(start: Fixture.date("2026-09-21"), end: Fixture.date("2027-02-14")))
        custom.enabledReminderTargets = [.exam]
        custom.weekStartOverride = .sunday
        custom.hourCycle = .h12
        custom.timeZoneMode = .fixed(identifier: "Europe/Bratislava")
        custom.palettePackID = .pastel
        custom.timetableEmoji = "🎓"
        let db = build(custom)
        let timetable = db.timetables[0]
        #expect(db.bellSchedules[0].periods.count == 5)
        #expect(timetable.fieldVisibility.visibleFields == [.room])
        #expect(timetable.enabledDays.count == 6 && timetable.defaultView == .agenda && timetable.emoji == "🎓")
        #expect(timetable.rotation == custom.rotation)
        #expect(db.terms.count == 1 && db.terms[0].name == "Winter semester" && db.terms[0].timetableID == timetable.id)
        #expect(db.reminderRules.filter(\.isEnabled).map(\.target) == [.exam])
        #expect(db.settings.weekStartOverride == .sunday && db.settings.hourCycle == .h12 && db.settings.palettePackID == .pastel)
        #expect(db.settings.timeZoneMode == .fixed(identifier: "Europe/Bratislava"))
        #expect(db.validate().filter { $0.severity != .info }.isEmpty)
    }

    @Test func isDeterministic() throws {
        let a = try build(answers(.secondary)).encoded()
        let b = try build(answers(.secondary)).encoded()
        #expect(a == b)
        let c = try build(answers(.secondary), namespace: 2).encoded()
        #expect(a != c)
    }

    @Test func timestampsAreStrictlyIncreasing() {
        let db = build(answers(.elementary))
        var stamps = [db.settings.meta.updatedAt] + db.timetables.map(\.meta.createdAt)
        stamps += db.bellSchedules.map(\.meta.createdAt) + db.reminderRules.map(\.meta.createdAt)
        #expect(Set(stamps).count == stamps.count)
    }

    /// Settings start from the untouched defaults (`createdAt == .zero`); only answers that differ from a default
    /// get a field clock — exactly what `MutationStamper` writes for the same edit (DOMAIN_MODEL §2.2).
    @Test(arguments: [false, true])
    func settingsCarryClocksOnlyForNonDefaultAnswers(customised: Bool) throws {
        var custom = answers(.other)
        if customised {
            custom.hourCycle = .h12
            custom.palettePackID = .ocean
            custom.weekStartOverride = .monday
        }
        var ids = SequentialIDGenerator(namespace: 1)
        var clock = TestClock()
        let db = OnboardingBuilder.makeInitialDatabase(answers: custom, ids: &ids, clock: &clock, now: Fixture.now)
        let settings = db.settings
        #expect(settings.meta.createdAt == .zero)
        var expected: Set<String> = ["onboardingCompletedAt", "activeTimetableID"]
        if customised { expected.formUnion(["hourCycle", "palettePackID", "weekStartOverride"]) }
        #expect(Set(settings.meta.fieldClocks.keys) == expected)
        #expect(settings.meta.fieldClocks.values.allSatisfy { $0 == settings.meta.updatedAt })

        var replay = TestClock()
        var draft = settings
        draft.meta = Fixture.meta()
        let viaStamper = try MutationStamper.stamp(old: nil, new: draft, clock: &replay, now: Fixture.now)
        #expect(viaStamper == settings)
    }
}

@Suite("SampleData")
struct SampleDataTests {
    private func onboard(_ profile: UserProfile, rotation: RotationScheme = .none) -> (TabulaDatabase, SequentialIDGenerator, TestClock) {
        var ids = SequentialIDGenerator(namespace: 7)
        var clock = TestClock()
        let answers = OnboardingAnswers(profile: profile, timetableName: "School", bellScheduleName: "Normal", rotation: rotation)
        let db = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: Fixture.now)
        return (db, ids, clock)
    }

    private func sample(_ profile: UserProfile, rotation: RotationScheme = .none,
                        localize: (LocalizedText) -> String = { "⟨\($0.key)⟩" }) -> TabulaDatabase {
        var (db, ids, clock) = onboard(profile, rotation: rotation)
        let content = SampleData.make(profile: profile, timetable: db.timetables[0], bellSchedule: db.bellSchedules.first,
                                      today: Fixture.date("2026-10-06"), localize: localize, ids: &ids, clock: &clock,
                                      now: Fixture.now)
        db = content.merged(into: db)
        return db
    }

    @Test(arguments: UserProfile.knownValues)
    func sampleDatabaseIsCleanForEveryProfile(profile: UserProfile) {
        let db = sample(profile)
        #expect(db.validate().isEmpty, "\(db.validate())")
        #expect(!db.subjects.isEmpty && !db.lessons.isEmpty && db.tasks.count == 1 && db.exams.count == 1)
        #expect(db.subjects.allSatisfy { $0.name.hasPrefix("⟨sample.subject.") })
        #expect(db.subjects.allSatisfy { if case .key(let key)? = $0.colorName { return key.hasPrefix("palette.classic.color.") } else { return false } })
    }

    @Test func dayCycleTimetablesGetCycleDayLessons() {
        let rotation = RotationScheme.dayCycle(DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01")))
        let db = sample(.secondary, rotation: rotation)
        #expect(db.validate().isEmpty, "\(db.validate())")
        #expect(Set(db.lessons.map(\.occurrence.day)) == Set((1...6).map(DayKey.cycleDay)))
    }

    @Test func universitySampleUsesTimesAndTypes() {
        let db = sample(.university)
        #expect(db.lessons.allSatisfy { if case .time = $0.slot { return true } else { return false } })
        #expect(db.lessons.allSatisfy { $0.lessonType != nil })
        #expect(db.lessons.contains { $0.slot == .time(start: Fixture.time("08:00"), end: Fixture.time("09:30")) })
        #expect(db.tasks[0].kind == .assignment)
    }

    @Test func datesAndBringListFollowTheCalendar() {
        let db = sample(.elementary)
        // 2026-10-06 is a Tuesday: homework due the next school day (Wednesday), exam one week later (Tuesday).
        #expect(db.tasks[0].due == .date(Fixture.date("2026-10-07")))
        #expect(db.exams[0].date == Fixture.date("2026-10-13"))
        #expect(db.lessons.contains { $0.bringList == ["⟨sample.bring.sportsKit⟩"] })
        #expect(SampleData.nextSchoolDay(after: Fixture.date("2026-10-09"), in: Weekday.workweek) == Fixture.date("2026-10-12"))
    }

    @Test func localizerReceivesOnlyDeclaredKeys() {
        var requested = Set<String>()
        for profile in UserProfile.knownValues {
            _ = sample(profile) { requested.insert($0.key); return $0.key }
        }
        #expect(requested.isSubset(of: Set(SampleData.allKeys)))
        #expect(requested == Set(SampleData.allKeys))
    }

    @Test func isDeterministic() throws {
        #expect(try sample(.secondary).encoded() == sample(.secondary).encoded())
    }
}
