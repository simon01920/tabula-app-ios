// Decides what the app does with its Live Activities right now (Stage B2): start, schedule, update or end each one.
// Pure, Linux-tested; the app (App/Sources/Widgets/LiveActivityController.swift) only reads ActivityKit's current
// activities into `LiveActivityExisting` values, runs `plan`, and executes the steps.
//
// Apple's rules this is built on (ENVIRONMENT §29): an app starts a Live Activity only while it is in the FOREGROUND
// (`canStart`; background requests fail with `.visibility`); it updates and ends them from the foreground or a
// background task; iOS 26 can SCHEDULE a start for a date (`request(…, alertConfiguration:start:)`, which must alert
// the user, and the pending activity counts toward the system limit); an activity lives ≤ 8 h, then stays on the Lock
// Screen ≤ 4 h; content + attributes ≤ 4 KB; the highest `relevanceScore` wins the Dynamic Island.
//
// (a) Lesson activity — one per school day (`LessonActivityAttributes.day`):
//   start     when a lesson runs or the first lesson starts within `lessonLead` (15 min), the lesson setting is on, the
//             feature is entitled, the system allows Live Activities, the app is in the foreground and no lesson
//             activity was started for today yet (the ledger also remembers activities the user swiped away);
//   schedule  with "Start automatically" on, from the foreground: today's window if it opens later, else the next
//             lesson day within `scheduleHorizonDays` once today's lessons are over (at most one pending);
//   update    on every run (data change, foreground, time-zone change, background refresh, in-app timer) when the
//             content differs: the day's lessons, the current/next index, the stale date (the next lesson boundary);
//   end       after the last lesson with the final "No more lessons today" content, dismissed `endStateDuration`
//             after it; immediately on a day change, a holiday / cancelled day / no lessons, the setting off, the
//             entitlement or system permission gone, and for duplicates. A changed pending (scheduled) activity is
//             ended and scheduled again, because a scheduled start date cannot be changed.
// (b) Exam-day activity — one per exam with a start time (`ExamActivityAttributes.examID`):
//   window    from max(start of the exam day, start − `examLead` (6 h)) to the end (else start + `examAssumedDuration`);
//   start / schedule / update / end as above; a scheduled start alerts the user, so it is moved to no earlier than
//             `earliestScheduledStart` (06:00) unless that is less than `examScheduledLead` before the exam;
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
    /// start alerts the user (decision needed, gate report).
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

/// Which days / exams already had an activity started or scheduled (so one the user swiped away is not started again
/// the same day). Device-local; pruned to the last `keptDays` days and `keptExams` exams.
public struct LiveActivityLedger: Codable, Equatable, Sendable {
    public static let keptDays = 14
    public static let keptExams = 32

    public var lessonDays: [LocalDate]
    public var examIDs: [UUID]

    enum CodingKeys: String, CodingKey { case lessonDays = "days", examIDs = "exams" }

    public init(lessonDays: [LocalDate] = [], examIDs: [UUID] = []) {
        self.lessonDays = lessonDays
        self.examIDs = examIDs
    }

    public func hasLesson(_ day: LocalDate) -> Bool { lessonDays.contains(day) }
    public func hasExam(_ id: UUID) -> Bool { examIDs.contains(id) }

    public mutating func recordLesson(_ day: LocalDate) {
        guard !hasLesson(day) else { return }
        lessonDays = Array((lessonDays + [day]).sorted().suffix(Self.keptDays))
    }

    public mutating func recordExam(_ id: UUID) {
        guard !hasExam(id) else { return }
        examIDs = Array((examIDs + [id]).suffix(Self.keptExams))
    }

    /// The user switched the lesson activity on: today and later may start again.
    public mutating func forgetLessons(from day: LocalDate) { lessonDays.removeAll { $0 >= day } }
    /// The user switched the exam activity on.
    public mutating func forgetExams() { examIDs.removeAll() }
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
    /// The ledger after the steps (save it).
    public var ledger: LiveActivityLedger
    /// The next instant at which the plan changes (lesson boundary, window opening, exam start / end), if any. The app
    /// re-plans then while it runs and asks for a background refresh around it.
    public var nextEvaluation: Date?

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
        var ledger = input.ledger
        var events: [Date] = []
        let lessonSteps = planLessons(input, ledger: &ledger, events: &events)
        let examSteps = planExams(input, ledger: &ledger, events: &events)
        let next = events.filter { $0 > input.now }.min()
        return LiveActivityPlan(lessonSteps: lessonSteps, examSteps: examSteps, ledger: ledger, nextEvaluation: next)
    }

    // MARK: (a) Lessons

    func planLessons(_ input: LiveActivityPlanInput, ledger: inout LiveActivityLedger,
                     events: inout [Date]) -> [LessonActivityStep] {
        let now = input.now
        let running = input.lessons.filter(\.status.isRunning).sorted { $0.id < $1.id }
        guard input.preferences.lessonEnabled, input.entitled, input.systemEnabled else {
            return running.map { .end(id: $0.id, nil, .immediate) }
        }
        let style = input.sources.style
        let today = input.sources.context.localDate(of: now)
        let todayDay = input.sources.lessonDay(today)
        let horizon = today.adding(days: LiveActivityPolicy.scheduleHorizonDays)
        let nextDay = input.sources.lessonDays.first { $0.day > today && $0.day <= horizon }
        var steps: [LessonActivityStep] = []
        var keptToday: LessonActivityExisting?
        var keptPending: LessonActivityExisting?
        var replan = Set<LocalDate>()

        for activity in running {
            let day = activity.attributes.day
            if day < today {
                steps.append(.end(id: activity.id, Self.finalLessonContent(activity.content.state.style), .immediate))
            } else if day == today {
                guard let todayDay, keptToday == nil else {
                    steps.append(.end(id: activity.id, nil, .immediate))   // no lessons (any more) today, or a duplicate
                    continue
                }
                if now >= todayDay.lastEnd {
                    steps.append(.end(id: activity.id, Self.finalLessonContent(style),
                                      Self.dismissal(endedAt: todayDay.lastEnd, now: now)))
                } else if activity.status == .pending, activity.content != Self.scheduledLessonContent(todayDay, style) {
                    steps.append(.end(id: activity.id, nil, .immediate))
                    replan.insert(today)
                } else {
                    keptToday = activity
                }
            } else if activity.status == .pending, keptPending == nil, let nextDay, nextDay.day == day,
                      activity.content == Self.scheduledLessonContent(nextDay, style) {
                keptPending = activity
            } else {
                steps.append(.end(id: activity.id, nil, .immediate))
                if activity.status == .pending { replan.insert(day) }
            }
        }

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
            } else if input.canStart, !ledger.hasLesson(today) || replan.contains(today) {
                if now >= open {
                    steps.append(.start(LessonActivityAttributes(day: today),
                                        Self.runningLessonContent(todayDay, style, now: now)))
                    ledger.recordLesson(today)
                } else if input.preferences.autoStart, open.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                    steps.append(.schedule(LessonActivityAttributes(day: today), Self.scheduledLessonContent(todayDay, style),
                                           at: open, alert: lessonAlert(todayDay)))
                    ledger.recordLesson(today)
                }
            }
        }

        if !todayBusy, keptPending == nil, input.canStart, input.preferences.autoStart, let nextDay,
           !ledger.hasLesson(nextDay.day) || replan.contains(nextDay.day) {
            let open = nextDay.firstStart.addingTimeInterval(-LiveActivityPolicy.lessonLead)
            if open.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                steps.append(.schedule(LessonActivityAttributes(day: nextDay.day), Self.scheduledLessonContent(nextDay, style),
                                       at: open, alert: lessonAlert(nextDay)))
                ledger.recordLesson(nextDay.day)
            }
        }
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

    func planExams(_ input: LiveActivityPlanInput, ledger: inout LiveActivityLedger,
                   events: inout [Date]) -> [ExamActivityStep] {
        let now = input.now
        let running = input.exams.filter(\.status.isRunning).sorted { $0.id < $1.id }
        guard input.preferences.examEnabled, input.entitled, input.systemEnabled else {
            return running.map { .end(id: $0.id, nil, .immediate) }
        }
        let style = input.sources.style
        let context = input.sources.context
        let today = context.localDate(of: now)
        let exams = input.sources.exams.filter { $0.close > now }
        var steps: [ExamActivityStep] = []
        var kept: [UUID: ExamActivityExisting] = [:]
        var replan = Set<UUID>()

        for activity in running {
            let id = activity.attributes.examID
            guard let exam = input.sources.exams.first(where: { $0.id == id }), kept[id] == nil else {
                steps.append(.end(id: activity.id, nil, .immediate))   // deleted, completed, moved away, or a duplicate
                continue
            }
            if now >= exam.close {
                steps.append(.end(id: activity.id, Self.finalExamContent(exam, style),
                                  Self.dismissal(endedAt: exam.close, now: now)))
            } else if activity.status == .pending {
                if activity.content == Self.scheduledExamContent(exam, style) {
                    kept[id] = activity
                } else {
                    steps.append(.end(id: activity.id, nil, .immediate))
                    replan.insert(id)
                }
            } else if exam.day != today {
                steps.append(.end(id: activity.id, nil, .immediate))   // moved to a later day
                replan.insert(id)
            } else {
                kept[id] = activity
                let desired = Self.runningExamContent(exam, style, now: now)
                if activity.content != desired { steps.append(.update(id: activity.id, desired)) }
            }
        }

        for exam in exams {
            events += [Self.window(exam, context).lowerBound, exam.start, exam.close]
        }
        // Started now: the first exam of today whose window is open.
        if let current = exams.first(where: { $0.day == today && Self.window($0, context).contains(now) }),
           kept[current.id] == nil, input.canStart, !ledger.hasExam(current.id) || replan.contains(current.id) {
            steps.append(.start(ExamActivityAttributes(examID: current.id), Self.runningExamContent(current, style, now: now)))
            ledger.recordExam(current.id)
            kept[current.id] = ExamActivityExisting(id: "", attributes: .init(examID: current.id), status: .active,
                                                    content: Self.runningExamContent(current, style, now: now))
        }
        // Scheduled: the first exam whose window opens later, if none is pending yet.
        let hasPending = kept.values.contains { $0.status == .pending }
        if !hasPending, input.canStart, input.preferences.autoStart,
           let upcoming = exams.first(where: { Self.window($0, context).lowerBound > now }), kept[upcoming.id] == nil,
           !ledger.hasExam(upcoming.id) || replan.contains(upcoming.id) {
            let at = Self.scheduledStart(upcoming, context)
            if at.timeIntervalSince(now) >= LiveActivityPolicy.minimumScheduleDelay {
                steps.append(.schedule(ExamActivityAttributes(examID: upcoming.id), Self.scheduledExamContent(upcoming, style),
                                       at: at, alert: examAlert(upcoming)))
                ledger.recordExam(upcoming.id)
            }
        }
        return steps
    }

    /// The exam's window: from max(start of its day, start − `examLead`) to its close.
    public static func window(_ exam: LiveActivityExam, _ context: CalendarContext) -> Range<Date> {
        let open = max(context.startOfDay(exam.day), exam.start.addingTimeInterval(-LiveActivityPolicy.examLead))
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
