// Developer screen (DEBUG only): what the app foundation is doing, usable on a physical device without Xcode —
// data source, launch options, clock/calendar, store status, validation, plus demo data, onboarding reset and recovery
// fault injection. Reachable from Settings → Developer and `-TabulaScreen debug-developer`.
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
    @Published var demoKind: SeedKind?
    @Published var demoMessage: String?
}

/// Replaces the store with a sample scenario moved to this week (`DemoData`). The current data is written to
/// `<store>/Backups` first, exactly like a Replace restore (Settings › Backup lists it); no backup → nothing replaced.
@MainActor
enum DemoDataLoader {
    static let kinds: [(kind: SeedKind, name: String)] = [(.secondary, "High school"), (.university, "University"),
                                                          (.elementary, "Elementary")]

    static func load(_ kind: SeedKind, model: AppModel, state: DeveloperScreenState) async {
        guard !model.isReadOnly, let current = model.database,
              let demo = DemoData.database(kind, today: model.today, now: model.now) else {
            state.demoMessage = "not loaded: the store is read-only or not loaded"
            return
        }
        let backup: URL
        do {
            backup = try BackupFolder.write(.make(from: current, createdAt: model.now), label: "pre-demo",
                                            in: model.environment.backupDirectory)
        } catch {
            state.demoMessage = "backup failed, nothing replaced: \(error)"
            return
        }
        let result = model.apply(.restore(demo, mode: .replace))
        guard case .applied = result else {
            state.demoMessage = "not applied (\(result)); backup \(backup.lastPathComponent)"
            return
        }
        await model.flush()
        state.demoMessage = "loaded \(kind.rawValue); backup \(backup.lastPathComponent)"
    }
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
                row("Stranded-data migration", model.strandedMigration.map { "\($0)" } ?? "not run")
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

            // Demo data answers QA 2026-10-09 (fixed IDs, foreign HLC nodes, fixed 2026 dates): DemoData moves the dates to
            // this week and the Replace restore re-stamps every entity with this device's clock; a backup comes first.
            Section {
                ForEach(DemoDataLoader.kinds, id: \.kind) { item in
                    Button { state.demoKind = item.kind } label: { Text(verbatim: item.name) }
                }
                if let message = state.demoMessage {
                    ProbeRow("Result", value: message)
                }
            } header: { Text(verbatim: "Demo data") } footer: {
                Text(verbatim: "Replaces all data. Your data is backed up first: Settings › Backup › Automatic copies.")
            }

            Section {
                Button { state.confirmReset = true } label: {
                    Text(verbatim: "Show onboarding again (finishing it adds a timetable)")
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

            ReminderDebugSection()

            LiveActivityDebugSection()

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
        .confirmationDialog(Text(verbatim: "Replace all data with demo data?"), isPresented: isPresented($state.demoKind),
                            titleVisibility: .visible, presenting: state.demoKind) { kind in
            Button(role: .destructive) {
                Task { await DemoDataLoader.load(kind, model: model, state: state) }
            } label: { Text(verbatim: "Back Up and Replace") }
        } message: { _ in
            Text(verbatim: "A backup of your data is written first; restore it from Settings › Backup "
                + "(attachment files are not in backups and are not restored). "
                + "With iCloud sync on, the demo data syncs to your other devices too.")
        }
    }

    private var dataSource: String {
        switch model.environment.dataSource {
        case let .file(directory, isAppGroup): return "\(isAppGroup ? "App Group" : "Application Support (fallback)"): \(directory.path)"
        case .seed(let kind): return "in-memory seed \(kind.rawValue)"
        }
    }

    private func isPresented<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }

    private func row(_ title: String, _ value: String) -> some View {
        ProbeRow(title, value: value)
    }
}
/// Phase 4 B2: the Live Activity controller's diagnostics (device checklist B2).
struct LiveActivityDebugSection: View {
    @Environment(LiveActivityController.self) private var liveActivities

    var body: some View {
        Section {
            ProbeRow("System enabled", value: "\(liveActivities.systemEnabled)")
            ProbeRow("Last run", value: liveActivities.lastRun)
            ProbeRow("Next evaluation", value: liveActivities.nextEvaluation?.ISO8601Format() ?? "–")
            ProbeRow("Activity running", value: "\(liveActivities.hasRunningActivity)")
            Button {
                Task { await liveActivities.refreshNow() }
            } label: { Text(verbatim: "Run the Live Activity planner now") }
        } header: { Text(verbatim: "Live Activities") }
    }
}
#endif // DEBUG

