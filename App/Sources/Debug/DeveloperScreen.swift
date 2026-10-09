// Developer screen (DEBUG only): what the app foundation is doing, usable on a physical device without Xcode —
// data source, launch options, clock/calendar, store status, validation, plus onboarding reset and recovery fault
// injection. Reachable from Settings → Developer and `-TabulaScreen debug-developer`.
// Developer-facing: verbatim strings on purpose (never shipped).
// APIs: List, Section, NavigationLink(destination:label:), Button(role:action:label:),
//       confirmationDialog(_:isPresented:titleVisibility:actions:), LabeledContent (iOS 16), textSelection (iOS).
#if DEBUG
import Combine
import SwiftUI
import TimetableCore
import TimetableUI

/// The Settings entry point (B4 places it as the last section of Settings).
struct DeveloperSettingsLink: View {
    var body: some View {
        Section {
            NavigationLink {
                DeveloperScreen()
            } label: {
                Label { Text("settings.developer") } icon: { Image(systemName: "hammer") }
            }
        }
    }
}

/// Screen state as a property-wrapper object (no macros).
@MainActor
final class DeveloperScreenState: ObservableObject {
    @Published var confirmReset = false
    @Published var faultMessage: String?
}

/// Writes broken or newer-version data straight into the store files so the recovery and read-only paths can be
/// exercised on a device (DEBUG only). Pending changes are flushed first; the running app keeps its in-memory
/// copy, so force-quit and relaunch right after (without editing anything) to see the result.
@MainActor
enum StoreFaultInjection {
    static func corrupt(_ directory: URL, model: AppModel, state: DeveloperScreenState) async {
        await model.flush()
        let url = directory.appendingPathComponent("tabula.json")
        do {
            try Data("{ this is not json".utf8).write(to: url, options: .atomic)
            let hasBackup = FileManager.default.fileExists(atPath: directory.appendingPathComponent("tabula.backup.json").path)
            state.faultMessage = "corrupted; backup present: \(hasBackup ? "yes → expect restore banner" : "NO → expect blocking error screen (make 2 changes first)")"
        } catch {
            state.faultMessage = "failed: \(error)"
        }
    }

    static func setSchemaVersion(_ version: Int, _ directory: URL, model: AppModel, state: DeveloperScreenState) async {
        await model.flush()
        let url = directory.appendingPathComponent("tabula.json")
        do {
            guard var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                state.faultMessage = "tabula.json is not a JSON object"
                return
            }
            root["schemaVersion"] = version
            try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]).write(to: url, options: .atomic)
            state.faultMessage = "schemaVersion = \(version); force-quit and relaunch"
        } catch {
            state.faultMessage = "failed: \(error)"
        }
    }
}

struct DeveloperScreen: View {
    @Environment(AppModel.self) private var model
    // No @State here: App/Sources/Debug stays macro-free outside `#if TABULA_MACRO_PROBES` (validate.sh).
    @StateObject private var state = DeveloperScreenState()

    var body: some View {
        List {
            Section {
                row("Data source", dataSource)
                row("Launch route", RouteTable.summary(RouteRegistry.resolve(LaunchContext.options.screen).resolution))
                ForEach(LaunchContext.options.problems, id: \.self) { problem in
                    ProbeRow("Launch argument", value: problem, status: .fail)
                }
            } header: { Text(verbatim: "Launch") }

            Section {
                row("Now", model.now.ISO8601Format() + (model.isClockFixed ? " (fixed)" : ""))
                row("Time zone", model.calendarContext.timeZone.identifier)
                row("First weekday", "\(model.calendarContext.firstWeekday)")
                row("Locale", model.formatter.locale.identifier)
                row("Today", model.formatter.date(model.today, style: .full))
                row("Sample time 13:05", model.formatter.time(LocalTime(hour: 13, minute: 5)!))
            } header: { Text(verbatim: "Clock & calendar") }

            Section {
                row("Phase", "\(model.phase)")
                row("Read-only", model.isReadOnly ? "yes" : "no")
                row("Banners", model.banners.map { "\($0)" }.joined(separator: ", "))
                row("Last change", model.lastMutationLabel ?? "–")
                row("Last save", model.lastSaveOutcome.map { "\($0)" } ?? "–")
                if let database = model.database {
                    let issues = database.validate()
                    row("Validation", "\(issues.filter { $0.severity == .error }.count) errors, "
                        + "\(issues.filter { $0.severity == .warning }.count) warnings")
                    row("Entities", "\(database.timetables.count) timetables, \(database.subjects.count) subjects, "
                        + "\(database.lessons.count) lessons, \(database.overrides.count) overrides")
                    row("Latest HLC", database.latestTimestamp.stringValue)
                }
            } header: { Text(verbatim: "Store") }

            // No "load sample data into the real store" action on purpose (QA 2026-10-09): the scenarios carry fixed
            // IDs, foreign HLC nodes and fixed 2026 dates. Use -TabulaSeed (in-memory) for sample data; real sample
            // data for a user's store comes from onboarding (TimetableCore.SampleData with the app's ids/clock/now).
            Section {
                Button { state.confirmReset = true } label: {
                    Text(verbatim: "Show onboarding again (data is replaced when it finishes)")
                }
            } header: { Text(verbatim: "Actions (go through AppModel.apply)") }

            if case let .file(directory, _) = model.environment.dataSource {
                Section {
                    Button { Task { await StoreFaultInjection.corrupt(directory, model: model, state: state) } } label: {
                        Text(verbatim: "Corrupt tabula.json (then force-quit + relaunch → restore banner)")
                    }
                    Button { Task { await StoreFaultInjection.setSchemaVersion(99, directory, model: model, state: state) } } label: {
                        Text(verbatim: "Mark tabula.json as schema v99 (relaunch → read-only banner)")
                    }
                    Button { Task { await StoreFaultInjection.setSchemaVersion(1, directory, model: model, state: state) } } label: {
                        Text(verbatim: "Set tabula.json back to schema v1 (relaunch → editable)")
                    }
                    if let message = state.faultMessage {
                        ProbeRow("Result", value: message)
                    }
                } header: { Text(verbatim: "Recovery tests (file store only)") }
            }

            Section {
                NavigationLink { DebugScreen(area: .all) } label: { Text(verbatim: "Phase 0 probes") }
            }
        }
        .navigationTitle(Text(verbatim: "Developer"))
        .confirmationDialog(Text(verbatim: "Show onboarding again?"), isPresented: $state.confirmReset, titleVisibility: .visible) {
            Button(role: .destructive) {
                model.apply(.settings { $0.onboardingCompletedAt = nil })
            } label: { Text(verbatim: "Show onboarding") }
        }
    }

    private var dataSource: String {
        switch model.environment.dataSource {
        case let .file(directory, isAppGroup): return "\(isAppGroup ? "App Group" : "Application Support (fallback)"): \(directory.path)"
        case .seed(let kind): return "in-memory seed \(kind.rawValue)"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        ProbeRow(title, value: value)
    }
}
#endif // DEBUG
