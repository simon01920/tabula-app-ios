// SwiftData macro probe. UNCOMPILED. Expected to FAIL under xtool 1.20.1 with
// "external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found" (xtool #149).
// APIs (docs checked): SwiftData.Model() iOS 17, Query iOS 17, EnvironmentValues.modelContext,
//   ModelContext.insert(_:), Scene.modelContainer(for:inMemory:isAutosaveEnabled:isUndoEnabled:onSetup:).
import SwiftData
import SwiftUI

@Model
final class ProbeItem {
    var title: String
    var createdAt: Date

    init(title: String, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
    }
}

@main
struct SwiftDataProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeListView()
        }
        .modelContainer(for: ProbeItem.self)
    }
}

struct ProbeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProbeItem.createdAt) private var items: [ProbeItem]

    var body: some View {
        List {
            Button {
                context.insert(ProbeItem(title: "Item \(items.count + 1)"))
            } label: {
                Text(verbatim: "Insert item (count must grow)")
            }
            ForEach(items) { item in
                Text(verbatim: item.title)
            }
        }
    }
}
