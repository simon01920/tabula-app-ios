// Opening editor sheets (stage B3, `editor.*` routes) from the timetable views without depending on their types:
// the route is looked up in the registry by id (absent → the action is disabled), and the target travels in the
// environment as `EditorContext` (TimetableUI/Components/EditorContext.swift).
// APIs: View.sheet(item:onDismiss:content:), View.environment(_:_:) (key path), Identifiable.
import SwiftUI
import TimetableCore
import TimetableUI

/// A registered editor route plus what it should edit.
struct EditorPresentation: Identifiable {
    let route: AppRoute
    let context: EditorContext
    let id = UUID()

    /// The presentation of route `routeID`, or `nil` while that editor is not registered (B3 not merged yet).
    @MainActor
    static func make(_ routeID: String, context: EditorContext) -> EditorPresentation? {
        EditorRouteLookup.route(routeID).map { EditorPresentation(route: $0, context: context) }
    }
}

/// Registry lookup of editor routes.
enum EditorRouteLookup {
    /// The route with `id`, if registered.
    @MainActor
    static func route(_ id: String) -> AppRoute? {
        RouteRegistry.routes.first { $0.id == id }
    }

    /// `true` when route `id` is registered.
    @MainActor
    static func isAvailable(_ id: String) -> Bool { route(id) != nil }
}

extension View {
    /// Presents `presentation`'s editor as a sheet with its `EditorContext` in the environment.
    func editorSheet(_ presentation: Binding<EditorPresentation?>) -> some View {
        sheet(item: presentation) { item in
            item.route.makeView()
                .environment(\.editorContext, item.context)
        }
    }
}

/// A timetable-level editor (settings, bell schedule, subjects, terms) opened from the timetable's options menu.
/// These routes edit the active timetable and ignore `EditorContext`.
struct ManagementSheet: Identifiable {
    let route: AppRoute
    var id: String { route.id }

    struct Entry: Identifiable {
        let routeID: String
        let titleKey: String  // existing String Catalog key
        let symbol: String
        var id: String { routeID }
    }

    static let entries: [Entry] = [
        Entry(routeID: "editor.timetable", titleKey: "editor.timetable.title", symbol: "gearshape"),
        Entry(routeID: "editor.bell", titleKey: "editor.bell.title", symbol: "bell"),
        Entry(routeID: "editor.subjects", titleKey: "editor.subjects.title", symbol: "books.vertical"),
        Entry(routeID: "editor.terms", titleKey: "editor.terms.title", symbol: "calendar"),
    ]

    @MainActor
    static func make(_ routeID: String) -> ManagementSheet? {
        EditorRouteLookup.route(routeID).map { ManagementSheet(route: $0) }
    }
}
