// The one widget snapshot build per change (Phase 10 WP2, P3 / C2 / P12), shared by the widget writer
// (WidgetSnapshotWriter, App Group file + WidgetKit reload + Watch) and the Live Activity controller (lesson days).
// Before Phase 10 both built the identical snapshot on the main actor after every change (~200 ms apart), each with
// new resolvers and several full sorted-key encodes; now the first caller builds it with the model's resolvers
// (`AppModel.resolvers`) and the second reuses it (`WidgetSnapshotBuildCache`: same data, context, tier, locale,
// language and minute), including the encoded bytes.
//
// Triggers are unchanged: the writer and the controller still run on every `AppModel.onChange` (.loaded / .data /
// .environment), foreground, flush, timer and background refresh; only the build is shared.
// Contract: `model.resolvers` is read in the same main-actor turn as `model.database` / `model.calendarContext`, and
// the builder uses a resolver only when its timetable value and context match (else it builds one, as before).
import Foundation
import TimetableCore
import TimetableUI

@MainActor
final class WidgetSnapshotSource {
    private weak var model: AppModel?
    private var cache = WidgetSnapshotBuildCache()

    init(model: AppModel) {
        self.model = model
    }

    /// Builds so far (developer diagnostics).
    var buildCount: Int { cache.buildCount }

    /// The snapshot for the model's current state; `nil` while the store is loading or failed to load (nothing may
    /// be written or planned then).
    func current() -> WidgetSnapshotBuild? {
        guard let model, !model.isLoading, model.problem == nil else { return nil }
        return cache.build(database: model.database, now: model.now, context: model.calendarContext,
                           tier: model.entitlements.tier, locale: model.environment.locale(),
                           languageCode: Bundle.main.preferredLocalizations.first, resolvers: model.resolvers)
    }
}
