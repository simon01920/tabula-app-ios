// One SF Symbol per concept, used app-wide (Phase 4U U1; Opus review M8 "same meaning, different icons" and H5
// "distinct symbols per change"). Pure (Linux-tested: names are unique, well-formed and the change mapping is total);
// the SwiftUI conveniences are at the bottom behind `canImport(SwiftUI)`.
//
// Rules:
// - A concept has exactly one symbol, and a symbol has exactly one meaning (tests enforce unique raw values).
// - Use `AppSymbol` instead of `systemName:` literals in new code. Subject symbols chosen by the user are user data
//   and stay strings.
// - Tab icons map onto concepts (`AppSymbol.Tab`), so the Tasks tab and a task badge always match.
//
// How the names were verified (no SF Symbols list or `UIImage(systemName:)` on Linux, and the xtool Darwin SDK ships
// no CoreGlyphs name table; searched 2026-10-23, see docs/ENVIRONMENT.md "SF Symbol names"):
//   (a) names already rendered in the CI iOS 27 simulator screenshots (docs/ux-review/screens) before U1;
//   (b) new names checked in the SFSafeSymbols source (MIT, generated from Apple's SF Symbols app; `SFSymbol+<n>.swift`
//       files carry the introducing OS): person.2.badge.gearshape (iOS 16), clock.badge.exclamationmark (iOS 15),
//       arrow.left.arrow.right (iOS 14), arrow.right.square, arrow.turn.up.right, bell (iOS 13), backpack and
//       beach.umbrella (iOS 16), checklist (iOS 15);
//   (c) every case is listed with a live `UIImage(systemName:)` check on the DEBUG "Design system" screen
//       (`-TabulaScreen debug.design`), which the CI screenshot run and the device checklist read.
import Foundation
import TimetableCore

/// The app's SF Symbols, one per concept. `rawValue` is the SF Symbol name.
public enum AppSymbol: String, CaseIterable, Sendable {
    // MARK: Lesson fields
    /// Room / location (also exam location). Was a door glyph in Today and Timetable, a map pin in Exams (M8).
    case room = "mappin.and.ellipse"
    /// Building / faculty.
    case building = "building.2"
    /// Teacher.
    case teacher = "person"
    /// Lesson type (lecture, seminar, lab).
    case lessonType = "tag"
    /// Notes.
    case notes = "note.text"
    /// Bring list.
    case bringList = "backpack"
    /// A time of day or time range.
    case time = "clock"

    // MARK: Changes (H5: one distinct symbol per meaning, the same in grid, detail and Today)
    /// The lesson's time changed (also "shortened lessons").
    case timeChanged = "clock.badge.exclamationmark"
    /// The lesson moved to another room or building.
    case roomChanged = "arrow.right.square"
    /// Substitute teacher.
    case substitute = "person.2.badge.gearshape"
    /// Substitute subject (a different subject in this slot).
    case subjectChanged = "arrow.left.arrow.right"
    /// Changed in another way, or in several ways.
    case changed = "pencil.circle"
    /// Cancelled lesson.
    case cancelled = "xmark.circle.fill"
    /// Extra (added) lesson.
    case extraLesson = "plus.circle.fill"
    /// A whole day off (cancel day).
    case cancelledDay = "calendar.badge.minus"
    /// The day follows another day's timetable.
    case followsAnotherDay = "arrow.turn.up.right"
    /// Marker of a day that has changes (column header).
    case dayHasChanges = "exclamationmark.circle"

    // MARK: Work
    /// A task (homework, assignment, to-do) and the Tasks tab.
    case task = "checklist"
    /// An exam and the Exams tab.
    case exam = "graduationcap.fill"
    /// Overdue.
    case overdue = "exclamationmark.triangle.fill"
    /// A date: due date, exam date, calendar (also the Timetable tab).
    case date = "calendar"
    /// Repeats.
    case repeats = "repeat"
    /// Attachments.
    case attachment = "paperclip"
    /// Subtasks of a task.
    case subtasks = "list.bullet.indent"
    /// Exam topics.
    case topics = "list.bullet"
    /// High priority.
    case priorityHigh = "exclamationmark.2"
    /// Urgent priority.
    case priorityUrgent = "exclamationmark.3"
    /// Done (a completed task, a finished state).
    case completed = "checkmark.circle.fill"
    /// Not done yet (an open checkbox).
    case notCompleted = "circle"
    /// Countdown / time left.
    case countdown = "hourglass"
    /// Holidays (days off).
    case holiday = "beach.umbrella"

    // MARK: Reminders
    /// A reminder (notification).
    case reminder = "bell"
    /// A loud alarm (AlarmKit).
    case alarm = "alarm"

    // MARK: App
    /// The Today tab.
    case today = "sun.max"
    /// The Settings tab.
    case settings = "gearshape"
    /// A Pro-only feature.
    case proLocked = "lock.fill"
    /// Add.
    case add = "plus"
    /// Edit.
    case edit = "pencil"
    /// Delete.
    case delete = "trash"
    /// Something needs a look (non-blocking warning).
    case warning = "exclamationmark.triangle"
    /// An error that blocks.
    case error = "xmark.octagon.fill"
    /// Information.
    case info = "info.circle"

    /// The SF Symbol name.
    public var name: String { rawValue }

    /// The symbol of a lesson's change status: cancelled, extra, or the specific change when there is exactly one
    /// reason (time, room/building, substitute teacher, substitute subject), else the generic `changed`.
    /// `nil` for a regular lesson.
    public static func status(_ status: ResolvedLesson.Status, reasons: [ModificationReason]) -> AppSymbol? {
        switch status {
        case .scheduled: return nil
        case .cancelled: return .cancelled
        case .added: return .extraLesson
        case .modified: return change(for: reasons)
        }
    }

    /// The symbol for a set of change reasons (one reason → its own symbol; none or several → `changed`).
    public static func change(for reasons: [ModificationReason]) -> AppSymbol {
        guard reasons.count == 1 else { return .changed }
        switch reasons[0] {
        case .timeChanged: return .timeChanged
        case .roomChanged, .buildingChanged: return .roomChanged
        case .teacherChanged: return .substitute
        case .subjectChanged: return .subjectChanged
        case .lessonTypeChanged, .notesChanged, .bringListChanged: return .changed
        }
    }

    /// Tab icons, mapped onto concepts so a tab and the badges of its content always match.
    public enum Tab {
        public static let today = AppSymbol.today
        public static let timetable = AppSymbol.date
        public static let tasks = AppSymbol.task
        public static let exams = AppSymbol.exam
        public static let settings = AppSymbol.settings
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension Image {
    /// `Image(.room)`: the app's symbol for a concept.
    public init(_ symbol: AppSymbol) {
        self.init(systemName: symbol.rawValue)
    }
}

extension Label where Title == Text, Icon == Image {
    /// `Label("lesson.room", symbol: .room)`: a catalog key with the app's symbol.
    public init(_ titleKey: LocalizedStringKey, symbol: AppSymbol) {
        self.init(titleKey, systemImage: symbol.rawValue)
    }

    /// `Label(verbatim: room, symbol: .room)`: user text (not localised) with the app's symbol.
    public init(verbatim title: String, symbol: AppSymbol) {
        self.init { Text(verbatim: title) } icon: { Image(symbol) }
    }
}
#endif
