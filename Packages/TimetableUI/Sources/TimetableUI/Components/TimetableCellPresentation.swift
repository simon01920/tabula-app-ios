// Presentation rules of the Timetable tab added in Phase 4U stage U4 (Opus H4, H5, H14, M11; Astra F19), without
// SwiftUI. Pure, Linux-tested:
// - `LessonCellBadge`: the single badge slot of a grid cell (cancelled > exam > tasks > change);
// - `NowLinePresentation`: which lesson is "now" and which gutter hour labels the "10:20" now label would cover;
// - `QuickAddScope`: the quick-add header "Every Monday · Week B · Period 7 (13:40–14:25)" from full catalog phrases;
// - `TimetableSubtitle`: the navigation subtitle "12 Oct – 16 Oct · Odd week".
import Foundation
import TimetableCore

/// What the one badge slot of a grid cell shows (Opus H5: "one badge slot with priority exam > task > change").
public enum LessonCellBadge: Equatable, Sendable {
    /// The lesson does not take place. Outranks everything: it is the state of the whole cell (also dimmed and struck
    /// through); its tasks / exam stay in VoiceOver and the lesson detail.
    case cancelled
    /// An exam on this occurrence.
    case exam
    /// Open tasks for this occurrence (count).
    case tasks(Int)
    /// A one-off change (extra lesson, time / room / teacher …), with its symbol.
    case change(symbolName: String)

    /// The badge of a cell, or `nil` when there is nothing to mark.
    public static func make(status: ResolvedLesson.Status, reasons: [ModificationReason],
                            badges: LessonBadges?) -> LessonCellBadge? {
        if status == .cancelled { return .cancelled }
        if let badges, badges.hasExam { return .exam }
        if let badges, badges.openTasks > 0 { return .tasks(badges.openTasks) }
        if let model = LessonStatusBadgeModel.make(status: status, reasons: reasons) {
            return .change(symbolName: model.symbolName)
        }
        return nil
    }

    /// SF Symbol of the badge.
    public var symbolName: String {
        switch self {
        case .cancelled: return AppSymbol.cancelled.name
        case .exam: return LessonBadges.examSymbol
        case .tasks: return LessonBadges.taskSymbol
        case .change(let symbol): return symbol
        }
    }

    /// `true` for one-off changes (cancelled, extra, modified): what the symbol legend explains.
    public var isChange: Bool {
        switch self {
        case .cancelled, .change: return true
        case .exam, .tasks: return false
        }
    }
}

/// "Now" in the timetable views.
public enum NowLinePresentation {
    /// `true` when `lesson` is in progress at `minuteOfDay` on `today` (start inclusive, end exclusive; a cancelled
    /// lesson is never "now").
    public static func isCurrent(_ lesson: ResolvedLesson, today: LocalDate, minuteOfDay: Int) -> Bool {
        lesson.status != .cancelled && lesson.date == today
            && lesson.startTime.minuteOfDay <= minuteOfDay && minuteOfDay < lesson.endTime.minuteOfDay
    }

    /// Hour marks (minute of day) whose gutter label is hidden because the now label at `nowMinute` would overlap it
    /// (closer than `clearanceMinutes`, which the view derives from the label height and the hour height). Without a
    /// now line (`nowMinute == nil`) every label stays.
    public static func hiddenHourMarks(_ marks: [Int], nowMinute: Int?, clearanceMinutes: Int) -> Set<Int> {
        guard let nowMinute else { return [] }
        return Set(marks.filter { abs($0 - nowMinute) < max(0, clearanceMinutes) })
    }

    /// Minutes covered by a label `labelHeight` points tall on an axis of `hourHeight` points per hour (rounded up).
    public static func clearanceMinutes(labelHeight: Double, hourHeight: Double) -> Int {
        guard hourHeight > 0 else { return 0 }
        return Int((labelHeight / hourHeight * 60).rounded(.up))
    }
}

/// The header of the quick-add sheet: quick add creates a **weekly** lesson slot (UX plan Q1), so the header names the
/// repetition ("Every Monday · Week B · Period 7 (13:40–14:25)"), not one date (Opus H14). Each part is a complete
/// catalog phrase; the parts are joined by full-format keys (no concatenated fragments).
public enum QuickAddScope {
    /// Catalog key of "Every Monday" … "Every Sunday".
    public static func everyWeekdayKey(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "timetable.quickAdd.every.monday"
        case .tuesday: return "timetable.quickAdd.every.tuesday"
        case .wednesday: return "timetable.quickAdd.every.wednesday"
        case .thursday: return "timetable.quickAdd.every.thursday"
        case .friday: return "timetable.quickAdd.every.friday"
        case .saturday: return "timetable.quickAdd.every.saturday"
        case .sunday: return "timetable.quickAdd.every.sunday"
        }
    }

    /// Every key this type renders (for `DynamicL10nKeys`).
    public static let allCatalogKeys: [String] = Weekday.allCases.map(everyWeekdayKey) + [
        "timetable.quickAdd.every.numberedDay", "timetable.quickAdd.every.namedDay", "timetable.quickAdd.every.customDay",
        "timetable.quickAdd.slot.period", "timetable.quickAdd.scope.two", "timetable.quickAdd.scope.three",
    ]

    /// "Every Monday" / "Every Day 3" for the target's day key.
    public static func every(_ dayKey: DayKey, userDayLabel: String?, renderer: LocalizedTextRenderer) -> String {
        switch dayKey {
        case .weekday(let weekday):
            return renderer.string(forKey: everyWeekdayKey(weekday))
        case .cycleDay(let index):
            switch CycleLabel.day(dayKey, userLabel: userDayLabel) {
            case .namedDay(let token)?:
                return renderer.format(key: "timetable.quickAdd.every.namedDay", arguments: [.text(token)])
            case .customDay(let label)?:
                return renderer.format(key: "timetable.quickAdd.every.customDay", arguments: [.text(label)])
            default:
                return renderer.format(key: "timetable.quickAdd.every.numberedDay", arguments: [.integer(Int64(index))])
            }
        }
    }

    /// "Period 7 (13:40–14:25)" for a bell-schedule period, else the time range.
    public static func slot(_ target: QuickAddTarget, renderer: LocalizedTextRenderer) -> String {
        let range = renderer.formatter.timeRange(target.start, target.end)
        guard let number = target.lessonNumber, target.periodID != nil else { return range }
        return renderer.format(key: "timetable.quickAdd.slot.period", arguments: [.integer(Int64(number)), .text(range)])
    }

    /// The whole header: "Every Monday · Week B · Period 7 (13:40–14:25)"; without a week cycle the middle part is
    /// absent ("Every Monday · Period 7 (13:40–14:25)").
    public static func text(_ target: QuickAddTarget, cycleWeek: CycleLabel?, userDayLabel: String?,
                            renderer: LocalizedTextRenderer) -> String {
        let every = every(target.dayKey, userDayLabel: userDayLabel, renderer: renderer)
        let slot = slot(target, renderer: renderer)
        if let week = cycleWeek?.text(renderer: renderer) {
            return renderer.format(key: "timetable.quickAdd.scope.three", arguments: [.text(every), .text(week), .text(slot)])
        }
        return renderer.format(key: "timetable.quickAdd.scope.two", arguments: [.text(every), .text(slot)])
    }
}

/// Where "Add Lesson" (toolbar menu, empty-timetable button; Astra F22) starts the new lesson: the first free period of
/// the preferred day (the selected day in day views, else today when shown, else the week's first day), else the
/// first free period of the week, else the first lesson period of the preferred day. `nil` when the week has no lesson
/// rows (free-form timetable without lessons): the editor then opens without a prefilled slot.
public enum AddLessonSlot {
    public static func pick(layout: GridLayout, preferredDate: LocalDate, timetable: Timetable) -> QuickAddTarget? {
        let preferred = layout.columns.first(where: { $0.date == preferredDate && $0.dayKey != nil })
            ?? layout.columns.first(where: { $0.dayKey != nil && $0.isSchoolDay })
        func target(_ slot: GridLayout.Slot) -> QuickAddTarget? {
            QuickAddTarget.make(layout: layout, column: slot.column, row: slot.row, timetable: timetable)
        }
        if let preferred,
           let found = layout.emptySlots.filter({ $0.column == preferred.index }).sorted(by: { $0.row < $1.row })
            .lazy.compactMap(target).first {
            return found
        }
        if let found = layout.emptySlots.sorted(by: { ($0.column, $0.row) < ($1.column, $1.row) }).lazy.compactMap(target).first {
            return found
        }
        guard let preferred, let row = layout.rows.first(where: \.isLessonRow) else { return nil }
        return QuickAddTarget.make(layout: layout, column: preferred.index, row: row.index, timetable: timetable)
    }
}

/// The navigation subtitle of the Timetable tab (iOS 26 `navigationSubtitle`, Opus L2/L8): the shown week's range
/// and, for week cycles, its rotation phrase.
public enum TimetableSubtitle {
    public static let catalogKeys = ["timetable.week.range", "timetable.subtitle.withCycle"]

    /// "12 Oct – 16 Oct · Odd week" (`first`/`last` already formatted).
    public static func text(first: String, last: String, cycle: CycleLabel?, renderer: LocalizedTextRenderer) -> String {
        let range = renderer.format(key: "timetable.week.range", arguments: [.text(first), .text(last)])
        guard let cycle else { return range }
        return renderer.format(key: "timetable.subtitle.withCycle", arguments: [.text(range), .text(cycle.text(renderer: renderer))])
    }
}
