import Foundation

/// String Catalog keys emitted by the reminder planner (Stage 2C). English suggestions and argument order
/// are documented per key; the catalog owns plural variations (`%lld` arguments).
public enum ReminderL10n {
    // Titles. Arg 1: user text.
    /// "%@" — task title.
    public static let taskTitle = "reminder.task.title"
    /// "Exam: %@" — exam title.
    public static let examTitle = "reminder.exam.title"
    /// "%@" — subject name.
    public static let lessonTitle = "reminder.lesson.title"
    /// "Still to do: %@" — task/exam title (follow-ups).
    public static let followUpTitle = "reminder.followUp.title"
    /// "Pack your bag".
    public static let packTonightTitle = "reminder.packTonight.title"
    /// Subtitle "Room %@" — room (lessons, exams).
    public static let room = "reminder.room"

    /// Task bodies by relative day of the due date (seen from the fire date) and whether a time is set.
    /// Args: `dueToday` —; `dueTodayAt` (time); `dueTomorrow` —; `dueTomorrowAt` (time);
    /// `dueInDays` (days, date); `dueInDaysAt` (days, date, time).
    public static let taskBodies = ["dueToday", "dueTodayAt", "dueTomorrow", "dueTomorrowAt", "dueInDays", "dueInDaysAt"]
        .map { "reminder.task.\($0)" }
    /// Exam bodies, same pattern and arguments: "Today", "Today at %@", "Tomorrow", "Tomorrow at %@",
    /// "In %lld days, on %@", "In %lld days, on %@ at %@".
    public static let examBodies = ["today", "todayAt", "tomorrow", "tomorrowAt", "inDays", "inDaysAt"]
        .map { "reminder.exam.\($0)" }
    /// Lesson bodies: `todayAt` (time) "Starts at %@"; `tomorrowAt` (time); `inDaysAt` (days, date, time).
    public static let lessonBodies = ["todayAt", "tomorrowAt", "inDaysAt"].map { "reminder.lesson.\($0)" }
    /// Pack-tonight bodies. Args: (1) item count (the only count: one plural axis per key), (2) first subject
    /// name; `inDays` adds (3) the date. English for `tomorrow`: "%1$lld items to pack for tomorrow, starting
    /// with %2$@".
    public static let packTonightBodies = ["today", "tomorrow", "inDays"].map { "reminder.packTonight.\($0)" }

    /// In-app notice when the window is saturated. Arg: number of reminders that could not be scheduled.
    public static let noticeSaturated = "reminder.notice.saturated"
    /// In-app notice when alarms fell back to notifications. Arg: count.
    public static let noticeAlarmLimit = "reminder.notice.alarmLimit"

    /// Every key the planner can emit (content, notices, tier-change and drop explanations, action titles).
    public static var allKeys: [String] {
        [taskTitle, examTitle, lessonTitle, followUpTitle, packTonightTitle, room]
            + taskBodies + examBodies + lessonBodies + packTonightBodies
            + [noticeSaturated, noticeAlarmLimit]
            + TierChangeReason.allCases.map(\.l10nKey)
            + DropReason.allCases.map(\.l10nKey)
            + ReminderAction.allCases.map(\.l10nKey)
    }
}

/// Builds `ReminderContent` for each source kind.
enum ReminderContentBuilder {
    /// Relative day of the item seen from the reminder's local fire date.
    enum RelativeDay {
        case today, tomorrow, inDays(Int)

        init(fire: LocalDate, item: LocalDate) {
            let delta = fire.days(to: item)
            switch delta {
            case ...0: self = .today
            case 1: self = .tomorrow
            default: self = .inDays(delta)
            }
        }
    }

    static func task(title: String, due: LocalDate, time: LocalTime?, fire: LocalDate, isFollowUp: Bool) -> ReminderContent {
        let titleText = LocalizedText(key: isFollowUp ? ReminderL10n.followUpTitle : ReminderL10n.taskTitle,
                                      args: [.string(title)])
        return ReminderContent(title: titleText, body: datedBody(prefix: "reminder.task.", names: ("dueToday", "dueTomorrow", "dueInDays"),
                                                                 date: due, time: time, fire: fire))
    }

    static func exam(title: String, date: LocalDate, start: LocalTime?, room: String?, fire: LocalDate,
                     isFollowUp: Bool) -> ReminderContent {
        let titleText = LocalizedText(key: isFollowUp ? ReminderL10n.followUpTitle : ReminderL10n.examTitle,
                                      args: [.string(title)])
        return ReminderContent(title: titleText, subtitle: roomText(room),
                               body: datedBody(prefix: "reminder.exam.", names: ("today", "tomorrow", "inDays"),
                                               date: date, time: start, fire: fire))
    }

    static func lesson(_ lesson: ResolvedLesson, fire: LocalDate) -> ReminderContent {
        let body: LocalizedText
        switch RelativeDay(fire: fire, item: lesson.date) {
        case .today: body = LocalizedText(key: "reminder.lesson.todayAt", args: [.time(lesson.startTime)])
        case .tomorrow: body = LocalizedText(key: "reminder.lesson.tomorrowAt", args: [.time(lesson.startTime)])
        case .inDays(let days):
            body = LocalizedText(key: "reminder.lesson.inDaysAt",
                                 args: [.integer(days), .date(lesson.date), .time(lesson.startTime)])
        }
        return ReminderContent(title: LocalizedText(key: ReminderL10n.lessonTitle, args: [.string(lesson.subject.name)]),
                               subtitle: roomText(lesson.room), body: body)
    }

    /// Counts and the first subject name only — never the item texts (lock-screen privacy).
    static func packTonight(_ day: PackTonightDay, fire: LocalDate) -> ReminderContent {
        let first = day.subjects.first?.subject.name ?? ""
        // At most one count per key (one plural axis): the item count. The day distance is shown as a date.
        var args: [LocalizedArgument] = [.integer(day.itemCount), .string(first)]
        let key: String
        switch RelativeDay(fire: fire, item: day.date) {
        case .today: key = "reminder.packTonight.today"
        case .tomorrow: key = "reminder.packTonight.tomorrow"
        case .inDays:
            key = "reminder.packTonight.inDays"
            args.append(.date(day.date))
        }
        return ReminderContent(title: LocalizedText(key: ReminderL10n.packTonightTitle),
                               body: LocalizedText(key: key, args: args))
    }

    private static func roomText(_ room: String?) -> LocalizedText? {
        guard let room = room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty else { return nil }
        return LocalizedText(key: ReminderL10n.room, args: [.string(room)])
    }

    /// `<prefix><today|tomorrow|inDays>[At]` with args `[days, date]` for in-days and a trailing time when timed.
    private static func datedBody(prefix: String, names: (today: String, tomorrow: String, inDays: String),
                                  date: LocalDate, time: LocalTime?, fire: LocalDate) -> LocalizedText {
        let suffix = time == nil ? "" : "At"
        let timeArgs: [LocalizedArgument] = time.map { [.time($0)] } ?? []
        switch RelativeDay(fire: fire, item: date) {
        case .today: return LocalizedText(key: prefix + names.today + suffix, args: timeArgs)
        case .tomorrow: return LocalizedText(key: prefix + names.tomorrow + suffix, args: timeArgs)
        case .inDays(let days):
            return LocalizedText(key: prefix + names.inDays + suffix, args: [.integer(days), .date(date)] + timeArgs)
        }
    }
}
