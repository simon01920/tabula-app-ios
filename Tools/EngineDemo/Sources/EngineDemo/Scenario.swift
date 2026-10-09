import Foundation
import TimetableCore
import TimetableUI

/// A fixed, deterministic sample scenario (data: `TimetableUI.SampleScenarios.secondary()`, shared with the app's
/// `-TabulaSeed secondary`) evaluated with the public `TimetableCore` API only:
/// a Slovak secondary school (gymnázium) with odd/even (A/B) weeks in Europe/Bratislava, evaluated at a fixed
/// "now" (Tue 2026-10-13 10:20). Every ID comes from `SequentialIDGenerator`, every timestamp from a
/// `HybridLogicalClock` fed with fixed instants, so the report is byte-for-byte reproducible.
struct Scenario {
    // Inputs
    let zone: TimeZone
    let context: CalendarContext
    let now: Date
    let today: LocalDate
    let onboardingInstant: Date
    let answers: OnboardingAnswers
    let preset: ProfilePreset
    let onboardedDB: TabulaDatabase
    let db: TabulaDatabase
    let timetable: Timetable
    let regularBell: BellSchedule
    let shortBell: BellSchedule
    let overrideDate: LocalDate

    // Engine results
    let resolver: ScheduleResolver
    let thisWeek: GridLayout
    let nextWeek: GridLayout
    let resolutions: [LocalDate: DayResolution]
    let todaySchedule: DaySchedule
    let nowNext: NowNext
    let timeBlocks: TimeBlockLayout
    let plannerInput: PlannerInput
    let plan: ReminderPlan
    let shareEnvelope: ShareEnvelope
    let shareWarnings: [ShareWarning]
    let decodedPayload: SharePayloadV1
    let sampleCode: ShortCode
    let inlineLink: String
    let codeLink: String
    let parsedLinkMatches: Bool
    let issues: [ValidationIssue]
    let jsonBytes: Int
    let prettyJSONBytes: Int
    let roundTripEqual: Bool

    // swiftlint:disable:next function_body_length
    static func build() throws -> Scenario {
        guard TimeZone(identifier: SampleScenarios.timeZoneIdentifier) != nil else { throw DemoError.noTimeZone }
        // The data (onboarding, subjects, lessons, overrides, tasks, exams) is the shared secondary scenario
        // (Packages/TimetableUI/Sources/TimetableUI/Samples/SecondaryScenario.swift), so the app's
        // `-TabulaSeed secondary` screenshots show exactly what this report shows.
        let sample = SampleScenarios.secondary()
        let zone = SampleScenarios.timeZone
        let context = sample.context
        let today = SampleScenarios.today
        let now = SampleScenarios.referenceNow
        let onboardingInstant = sample.onboardingInstant
        let overrideDate = sample.overrideDate
        let db = sample.database
        let onboarded = sample.onboardedDatabase
        let answers = sample.answers
        let timetable = sample.timetable
        let regularBell = sample.regularBell
        let shortBell = sample.shortBell

        // 2./3./5. Schedule engine ------------------------------------------------------------------------------
        guard let resolver = ScheduleResolver(database: db, timetableID: timetable.id, context: context) else {
            throw DemoError.noResolver
        }
        let thisWeek = GridLayout.week(containing: today, resolver: resolver)
        let nextWeek = GridLayout.week(containing: today.adding(days: 7), resolver: resolver)
        var resolutions: [LocalDate: DayResolution] = [:]
        for column in thisWeek.columns + nextWeek.columns {
            resolutions[column.date] = resolver.resolution(for: column.date)
        }
        let todaySchedule = resolver.day(today)
        let nowNext = resolver.nowAndNext(at: now)
        let timeBlocks = TimeBlockLayout.make(days: [todaySchedule, resolver.day(overrideDate)])

        // 6. Reminder planner -----------------------------------------------------------------------------------
        let horizonDays = 14
        // Occurrences for the horizon plus one day, so "pack tonight" sees the morning after the horizon's last evening.
        let window = DateInterval(start: context.startOfDay(today),
                                  end: context.startOfDay(today.adding(days: horizonDays + 2)))
        let occurrences = resolver.occurrences(in: window)
        let plannerInput = PlannerInput(
            now: now, context: context, settings: db.settings, rules: db.reminderRules, tasks: db.tasks,
            exams: db.exams, lessons: occurrences, packTonight: PackTonightDay.days(from: occurrences),
            horizonDays: horizonDays, canScheduleAlarms: false)
        let plan = ReminderPlanner.plan(plannerInput)

        // 7. Share -----------------------------------------------------------------------------------------------
        let (envelope, warnings) = try ShareExport.encode(from: db, timetableID: timetable.id, includeTasks: true)
        let decoded = try ShareCodec.decode(envelope.text)
        var rng = SplitMix64(seed: 20_261_013)
        let sampleCode = ShortCode.random(using: &rng)
        let inlineLink = ShareLink.inline(envelope: envelope.text).urlString()
        let codeLink = ShareLink.shortCode(sampleCode).urlString()
        let reparsed = try ShareLink.parse(envelope.route == .inline ? inlineLink : codeLink)
        let parsedLinkMatches = reparsed == (envelope.route == .inline
            ? ShareLink.inline(envelope: envelope.text) : ShareLink.shortCode(sampleCode))

        // 8. Validation + persistence -----------------------------------------------------------------------------
        let issues = db.validate()
        let json = try db.encoded()
        let pretty = try db.encoded(pretty: true)
        let roundTrip = try TabulaDatabase.decode(from: json)

        return Scenario(
            zone: zone, context: context, now: now, today: today, onboardingInstant: onboardingInstant,
            answers: answers, preset: ProfilePreset.for(.secondary), onboardedDB: onboarded, db: db,
            timetable: timetable, regularBell: regularBell, shortBell: shortBell, overrideDate: overrideDate,
            resolver: resolver, thisWeek: thisWeek, nextWeek: nextWeek, resolutions: resolutions,
            todaySchedule: todaySchedule, nowNext: nowNext, timeBlocks: timeBlocks, plannerInput: plannerInput,
            plan: plan, shareEnvelope: envelope, shareWarnings: warnings, decodedPayload: decoded,
            sampleCode: sampleCode, inlineLink: inlineLink, codeLink: codeLink, parsedLinkMatches: parsedLinkMatches,
            issues: issues, jsonBytes: json.count, prettyJSONBytes: pretty.count,
            roundTripEqual: roundTrip.canonicalized() == db.canonicalized())
    }
}

enum DemoError: Error, CustomStringConvertible {
    case noTimeZone
    case noResolver
    case usage

    var description: String {
        switch self {
        case .noTimeZone: return "Europe/Bratislava is not a known time zone on this system (install tzdata)."
        case .noResolver: return "ScheduleResolver could not be created for the sample timetable."
        case .usage: return "usage: EngineDemo <output.html> [Localizable.xcstrings]"
        }
    }
}

/// Deterministic RNG for the sample short code (SplitMix64; the demo must not depend on system randomness).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
