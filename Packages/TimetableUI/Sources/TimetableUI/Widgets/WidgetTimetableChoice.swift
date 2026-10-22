// Timetable choice for the *Now & Next* and *Today* widgets (Phase 4 B3, `AppIntentConfiguration` on builds with App
// Intents metadata). Pure, Linux-tested; the extension's `TimetableEntity` / `TimetableEntityQuery`
// (WidgetExtension/Sources/TimetableSelection.swift) only wrap these functions.
//
// Data: `WidgetSnapshot.timetables` (one `TimetableSection` per live timetable, display order). The active timetable's
// section holds its name only, its days are the snapshot's `days` (unchanged since Stage A). Other timetables carry their
// own days when they fit the 19 000 B budget; the builder adds them after the B1 trim, so a choice never costs the
// active timetable, tasks or exams any data.
//
// Selection rules (`WidgetSnapshot.selecting(timetableID:)`):
//   nothing chosen (the default, also every widget placed before B3 and every StaticConfiguration build) → the active
//   timetable, exactly as before;
//   the active timetable chosen → the same;
//   another timetable with data → its days and following lesson in place of the active one's;
//   another timetable without data (budget) → `nil` snapshot → the widget's "Open Tabula" state (never another
//   timetable's lessons under the chosen name);
//   a chosen timetable that no longer exists (deleted) or a snapshot from before B3 → the active timetable.
import Foundation
import TimetableCore

/// One timetable as the widgets know it.
public struct TimetableSection: Codable, Equatable, Sendable, Identifiable {
    /// `Timetable.ID.uuid`.
    public var id: UUID
    /// User name (shortened to `WidgetSnapshotBuilder.maxTextLength`).
    public var name: String
    /// The app's active timetable (its days are `WidgetSnapshot.days`).
    public var isActive: Bool
    /// Covered days (same range rule as `WidgetSnapshot.days`); `nil` for the active timetable and for one that did
    /// not fit the size budget.
    public var days: [WidgetSnapshot.Day]?
    /// The first lesson after the covered days.
    public var followingLesson: WidgetSnapshot.Lesson?

    enum CodingKeys: String, CodingKey { case id = "i", name = "n", isActive = "a", days = "d", followingLesson = "f" }

    public init(id: UUID, name: String, isActive: Bool, days: [WidgetSnapshot.Day]? = nil,
                followingLesson: WidgetSnapshot.Lesson? = nil) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.days = days
        self.followingLesson = followingLesson
    }

    /// The widgets can show it (active, or its days are in the snapshot).
    public var hasData: Bool { isActive || days != nil }
}

/// A timetable the configuration UI offers.
public struct TimetableChoice: Equatable, Sendable, Identifiable {
    /// `UUID.uuidString` (the App Intents entity identifier).
    public var id: String
    public var name: String
    public var isActive: Bool
}

extension WidgetSnapshot {
    /// The snapshot as the widget configured for `timetableID` should see it (rules in the file header).
    public func selecting(timetableID: String?) -> WidgetSnapshot? {
        guard let timetableID, let id = UUID(uuidString: timetableID), let sections = timetables,
              let section = sections.first(where: { $0.id == id }), !section.isActive else { return self }
        guard let days = section.days else { return nil }
        var copy = self
        copy.days = days
        copy.followingLesson = section.followingLesson
        copy.hasTimetable = true
        return copy
    }

    /// The timetables to offer, in display order (empty for snapshots written before B3 or without a timetable).
    public var timetableChoices: [TimetableChoice] {
        (timetables ?? []).map { TimetableChoice(id: $0.id.uuidString, name: $0.name, isActive: $0.isActive) }
    }
}

/// The logic of the extension's `EntityQuery` (App Intents only asks for identifiers and suggestions).
public enum TimetableChoiceQuery {
    /// The choices for `identifiers`, in the order asked; unknown ones are omitted (EntityQuery docs: "If the entity for
    /// a provided identifier is no longer available, omit it").
    public static func entities(for identifiers: [String], in snapshot: WidgetSnapshot?) -> [TimetableChoice] {
        let all = snapshot?.timetableChoices ?? []
        return identifiers.compactMap { id in all.first { $0.id.caseInsensitiveCompare(id) == .orderedSame } }
    }

    /// Every timetable, display order (the configuration list).
    public static func suggested(in snapshot: WidgetSnapshot?) -> [TimetableChoice] {
        snapshot?.timetableChoices ?? []
    }
}
