// Shared pure helpers of the editors (stage B3): the field rule for editor inputs, text cleaning, new-entity
// placeholders and time/date bridges for SwiftUI `DatePicker`s. Linux-tested.
//
// Field rule (PHASE2_PLAN §0.8): a field the timetable disables is hidden in the editors too (its stored value is
// kept untouched); an enabled field is an input even when empty (the *absence* rule applies to read-only views).
import Foundation
import TimetableCore

/// Which optional lesson fields an editor offers.
public enum EditorFieldPolicy {
    /// The optional lesson fields enabled by `visibility`, in presentation order.
    public static func shownFields(_ visibility: FieldVisibility) -> [LessonField] {
        LessonField.knownValues.filter { visibility.isVisible($0) }
    }

    /// `true` when the editor offers an input for `field`.
    public static func isShown(_ field: LessonField, in visibility: FieldVisibility) -> Bool {
        visibility.isVisible(field)
    }
}

/// Text cleaning shared by all drafts.
public enum EditorText {
    /// `text` trimmed, or `nil` when blank (an empty optional field is stored as absent).
    public static func trimmedOrNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trimmed, non-blank items in order.
    public static func cleanedList(_ items: [String]) -> [String] {
        items.compactMap(trimmedOrNil)
    }

    /// The first user-perceived character of `text` (an emoji field holds exactly one), or `nil` when blank.
    public static func firstCharacter(_ text: String) -> String? {
        trimmedOrNil(text).flatMap { $0.first.map { String($0) } }
    }
}

/// Placeholders for entities that do not exist yet (`AppModel.apply` stamps the real metadata on creation).
public enum EditorEntities {
    /// Metadata of a not-yet-created entity.
    public static let placeholderMeta = EntityMeta(createdAt: .zero, updatedAt: .zero)
}

/// Bridges `LocalTime`/`LocalDate` to `Date` for `DatePicker` in a fixed UTC gregorian calendar, so the picker's
/// wall-clock fields equal the stored local values whatever the device time zone is. Use together with
/// `.environment(\.timeZone, LocalDateBridge.timeZone)` and `.environment(\.calendar, LocalDateBridge.calendar)`.
public enum LocalDateBridge {
    /// UTC.
    public static let timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    /// Gregorian calendar in UTC.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The same calendar with `locale` (for `.environment(\.calendar, …)` so the picker formats like the app).
    public static func calendar(locale: Locale) -> Calendar {
        var calendar = Self.calendar
        calendar.locale = locale
        return calendar
    }

    /// The instant whose UTC wall clock is `date` at `time`.
    public static func instant(_ date: LocalDate, _ time: LocalTime = .midnight) -> Date {
        var parts = DateComponents()
        parts.year = date.year
        parts.month = date.month
        parts.day = date.day
        parts.hour = time.hour
        parts.minute = time.minute
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// The local time of day of `instant` (UTC wall clock).
    public static func time(_ instant: Date) -> LocalTime {
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        return LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0) ?? .midnight
    }

    /// The local date of `instant` (UTC wall clock).
    public static func date(_ instant: Date, fallback: LocalDate) -> LocalDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return LocalDate(year: parts.year ?? fallback.year, month: parts.month ?? fallback.month,
                         day: parts.day ?? fallback.day) ?? fallback
    }
}

/// Day choices of a timetable (weekdays or cycle days) in presentation order.
public enum DayChoices {
    /// Weekdays in `firstWeekday` order restricted to the enabled days, or cycle days `1...length`.
    public static func keys(for timetable: Timetable, firstWeekday: Weekday) -> [DayKey] {
        switch timetable.rotation {
        case .dayCycle(let cycle):
            guard DayCycle.validLengths.contains(cycle.length) else { return [] }
            return (1...cycle.length).map { DayKey.cycleDay($0) }
        case .none, .weekCycle:
            return Weekday.week(startingAt: firstWeekday).filter { timetable.enabledDays.contains($0) }.map { DayKey.weekday($0) }
        }
    }

    /// The custom label of a cycle day or cycle week, when the user set one.
    public static func label(at index: Int, in labels: [String]?) -> String? {
        guard let labels, labels.indices.contains(index - 1) else { return nil }
        return EditorText.trimmedOrNil(labels[index - 1])
    }
}
