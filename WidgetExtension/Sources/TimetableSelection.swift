// Timetable choice for *Now & Next* and *Today* (Phase 4 B3): the widget configuration intent, the timetable entity and
// its query. Used only when the extension is compiled with `TABULA_APP_INTENTS` (project.yml, Xcode / TestFlight: the
// path that generates App Intents metadata); the xtool build keeps the B1 `StaticConfiguration`s (RISKS #19).
//
// The query runs in this extension and reads only the App Group snapshot (`WidgetSnapshot.timetables`, written by the
// app); it never opens the database. Without an App Group (free team) or before the app wrote a B3 snapshot it offers
// nothing and the widget follows the active timetable. Choice rules: TimetableUI/Widgets/WidgetTimetableChoice.swift.
// The parameter is optional: no choice (the default for every widget) = the active timetable, the pre-B3 behaviour.
// APIs (iOS 26/27 SDK interface + docs, checked 2026-10-22): WidgetConfigurationIntent (iOS 17), AppEntity
//   (typeDisplayRepresentation, defaultQuery, displayRepresentation), EntityQuery (entities(for:), suggestedEntities():
//   "If the entity for a provided identifier is no longer available, omit it"), TypeDisplayRepresentation,
//   DisplayRepresentation(title:subtitle:), @Parameter(title:) with an optional entity.
import AppIntents
import Foundation
import TimetableUI

/// One timetable, as the widget configuration lists it.
struct TimetableEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "intent.timetable.typeName" }
    static var defaultQuery: TimetableEntityQuery { TimetableEntityQuery() }

    /// `Timetable.ID.uuidString`.
    let id: String
    let name: String
    let isActive: Bool

    init(_ choice: TimetableChoice) {
        id = choice.id
        name = choice.name
        isActive = choice.isActive
    }

    var displayRepresentation: DisplayRepresentation {
        // The user's name as is (an interpolated resource: its "%@" key is not in the catalog).
        DisplayRepresentation(title: "\(name)", subtitle: isActive ? "intent.timetable.activeSubtitle" : nil)
    }
}

/// The timetables in the app's snapshot.
struct TimetableEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TimetableEntity] {
        TimetableChoiceQuery.entities(for: identifiers, in: WidgetSnapshotReader.read().snapshot).map(TimetableEntity.init)
    }

    func suggestedEntities() async throws -> [TimetableEntity] {
        TimetableChoiceQuery.suggested(in: WidgetSnapshotReader.read().snapshot).map(TimetableEntity.init)
    }
}

/// The configuration of *Now & Next* and *Today*.
struct SelectTimetableIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "intent.selectTimetable.title" }
    static var description: IntentDescription? { IntentDescription("intent.selectTimetable.description") }
    /// Widget configuration only, never a Shortcuts action (final QA m5; the SDK interface does not show the default).
    static var isDiscoverable: Bool { false }

    /// `nil` = follow the active timetable.
    @Parameter(title: "intent.param.timetable")
    var timetable: TimetableEntity?

    init() {}
}
