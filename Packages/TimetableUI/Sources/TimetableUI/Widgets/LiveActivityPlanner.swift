// Decides what the app does with its Live Activities right now (Stage B2): start, schedule, update or end each one.
// Pure, Linux-tested; the app (App/Sources/Widgets/LiveActivityController.swift) only reads ActivityKit's current
// activities into `LiveActivityExisting` values, runs `plan`, executes the steps and applies `ledgerChanges`.
//
// Apple's rules this is built on (ENVIRONMENT §31): an app starts a Live Activity only while it is in the FOREGROUND
// (`canStart`; background requests fail with `.visibility`); it updates and ends them from the foreground or a
// background task; iOS 26 can SCHEDULE a start for a date (`request(…, alertConfiguration:start:)`, which must alert
// the user, and the pending activity counts toward the system limit); an activity lives ≤ 8 h, then stays on the Lock
// Screen ≤ 4 h; content + attributes ≤ 4 KB; the highest `relevanceScore` wins the Dynamic Island.
//
// Ledger: every start / schedule is recorded; the planner forgets the key again when it ends that activity itself
// without a replacement. So only activities the USER swiped away (or the system ended, 8 h) block a new start that
// day; a day cancelled and then restored, an exam moved to another day, a setting switched off and on all start again.
//
// (a) Lesson activity — one per school day (`LessonActivityAttributes.day`):
//   start     when a lesson runs or the first lesson starts within `lessonLead` (15 min), the lesson setting is on, the
//             feature is entitled, the system allows Live Activities, the app is in the foreground and no activity
//             for today is running or was dismissed;
//   schedule  with "Start automatically" on, from the foreground: today's window if it opens later, else the next
//             lesson day within `scheduleHorizonDays` once today's lessons are over (at most one pending);
//   update    on every run (data change, foreground, time-zone change, background refresh, in-app timer) when the
//             content differs: the day's lessons, the current/next index, the stale date (the next lesson boundary);
//   end       after the last lesson with the final "No more lessons today" content, dismissed `endStateDuration`
//             after it; immediately on a day change, a holiday / cancelled day / no lessons, the setting off, the
//             entitlement or system permission gone, and for duplicates; every PENDING one as soon as "Start
//             automatically" is off. A changed pending activity is ended and scheduled again from the foreground (a
//             scheduled start date cannot be changed); in the background, where nothing could replace it, it is kept.
// (b) Exam-day activity — one per exam with a start time (`ExamActivityAttributes.examID`), one running at a time:
//   window    from the latest of the start of the exam day, start − `examLead` (6 h) and close − `maxDuration` (8 h) to
//             the end (else start + `examAssumedDuration`);
//   start     the first exam of today whose window is open and that was not dismissed (a second exam that day starts
//             when its window opens if the first was swiped away, or once the first ended);
//   schedule  the earliest exam whose window opens later (an earlier exam added later replaces the pending one); the
//             alert is moved to no earlier than `earliestScheduledStart` (06:00) unless that is less than
//             `examScheduledLead` before the exam;
//   ends      after the exam with "Exam finished", or at once when the exam is deleted, completed or moved.
// Relevance: exam 100, lesson 50 → the exam wins the Dynamic Island when both run; the Lock Screen orders them so.
import Foundation
import TimetableCore

/// Constants of the Live Activity rules (documented in the header and in the device checklist).
public enum LiveActivityPolicy {
    /// A lesson activity starts this long before the first lesson.
    public static let lessonLead: TimeInterval = 15 * 60
    /// An exam activity starts this long before the exam (but not before the exam day).
    public static let examLead: TimeInterval = 6 * 3600
    /// "In progress" length of an exam without an end time.
    public static let examAssumedDuration: TimeInterval = 60 * 60
    /// Ended activities stay on the Lock Screen this long (Apple HIG: "In most cases, 15 to 30 minutes is adequate").
    public static let endStateDuration: TimeInterval = 15 * 60
    /// Activities are scheduled at most this many days ahead.
    public static let scheduleHorizonDays = 3
    /// A scheduled exam activity (which alerts) does not start before this local time…
    public static let earliestScheduledStart = LocalTime(hour: 6, minute: 0)!
    /// …unless the exam starts less than this after it; then it starts this long before the exam.
    public static let examScheduledLead: TimeInterval = 15 * 60
    /// Apple: "A Live Activity can be active for up to eight hours" (exam windows are capped to it, RISKS #75).
    public static let maxDuration: TimeInterval = 8 * 3600
    /// A schedule closer than this to now is not worth it (the next run starts it directly).
    public static let minimumScheduleDelay: TimeInterval = 60
    /// Relevance scores ("the system shows the Live Activity with the highest relevance score in the Dynamic Island").
    public static let lessonRelevance: Double = 50
    public static let examRelevance: Double = 100
}

/// What the user chose (Settings → Live Activities). Device-local (UserDefaults), not part of the synced database.
public struct LiveActivityPreferences: Codable, Equatable, Sendable {
    /// The current-lesson activity.
    public var lessonEnabled: Bool
    /// The exam-day activity.
    public var examEnabled: Bool
    /// Schedule the next activity while the app is open, so it starts on its own (iOS announces it with an alert).
    public var autoStart: Bool

    enum CodingKeys: String, CodingKey { case lessonEnabled = "lesson", examEnabled = "exam", autoStart = "auto" }

    /// Defaults: both activities on (PHASE4_PLAN §0.5 "default on"); automatic start off, because every scheduled
    /// start alerts the user (P4-B2-1: human decision pending).
    public init(lessonEnabled: Bool = true, examEnabled: Bool = true, autoStart: Bool = false) {
        self.lessonEnabled = lessonEnabled
        self.examEnabled = examEnabled
        self.autoStart = autoStart
    }

    public init(from decoder: any Decoder) throws {
        let defaults = LiveActivityPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessonEnabled = try container.decodeIfPresent(Bool.self, forKey: .lessonEnabled) ?? defaults.lessonEnabled
        examEnabled = try container.decodeIfPresent(Bool.self, forKey: .examEnabled) ?? defaults.examEnabled
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? defaults.autoStart
    }
}

/// Which days / exams had an activity started or scheduled that the planner did not end itself — i.e. one the user
/// swiped away or the system ended (8-hour limit) — so it is not started again that day. The planner records every
/// start / schedule and forgets the key again whenever it ends that activity itself without a replacement (holiday,
/// setting off, exam deleted…), so a planner-initiated end never blocks a later start. Exams are keyed by (exam, day),
/// so a moved exam can start on its new day. Device-local; pruned to the last `keptDays` days and `keptExams` exams.
public struct LiveActivityLedger: Codable, Equatable, Sendable {
    public static let keptDays = 14
    public static let keptExams = 32

    /// One exam on one day.
    public struct ExamKey: Codable, Hashable, Sendable {
        public var id: UUID
        public var day: LocalDate

        enum CodingKeys: String, CodingKey { case id, day = "d" }

        public init(id: UUID, day: LocalDate) {
            self.id = id
            self.day = day
        }
    }

    public var lessonDays: [LocalDate]
    public var exams: [ExamKey]

    // "examDays": the pre-QA format ("exams": [UUID]) is ignored on purpose (it never shipped).
    enum CodingKeys: String, CodingKey { case lessonDays = "days", exams = "examDays" }

    public init(lessonDays: [LocalDate] = [], exams: [ExamKey] = []) {
        self.lessonDays = lessonDays
        self.exams = exams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessonDays = try container.decodeIfPresent([LocalDate].self, forKey: .lessonDays) ?? []
        exams = try container.decodeIfPresent([ExamKey].self, forKey: .exams) ?? []
    }

    public func hasLesson(_ day: LocalDate) -> Bool { lessonDays.contains(day) }
    public func hasExam(_ id: UUID, day: LocalDate) -> Bool { exams.contains(ExamKey(id: id, day: day)) }

    public mutating func recordLesson(_ day: LocalDate) {
        guard !hasLesson(day) else { return }
        lessonDays = Array((lessonDays + [day]).sorted().suffix(Self.keptDays))
    }

    public mutating func forgetLesson(_ day: LocalDate) { lessonDays.removeAll { $0 == day } }

    public mutating func recordExam(_ id: UUID, day: LocalDate) {
        guard !hasExam(id, day: day) else { return }
        exams = Array((exams + [ExamKey(id: id, day: day)]).suffix(Self.keptExams))
    }

    /// Every day of exam `id`.
    public mutating func forgetExam(_ id: UUID) { exams.removeAll { $0.id == id } }

    /// Today and later lesson days may start again.
    public mutating func forgetLessons(from day: LocalDate) { lessonDays.removeAll { $0 >= day } }
    /// Every exam may start again.
    public mutating func forgetExams() { exams.removeAll() }

    /// Applies one planning run's changes. The app reloads the ledger after the run's ActivityKit awaits and applies
    /// only these, so writes made meanwhile (Settings switches, the system switch) are kept.
    public mutating func apply(_ changes: [LiveActivityLedgerChange]) {
        for change in changes {
            switch change {
            case .recordLesson(let day): recordLesson(day)
            case .forgetLesson(let day): forgetLesson(day)
            case let .recordExam(id, day): recordExam(id, day: day)
            case .forgetExam(let id): forgetExam(id)
            }
        }
    }

    /// The Settings switches changed: an activity switched on again may start again from today.
    public mutating func applyPreferenceChange(from old: LiveActivityPreferences, to new: LiveActivityPreferences,
                                               today: LocalDate) {
        if new.lessonEnabled, !old.lessonEnabled { forgetLessons(from: today) }
        if new.examEnabled, !old.examEnabled { forgetExams() }
    }

    /// Live Activities were turned on again in the Settings app: the activities the system ended may start again.
    public mutating func systemReenabled(today: LocalDate) {
        forgetLessons(from: today)
        forgetExams()
    }
}

/// One ledger change of a planning run.
public enum LiveActivityLedgerChange: Hashable, Sendable {
    case recordLesson(LocalDate)
    case forgetLesson(LocalDate)
    case recordExam(UUID, LocalDate)
    case forgetExam(UUID)
}

/// ActivityKit's `ActivityState`, without ActivityKit.
public enum LiveActivityStatus: String, Sendable {
    /// Scheduled for a start date (iOS 26), not started yet.
    case pending
    case active
    /// Past its stale date, still shown.
    case stale
    /// Ended, maybe still on the Lock Screen.
    case ended
    /// Removed by the user or the system.
    case dismissed

    /// Counts as "there is one" (pending, active or stale).
    public var isRunning: Bool { self == .pending || self == .active || self == .stale }
}

/// `ActivityContent` without ActivityKit.
public struct LiveActivityContent<State: Hashable & Sendable>: Hashable, Sendable {
    public var state: State
    public var staleDate: Date?
    public var relevanceScore: Double

    public init(state: State, staleDate: Date?, relevanceScore: Double) {
        self.state = state
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

/// `ActivityUIDismissalPolicy` without ActivityKit.
public enum LiveActivityDismissal: Hashable, Sendable {
    case immediate
    case after(Date)
}

/// The alert a scheduled start shows (rendered in the app's language).
public struct LiveActivityAlert: Hashable, Sendable {
    public var title: String
    public var body: String
}

/// One of the app's current Live Activities (from `Activity<…>.activities`).
public struct LiveActivityExisting<Attributes: Hashable & Sendable, State: Hashable & Sendable>: Hashable, Sendable {
    public var id: String
    public var attributes: Attributes
    public var status: LiveActivityStatus
    public var content: LiveActivityContent<State>

    public init(id: String, attributes: Attributes, status: LiveActivityStatus, content: LiveActivityContent<State>) {
        self.id = id
        self.attributes = attributes
        self.status = status
        self.content = content
    }
}

/// What to do with one activity.
public enum LiveActivityStep<Attributes: Hashable & Sendable, State: Hashable & Sendable>: Hashable, Sendable {
    /// `Activity.request(attributes:content:pushType: nil)` (foreground only).
    case start(Attributes, LiveActivityContent<State>)
    /// `Activity.request(attributes:content:pushType: nil, style: .standard, alertConfiguration:start:)` (iOS 26).
    case schedule(Attributes, LiveActivityContent<State>, at: Date, alert: LiveActivityAlert)
    /// `activity.update(_:)`.
    case update(id: String, LiveActivityContent<State>)
    /// `activity.end(_:dismissalPolicy:)`.
    case end(id: String, LiveActivityContent<State>?, LiveActivityDismissal)
}

public typealias LessonActivityStep = LiveActivityStep<LessonActivityAttributes, LessonActivityAttributes.ContentState>
public typealias ExamActivityStep = LiveActivityStep<ExamActivityAttributes, ExamActivityAttributes.ContentState>
public typealias LessonActivityExisting = LiveActivityExisting<LessonActivityAttributes, LessonActivityAttributes.ContentState>
public typealias ExamActivityExisting = LiveActivityExisting<ExamActivityAttributes, ExamActivityAttributes.ContentState>

/// Everything one planning run looks at.
public struct LiveActivityPlanInput: Sendable {
    public var sources: LiveActivitySources
    public var now: Date
    /// The app is in the foreground (only then can it start or schedule).
    public var canStart: Bool
    /// `ActivityAuthorizationInfo().areActivitiesEnabled`.
    public var systemEnabled: Bool
    /// `EntitlementsProvider.isAllowed(.liveActivity)`.
    public var entitled: Bool
    public var preferences: LiveActivityPreferences
    public var ledger: LiveActivityLedger
    public var lessons: [LessonActivityExisting]
    public var exams: [ExamActivityExisting]

    public init(sources: LiveActivitySources, now: Date, canStart: Bool, systemEnabled: Bool, entitled: Bool,
                preferences: LiveActivityPreferences, ledger: LiveActivityLedger, lessons: [LessonActivityExisting],
                exams: [ExamActivityExisting]) {
        self.sources = sources
        self.now = now
        self.canStart = canStart
        self.systemEnabled = systemEnabled
        self.entitled = entitled
        self.preferences = preferences
        self.ledger = ledger
        self.lessons = lessons
        self.exams = exams
    }
}

/// The result of one run.
public struct LiveActivityPlan: Equatable, Sendable {
    public var lessonSteps: [LessonActivityStep]
    public var examSteps: [ExamActivityStep]
    /// This run's ledger changes (the app applies them to a freshly loaded ledger after executing the steps).
    public var ledgerChanges: [LiveActivityLedgerChange]
    /// The input ledger with `ledgerChanges` applied (tests, diagnostics).
    public var ledger: LiveActivityLedger
    /// The next instant at which the plan changes (lesson boundary, window opening, exam start / end), if any. The app
    /// re-plans then while it runs and asks for a background refresh around it.
    public var nextEvaluation: Date?
    /// After the steps at least one lesson / exam activity is pending or running (known before the steps execute, so
    /// the background-refresh hint never waits for ActivityKit).
    public var keepsActivity: Bool

    /// Nothing to do.
    public var isEmpty: Bool { lessonSteps.isEmpty && examSteps.isEmpty }
}

public struct LiveActivityPlanner: Sendable {
    /// Renders the scheduled-start alerts (the app's language, locale, 12/24 h and zone).
    public let renderer: LocalizedTextRenderer

    public init(renderer: LocalizedTextRenderer) {
        self.renderer = renderer
    }

    public func plan(_ input: LiveActivityPlanInput) -> LiveActivityPlan {
        var changes: [LiveActivityLedgerChange] = []
        var events: [Date] = []
        var keeps = false
        let lessonSteps = planLessons(input, changes: &changes, events: &events, keeps: &keeps)
        let examSteps = planExams(input, changes: &changes, events: &events, keeps: &keeps)
        var ledger = input.ledger
        ledger.apply(changes)
        let next = events.filter { $0 > input.now }.min()
        return LiveActivityPlan(lessonSteps: lessonSteps, examSteps: examSteps, ledgerChanges: changes, ledger: ledger,
                                nextEvaluation: next, keepsActivity: keeps)
    }

    // MARK: (a) Lessons

    func planLessons(_ input: LiveActivityPlanInput, changes: inout [LiveActivityLedgerChange], events: inout [Date],
                     keeps: inout Bool) -> [LessonActivityStep] {
        let now = input.now
        let running = input.lessons.filter(\.status.isRunning).sorted { $0.id < $1.id }
        guard input.preferences.lessonEnabled, input.entitled, input.systemEnabled else {
            changes += Set(running.map(\.attributes.day)).sorted().map { .forgetLesson($0) }
            return running.map { .end(id: $0.id, nil, .immediate) }
        }
        let style = input.sources.style
        let today = input.sources.context.localDate(of: now)
        let todayDay = input.sources.lessonDay(today)
        let horizon = today.adding(days: LiveActivityPolicy.scheduleHorizonDays)
        let nextDay = input.sources.lessonDays.first { $0.day > today && $0.day <= horizon }
        let autoStart = input.preferences.autoStart
        var steps: [LessonActivityStep] = []
        var keptToday: LessonActivityExisting?
        var keptPending: LessonActivityExisting?
        var ended = Set<LocalDate>()     // days whose activity the planner ended itself (forgotten unless replaced)
        var started = Set<LocalDate>()   // days started or scheduled in this run

        for activity in running {
            let day = activity.attributes.day
            let pending = activity.status == .pending
            func end(_ content: LiveActivityContent<LessonActivityAttributes.ContentState>?,
                     _ dismissal: LiveActivityDismissal = .immediate) {
                steps.append(.end(id: activity.id, content, dismissal))
                ended.insert(day)
            }
            if day < today {
                end(Self.finalLessonContent(activity.content.state.style))
            } else if pending, !autoStart {
                end(nil)   // "Start automatically" was switched off: cancel what it scheduled
            } else if day == today {
                guard let todayDay else {
                    end(nil)   // no lessons (any more) today: holiday, cancelled day, all lessons moved
                    continue
                }
                if keptToday != nil {
                    steps.append(.end(id: activity.id, nil, .immediate))   // a duplicate; the kept one keeps the key
                } else if now >= todayDay.lastEnd {
                    end(Self.finalLessonContent(style), Self.dismissal(endedAt: todayDay.lastEnd, now: now))
                } else if pending, input.canStart, activity.content != Self.scheduledLessonContent(todayDay, style) {
                    end(nil)   // changed: a scheduled start date cannot be changed, so it is replaced below
                } else {
                    // Running, an unchanged pending one, or a changed pending one in the background: nothing could
                    // replace it there, so it keeps its start and the first run after it started updates it.
                    keptToday = activity
                }
            } else if pending, keptPending == nil, let nextDay, nextDay.day == day,
                      !input.canStart || activity.content == Self.scheduledLessonContent(nextDay, style) {
                keptPending = activity   // the next lesson day's schedule (a changed one is kept in the background)
            } else if pending, keptPending == nil, !input.canStart, input.sources.lessonDay(day) != nil {
                keptPending = activity   // still a lesson day; re-planned at the next foreground
            } else {
                end(nil)
            }
        }

        func blocked(_ day: LocalDate) -> Bool { input.ledger.hasLesson(day) && !ended.contains(day) }
        var todayBusy = false
        if let todayDay, now < todayDay.lastEnd {
            todayBusy = true
            let open = todayDay.firstStart.addingTimeInterval(-LiveActivityPolicy.lessonLead)
            events += [open, todayDay.lastEnd] + todayDay.lessons.flatMap { [$0.start, $0.end] }
            if let kept = keptToday {
                if kept.status != .pending {
                    let desired = Self.runningLessonContent(todayDay, style, now: now)
                    if kept.content != desired { steps.append(.update(id: kept.id, desired)) }
                }
            } else if input.canStart, !blocked(today) {
                if now >= open {
                    steps.append(.start(LessonActivityAttributes(day: today),
                                        Self.runningLessonContent(todayDay, style, now: now)))
                    started.insert(today)
                } else if autoStart, open.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                    steps.append(.schedule(LessonActivityAttributes(day: today), Self.scheduledLessonContent(todayDay, style),
                                           at: open, alert: lessonAlert(todayDay)))
                    started.insert(today)
                }
            }
        }

        if !todayBusy, keptPending == nil, input.canStart, autoStart, let nextDay, !blocked(nextDay.day) {
            let open = nextDay.firstStart.addingTimeInterval(-LiveActivityPolicy.lessonLead)
            if open.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                steps.append(.schedule(LessonActivityAttributes(day: nextDay.day), Self.scheduledLessonContent(nextDay, style),
                                       at: open, alert: lessonAlert(nextDay)))
                started.insert(nextDay.day)
            }
        }
        let kept = Set([keptToday, keptPending].compactMap { $0?.attributes.day })
        changes += started.sorted().map { .recordLesson($0) }
        changes += ended.subtracting(started).subtracting(kept).sorted().map { .forgetLesson($0) }
        if !kept.isEmpty || !started.isEmpty { keeps = true }
        return steps
    }

    /// The content while lessons run: the day's lessons, the index of the current/next one (the remaining lessons are
    /// `lessons[index...]`), stale at the next lesson boundary (the system re-renders an activity when it becomes
    /// stale, and the views compute the current lesson at render time, so they switch lessons even when the app
    /// cannot update in time — device check B2.6).
    public static func runningLessonContent(_ day: LiveActivityLessonDay, _ style: LiveActivityStyle,
                                            now: Date) -> LiveActivityContent<LessonActivityAttributes.ContentState> {
        let index = LiveActivityTimeline.currentIndex(in: day.lessons, at: now) ?? day.lessons.count
        let boundary = day.lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
        return LiveActivityContent(state: .init(lessons: day.lessons, index: index, isFinal: false, style: style),
                                   staleDate: boundary, relevanceScore: LiveActivityPolicy.lessonRelevance)
    }

    /// The content of a scheduled (not yet started) lesson activity: the running content before the first lesson
    /// (index 0, stale at the first start), so a scheduled activity that starts needs no update.
    public static func scheduledLessonContent(_ day: LiveActivityLessonDay,
                                              _ style: LiveActivityStyle) -> LiveActivityContent<LessonActivityAttributes.ContentState> {
        LiveActivityContent(state: .init(lessons: day.lessons, index: 0, isFinal: false, style: style),
                            staleDate: day.lessons.first?.start, relevanceScore: LiveActivityPolicy.lessonRelevance)
    }

    /// The final content ("No more lessons today").
    public static func finalLessonContent(_ style: LiveActivityStyle) -> LiveActivityContent<LessonActivityAttributes.ContentState> {
        LiveActivityContent(state: .init(lessons: [], index: 0, isFinal: true, style: style), staleDate: nil,
                            relevanceScore: LiveActivityPolicy.lessonRelevance)
    }

    func lessonAlert(_ day: LiveActivityLessonDay) -> LiveActivityAlert {
        let first = day.lessons.first
        return LiveActivityAlert(
            title: renderer.string(forKey: "today.header.first"),
            body: renderer.format(key: "liveActivity.alert.at", arguments: [
                .text(first?.subject.name ?? ""), .text(first.map { renderer.formatter.time($0.start) } ?? ""),
            ]))
    }

    // MARK: (b) Exams

    func planExams(_ input: LiveActivityPlanInput, changes: inout [LiveActivityLedgerChange], events: inout [Date],
                   keeps: inout Bool) -> [ExamActivityStep] {
        let now = input.now
        let running = input.exams.filter(\.status.isRunning).sorted { $0.id < $1.id }
        guard input.preferences.examEnabled, input.entitled, input.systemEnabled else {
            changes += Set(running.map(\.attributes.examID)).sorted { $0.uuidString < $1.uuidString }.map { .forgetExam($0) }
            return running.map { .end(id: $0.id, nil, .immediate) }
        }
        let style = input.sources.style
        let context = input.sources.context
        let today = context.localDate(of: now)
        let autoStart = input.preferences.autoStart
        let exams = input.sources.exams.filter { $0.close > now }
        let pendingIDs = Set(running.filter { $0.status == .pending }.map(\.attributes.examID))
        func recorded(_ exam: LiveActivityExam) -> Bool { input.ledger.hasExam(exam.id, day: exam.day) }
        // The exam a scheduled start is for: the earliest whose window opens later and that the user did not dismiss
        // (an exam added before the pending one replaces it).
        let upcoming = autoStart
            ? exams.first { Self.window($0, context).lowerBound > now && (!recorded($0) || pendingIDs.contains($0.id)) }
            : nil
        var steps: [ExamActivityStep] = []
        var kept: [UUID: ExamActivityExisting] = [:]
        var ended = Set<UUID>()             // exams whose activity the planner ended itself (forgotten unless replaced)
        var started: [UUID: LocalDate] = [:]

        for activity in running {
            let id = activity.attributes.examID
            let pending = activity.status == .pending
            func end(_ content: LiveActivityContent<ExamActivityAttributes.ContentState>?,
                     _ dismissal: LiveActivityDismissal = .immediate) {
                steps.append(.end(id: activity.id, content, dismissal))
                ended.insert(id)
            }
            guard let exam = input.sources.exams.first(where: { $0.id == id }) else {
                end(nil)   // deleted, completed, or moved beyond the horizon
                continue
            }
            if pending, !autoStart {
                end(nil)   // "Start automatically" was switched off
            } else if kept[id] != nil {
                steps.append(.end(id: activity.id, nil, .immediate))   // a duplicate
            } else if now >= exam.close {
                end(Self.finalExamContent(exam, style), Self.dismissal(endedAt: exam.close, now: now))
            } else if pending {
                if !input.canStart || (upcoming?.id == id && activity.content == Self.scheduledExamContent(exam, style)) {
                    kept[id] = activity   // unchanged, or nothing could replace it in the background
                } else {
                    end(nil)   // changed or no longer the earliest: replaced below
                }
            } else if exam.day != today {
                end(nil)   // moved to a later day while it ran
            } else {
                kept[id] = activity
                let desired = Self.runningExamContent(exam, style, now: now)
                if activity.content != desired { steps.append(.update(id: activity.id, desired)) }
            }
        }

        for exam in exams {
            events += [Self.window(exam, context).lowerBound, exam.start, exam.close]
        }
        func blocked(_ exam: LiveActivityExam) -> Bool { recorded(exam) && !ended.contains(exam.id) }
        // Started now: the first exam of today whose window is open and that was not dismissed, while no exam
        // activity runs (one at a time; the next one starts when the previous one ended).
        let examRunning = kept.values.contains { $0.status != .pending }
        if !examRunning, input.canStart,
           let current = exams.first(where: { $0.day == today && Self.window($0, context).contains(now)
                                              && kept[$0.id] == nil && !blocked($0) }) {
            steps.append(.start(ExamActivityAttributes(examID: current.id), Self.runningExamContent(current, style, now: now)))
            started[current.id] = current.day
        }
        // Scheduled: the upcoming exam, if no exam activity is pending yet.
        let hasPending = kept.values.contains { $0.status == .pending }
        if !hasPending, input.canStart, let upcoming, kept[upcoming.id] == nil, started[upcoming.id] == nil,
           !blocked(upcoming) {
            let at = Self.scheduledStart(upcoming, context)
            if at.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                steps.append(.schedule(ExamActivityAttributes(examID: upcoming.id), Self.scheduledExamContent(upcoming, style),
                                       at: at, alert: examAlert(upcoming)))
                started[upcoming.id] = upcoming.day
            }
        }
        changes += started.sorted { $0.key.uuidString < $1.key.uuidString }.map { .recordExam($0.key, $0.value) }
        changes += ended.subtracting(started.keys).subtracting(kept.keys).sorted { $0.uuidString < $1.uuidString }
            .map { .forgetExam($0) }
        if !kept.isEmpty || !started.isEmpty { keeps = true }
        return steps
    }

    /// The exam's window: from the latest of the start of its day, start − `examLead` and close − `maxDuration` (an
    /// activity lives ≤ 8 h) to its close.
    public static func window(_ exam: LiveActivityExam, _ context: CalendarContext) -> Range<Date> {
        let open = max(context.startOfDay(exam.day), exam.start.addingTimeInterval(-LiveActivityPolicy.examLead),
                       exam.close.addingTimeInterval(-LiveActivityPolicy.maxDuration))
        return open..<max(open, exam.close)
    }

    /// When a scheduled exam activity starts: the window's start, but not before 06:00 on the exam day unless the exam
    /// starts less than `examScheduledLead` after 06:00 (then that lead before the exam, still inside the window).
    public static func scheduledStart(_ exam: LiveActivityExam, _ context: CalendarContext) -> Date {
        let open = window(exam, context).lowerBound
        let morning = context.date(exam.day, LiveActivityPolicy.earliestScheduledStart)
        let latest = exam.start.addingTimeInterval(-LiveActivityPolicy.examScheduledLead)
        let wanted = max(open, morning)
        return wanted <= latest ? wanted : max(open, latest)
    }

    /// The content while the exam window is open: stale at the start (countdown → "in progress"), then at the end.
    public static func runningExamContent(_ exam: LiveActivityExam, _ style: LiveActivityStyle,
                                          now: Date) -> LiveActivityContent<ExamActivityAttributes.ContentState> {
        let stale = [exam.start, exam.close].filter { $0 > now }.min()
        return LiveActivityContent(state: examState(exam, style, isFinal: false), staleDate: stale,
                                   relevanceScore: LiveActivityPolicy.examRelevance)
    }

    /// The content of a scheduled (not yet started) exam activity.
    public static func scheduledExamContent(_ exam: LiveActivityExam,
                                            _ style: LiveActivityStyle) -> LiveActivityContent<ExamActivityAttributes.ContentState> {
        LiveActivityContent(state: examState(exam, style, isFinal: false), staleDate: exam.start,
                            relevanceScore: LiveActivityPolicy.examRelevance)
    }

    /// The final content ("Exam finished").
    public static func finalExamContent(_ exam: LiveActivityExam,
                                        _ style: LiveActivityStyle) -> LiveActivityContent<ExamActivityAttributes.ContentState> {
        LiveActivityContent(state: examState(exam, style, isFinal: true), staleDate: nil,
                            relevanceScore: LiveActivityPolicy.examRelevance)
    }

    static func examState(_ exam: LiveActivityExam, _ style: LiveActivityStyle,
                          isFinal: Bool) -> ExamActivityAttributes.ContentState {
        ExamActivityAttributes.ContentState(title: exam.title, subject: exam.subject, room: exam.room, start: exam.start,
                                            end: exam.end, isFinal: isFinal, style: style)
    }

    func examAlert(_ exam: LiveActivityExam) -> LiveActivityAlert {
        LiveActivityAlert(
            title: renderer.string(forKey: "liveActivity.exam.today"),
            body: renderer.format(key: "liveActivity.alert.at", arguments: [
                .text(exam.title), .text(renderer.formatter.time(exam.start)),
            ]))
    }

    // MARK: Shared

    /// Keep an ended activity on the Lock Screen until `endStateDuration` after it ended (immediately when that passed).
    static func dismissal(endedAt: Date, now: Date) -> LiveActivityDismissal {
        let until = endedAt.addingTimeInterval(LiveActivityPolicy.endStateDuration)
        return until > now ? .after(until) : .immediate
    }
}

/// Which lesson is current at an instant (shared by the planner and the views' presenter).
public enum LiveActivityTimeline {
    /// Index of the lesson in progress at `instant` (of overlapping ones the one that started last), else of the next
    /// one; `nil` after the last lesson.
    public static func currentIndex(in lessons: [LiveActivityLesson], at instant: Date, from lowerBound: Int = 0) -> Int? {
        let candidates = lessons.indices.filter { $0 >= lowerBound }
        if let running = candidates.filter({ lessons[$0].start <= instant && instant < lessons[$0].end })
            .max(by: { lessons[$0].start < lessons[$1].start || (lessons[$0].start == lessons[$1].start && $0 < $1) }) {
            return running
        }
        return candidates.first { lessons[$0].start > instant }
    }
}
