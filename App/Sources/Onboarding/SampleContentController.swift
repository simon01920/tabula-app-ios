// "Just look around" (UX_OVERHAUL_PLAN D8): the device-local record of the sample timetable onboarding created, and
// the banner "This is sample data · Remove" above the main tabs. What Remove deletes is decided by
// `SampleContent.removalMutation` (TimetableUI, Linux-tested): only the sample timetable with its children and the
// sample task / exam; the user's own content stays. Closing the banner keeps the sample as ordinary data.
// The record lives in the App Group UserDefaults (`UserDefaultsOnboardingLocalStore`), never in the synced database.
// APIs: Observation.Observable, View.confirmationDialog(_:isPresented:titleVisibility:actions:message:) (iOS 15),
//       Button(role: .destructive / .cancel), TimetableUI AdaptiveStack, ShapeStyle.bar.
import Foundation
import Observation
import SwiftUI
import TimetableCore
import TimetableUI

@MainActor
@Observable
final class SampleContentController {
    /// The sample content still offered for removal (`nil` = no banner).
    private(set) var record: SampleContentRecord?
    @ObservationIgnored let localStore: any OnboardingLocalStore

    init(localStore: any OnboardingLocalStore) {
        self.localStore = localStore
        record = localStore.loadSample()
    }

    /// Records (or forgets, `nil`) the sample content.
    func remember(_ record: SampleContentRecord?) {
        self.record = record
        localStore.saveSample(record)
    }

    /// The record when its timetable is still live in `database` (a stale record is forgotten).
    func activeRecord(in database: TabulaDatabase?) -> SampleContentRecord? {
        guard let record, let database else { return nil }
        return SampleContent.isActive(record, in: database) ? record : nil
    }

    /// Removes the sample content. `false` when the change was refused (nothing changed; the banner stays).
    @discardableResult
    func remove(model: AppModel) -> Bool {
        guard let record, let database = model.database else { return false }
        guard let mutation = SampleContent.removalMutation(record, in: database) else {
            remember(nil)   // already gone
            return true
        }
        guard case .applied = model.apply(mutation) else { return false }
        remember(nil)
        return true
    }

    #if DEBUG
    /// Screenshot route: marks the seed's active timetable as sample content (in-memory store in seed runs).
    func markActiveTimetableAsSample(in model: AppModel) {
        guard let database = model.database, let timetable = model.activeTimetable else { return }
        remember(SampleContent.record(for: timetable.id, in: database))
    }
    #endif
}

/// The banner above the main tabs while sample content exists: "This is sample data", Remove (with confirmation),
/// and a close button that keeps the data. Icon + text; the text and Remove wrap / stack at large text sizes.
struct SampleDataBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(SampleContentController.self) private var samples
    @State private var confirming = false
    @State private var failed = false

    var body: some View {
        if let record = samples.activeRecord(in: model.database) {
            banner(record)
        }
    }

    private func banner(_ record: SampleContentRecord) -> some View {
        return HStack(alignment: .top, spacing: 8) {
            AdaptiveStack(spacing: 10) {
                Label {
                    Text("sample.banner.title")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkles")
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { confirming = true } label: {
                    Text("sample.banner.remove").frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            Button { samples.remember(nil) } label: {
                Image(systemName: "xmark")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("store.banner.dismiss"))
            .accessibilityHint(Text("sample.banner.dismiss.hint"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .confirmationDialog(Text("sample.remove.title"), isPresented: $confirming, titleVisibility: .visible) {
            Button(role: .destructive) {
                if !samples.remove(model: model) { failed = true }
            } label: {
                Text("sample.remove.confirm")
            }
            Button(role: .cancel) { } label: { Text("editor.common.cancel") }
        } message: {
            Text(verbatim: message(for: record))
        }
        .alert(Text("sample.remove.failed.title"), isPresented: $failed) {
            Button { } label: { Text("onboarding.error.ok") }
        } message: {
            Text("onboarding.error.message")
        }
    }

    /// Full sentences only (no fragments): the scope, plus what happens to the user's own additions when there are any.
    private func message(for record: SampleContentRecord) -> String {
        let renderer = model.renderer
        var sentences = [renderer.string(forKey: "sample.remove.message")]
        if let database = model.database {
            let impact = SampleContent.impact(of: record, in: database)
            if impact.addedByUser > 0 {
                sentences.append(renderer.format(key: "sample.remove.addedByUser",
                                                 arguments: [.integer(Int64(impact.addedByUser))]))
            }
            if impact.unlinkedItems > 0 {
                sentences.append(renderer.format(key: "sample.remove.unlinked",
                                                 arguments: [.integer(Int64(impact.unlinkedItems))]))
            }
        }
        return sentences.joined(separator: "\n\n")
    }
}
