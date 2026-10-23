// Phase 0 platform probes (env-ci-engineer). COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629).
// Developer-facing debug UI: labels are verbatim (not localized) on purpose; only the
// "Localization" rows exercise the String Catalog.
//
// Macro isolation (CLAUDE.md rule 5): the DEFAULT build of this file uses no Swift macros.
// Everything macro-based sits behind `#if TABULA_MACRO_PROBES` (set by `TABULA_MACRO_PROBES=1` at
// manifest evaluation via `scripts/xtool-dev.sh --macro-probes`, and always on the XcodeGen/CI path).
// Note: in the Xcode 27 SDK `@State` is a SwiftUI *macro* (OpenAppleMacros README), so the base
// variant uses @StateObject/@Published (property wrappers) instead.
//
// What each row proves on device (see the checklist in docs/ENVIRONMENT.md §15):
//   Build path ........ SWIFT_PACKAGE is defined for SwiftPM targets (xtool path), not for Xcode app targets.
//   Macro probes ...... ON = macro variant compiled, OFF = base variant.
//   Bundle ID ......... shows the xtool "XTL-<ID>." prefix when installed via xtool.
//   App Group ......... container URL + UserDefaults + file round-trip; widget writes back what it read.
//   Localization ...... raw keys (e.g. "probe.hello") => the String Catalog was not compiled into .lproj.
//   @Observable ....... (macro variant) the tick counter updates the row => Observation macro works.
//   @Entry ............ (macro variant) shows the value injected by DebugScreen => @Entry expanded.
//   AppIntent ......... perform() runs in-process; Shortcuts-app listing is a manual check.
//   @Generable ........ (macro variant) schema dump renders => FoundationModels macros expanded.
//
// APIs (checked against developer.apple.com JSON docs; URLs in docs/ENVIRONMENT.md §12):
//   Observation.Observable() iOS 17 · SwiftUI.Entry() · EnvironmentKey · EnvironmentValues · State ·
//   StateObject iOS 14 · Combine.ObservableObject · Combine.Published · Environment ·
//   List/Section/Button · onAppear(perform:) · UIDevice.systemName/systemVersion/model ·
//   FileManager.containerURL(forSecurityApplicationGroupIdentifier:) · UserDefaults(suiteName:) ·
//   WidgetCenter.reloadAllTimelines() · Bundle.bundleIdentifier/localizations/preferredLocalizations ·
//   Bundle.localizedString(forKey:value:table:) · String(format:locale:_:) ·
//   String(localized:table:bundle:locale:comment:) iOS 15 · Date.ISO8601Format(_:) · URL.appending(path:)
// Compiled only in DEBUG builds (PHASE2_PLAN §0.2): Release archives/TestFlight contain no probe code.
#if DEBUG
import Combine
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit
import WidgetKit
#if TABULA_MACRO_PROBES
import Observation
#endif

// MARK: - Environment value (@Entry macro in the macro variant, plain EnvironmentKey otherwise)

enum PlatformProbeConstants {
    static let injectedEntryToken = "injected-by-DebugScreen"
    static let defaultEntryToken = "default (NOT injected)"

    #if TABULA_MACRO_PROBES
    static let macroProbesEnabled = true
    #else
    static let macroProbesEnabled = false
    #endif
}

#if TABULA_MACRO_PROBES
extension EnvironmentValues {
    @Entry var phase0ProbeToken: String = PlatformProbeConstants.defaultEntryToken
}
#else
private struct Phase0ProbeTokenKey: EnvironmentKey {
    static let defaultValue = PlatformProbeConstants.defaultEntryToken
}

extension EnvironmentValues {
    var phase0ProbeToken: String {
        get { self[Phase0ProbeTokenKey.self] }
        set { self[Phase0ProbeTokenKey.self] = newValue }
    }
}
#endif

// MARK: - Static platform facts

enum PlatformInfo {
    #if SWIFT_PACKAGE
    static let buildPath = "xtool / SwiftPM (SWIFT_PACKAGE defined)"
    #else
    static let buildPath = "XcodeGen / xcodebuild (SWIFT_PACKAGE not defined)"
    #endif

    /// Hardware identifier such as "iPhone17,2" (uname machine field).
    static func hardwareModel() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}

// MARK: - Localization probe

enum LocalizationProbe {
    /// Keys used in Resources/Localizable.xcstrings.
    static let helloKey = "probe.hello"
    static let lessonsKey = "probe.lessons %lld"

    /// Current-language lookup through the normal API (main bundle, device language).
    static func currentHello() -> String {
        String(localized: "probe.hello")
    }

    static func currentLessons(_ count: Int) -> String {
        String(localized: "probe.lessons \(count)")
    }

    /// Loads a specific `<code>.lproj` from the main bundle so both languages can be shown
    /// regardless of the device language. `nil` => that localization is not in the bundle.
    static func languageBundle(_ code: String) -> Bundle? {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// One line per language: hello + plural samples (1, 3, 5) — Slovak exercises one/few/other.
    /// The table lookup uses the explicit `<code>.lproj` bundle, and the plural format is applied with
    /// `String(format:locale:)` and that language's locale, so the Slovak rules are exercised even on an
    /// English device. Remaining uncertainty (device check): whether Foundation picks the plural rule
    /// from the `locale:` argument or from the process language — the expected Slovak output is
    /// "1 hodina · 3 hodiny · 5 hodín".
    static func sampleLine(_ code: String) -> (String, ProbeStatus) {
        guard let bundle = languageBundle(code) else {
            return ("\(code).lproj missing in app bundle", .fail)
        }
        let locale = Locale(identifier: code)
        let greeting = bundle.localizedString(forKey: helloKey, value: nil, table: nil)
        let format = bundle.localizedString(forKey: lessonsKey, value: nil, table: nil)
        let samples = [1, 3, 5]
            .map { String(format: format, locale: locale, $0) }
            .joined(separator: " · ")
        let isRaw = greeting == helloKey || format == lessonsKey
        return ("\(greeting) | \(samples)", isRaw ? .fail : .pass)
    }
}

// MARK: - Section state (base variant: ObservableObject + @Published, no macros)

@MainActor
final class PlatformProbeModel: ObservableObject {
    @Published var appGroupID = AppGroup.identifier(forBundleIdentifier: Bundle.main.bundleIdentifier)
    @Published var containerResult = "not run"
    @Published var containerStatus: ProbeStatus = .pending
    @Published var defaultsResult = "not run"
    @Published var defaultsStatus: ProbeStatus = .pending
    @Published var fileResult = "not run"
    @Published var fileStatus: ProbeStatus = .pending
    @Published var widgetSaw = "not read yet"
    @Published var intentLastRun = "never"
    @Published var intentInProcess = "not run"
    @Published var intentStatus: ProbeStatus = .pending

    func runAppGroupRoundTrip() {
        let groupID = appGroupID
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            containerStatus = .fail
            containerResult = "nil: App Group not in signed entitlements/profile (free team? xtool #284)"
            defaultsStatus = .fail
            defaultsResult = "skipped (no container)"
            fileStatus = .fail
            fileResult = "skipped (no container)"
            return
        }
        containerStatus = .pass
        containerResult = container.path

        let stamp = Date.now.ISO8601Format()
        if let defaults = UserDefaults(suiteName: groupID) {
            defaults.set(stamp, forKey: Phase0ProbeKeys.appWrite)
            let readBack = defaults.string(forKey: Phase0ProbeKeys.appWrite)
            defaultsStatus = readBack == stamp ? .pass : .fail
            defaultsResult = "wrote \(stamp) · read \(readBack ?? "nil")"
        } else {
            defaultsStatus = .fail
            defaultsResult = "UserDefaults(suiteName:) returned nil"
        }

        let fileURL = container.appending(path: Phase0ProbeKeys.fileName)
        do {
            try Data(stamp.utf8).write(to: fileURL, options: .atomic)
            let readBack = try String(contentsOf: fileURL, encoding: .utf8)
            fileStatus = readBack == stamp ? .pass : .fail
            fileResult = "\(Phase0ProbeKeys.fileName): \(readBack)"
        } catch {
            fileStatus = .fail
            fileResult = "error: \(error.localizedDescription)"
        }

        // Ask WidgetKit to re-run the widget's timeline provider, which reads the value back.
        WidgetCenter.shared.reloadAllTimelines()
        refreshReadBacks()
    }

    func refreshReadBacks() {
        let defaults = UserDefaults(suiteName: appGroupID)
        widgetSaw = defaults?.string(forKey: Phase0ProbeKeys.widgetSaw)
            ?? "nothing yet: add the Tabula widget, run the round-trip, wait, tap Refresh"
        if let seconds = defaults?.object(forKey: Phase0ProbeKeys.intentRun) as? Double {
            intentLastRun = Date(timeIntervalSince1970: seconds).ISO8601Format()
        }
    }

    func runIntentInProcess() async {
        switch await IntentProbe.performInProcess() {
        case .success:
            intentStatus = .pass
            intentInProcess = "perform() returned"
        case .failure(let error):
            intentStatus = .fail
            intentInProcess = "perform() threw: \(error.localizedDescription)"
        }
        refreshReadBacks()
    }
}

// MARK: - @Observable macro probe (macro variant only)

#if TABULA_MACRO_PROBES
@MainActor
@Observable
final class ObservationTickProbe {
    var ticks = 0
}
#endif

// MARK: - Section

/// The four areas of this probe; DebugScreen can show a subset (`-TabulaScreen debug-<area>`).
enum PlatformProbePart: CaseIterable, Hashable, Sendable {
    case platform, appGroup, localization, macros
}

struct PlatformProbesSection: View {
    var parts: Set<PlatformProbePart> = Set(PlatformProbePart.allCases)
    @StateObject private var model = PlatformProbeModel()
    @Environment(\.phase0ProbeToken) private var entryToken
    #if TABULA_MACRO_PROBES
    @State private var tickProbe = ObservationTickProbe()   // @State is itself a macro in the Xcode 27 SDK
    #endif

    var body: some View {
        if parts.contains(.platform) { platformSection }
        if parts.contains(.appGroup) { appGroupSection }
        if parts.contains(.localization) { localizationSection }
        if parts.contains(.macros) { macroSection }
    }

    private var platformSection: some View {
        Section {
            ProbeRow("Build path", value: PlatformInfo.buildPath)
            ProbeRow(
                "Macro probes",
                value: PlatformProbeConstants.macroProbesEnabled
                    ? "ON (TABULA_MACRO_PROBES)" : "OFF (base variant, no macros)"
            )
            ProbeRow("OS", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
            ProbeRow("Device", value: "\(UIDevice.current.model) · \(PlatformInfo.hardwareModel())")
            ProbeRow(
                "Locale",
                value: "\(Locale.current.identifier) · preferred: \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))"
            )
            ProbeRow(
                "Time zone · first weekday",
                value: "\(TimeZone.current.identifier) · \(Calendar.current.firstWeekday)"
            )
            ProbeRow(
                "Bundle ID",
                value: Bundle.main.bundleIdentifier ?? "nil",
                status: AppGroup.isXtoolSigned(bundleIdentifier: Bundle.main.bundleIdentifier) ? .info : .pass
            )
            ProbeRow("App version", value: PlatformInfo.appVersion)
            ProbeRow("Core schema", value: "v\(TimetableCoreInfo.schemaVersion)")
        } header: {
            Text(verbatim: "Platform")
        }
    }

    private var appGroupSection: some View {
        Section {
            ProbeRow("App Group ID (resolved)", value: model.appGroupID)
            ProbeRow("Container URL", value: model.containerResult, status: model.containerStatus)
            ProbeRow("UserDefaults round-trip", value: model.defaultsResult, status: model.defaultsStatus)
            ProbeRow("File round-trip", value: model.fileResult, status: model.fileStatus)
            ProbeRow("Widget read-back", value: model.widgetSaw)
            Button {
                model.runAppGroupRoundTrip()
            } label: {
                Text(verbatim: "Run App Group round-trip + reload widgets")
            }
            Button {
                model.refreshReadBacks()
            } label: {
                Text(verbatim: "Refresh read-backs")
            }
        } header: {
            Text(verbatim: "App Group & widget")
        }
    }

    private var localizationSection: some View {
        let current = LocalizationProbe.currentHello()
        let en = LocalizationProbe.sampleLine("en")
        let sk = LocalizationProbe.sampleLine("sk")
        return Section {
            ProbeRow(
                "Current language",
                value: "\(current) | \(LocalizationProbe.currentLessons(2))",
                status: current == LocalizationProbe.helloKey ? .fail : .pass
            )
            ProbeRow("en.lproj", value: en.0, status: en.1)
            ProbeRow("sk.lproj (expect 1 hodina · 3 hodiny · 5 hodín)", value: sk.0, status: sk.1)
            ProbeRow(
                "Bundle localizations",
                value: "\(Bundle.main.localizations) · preferred \(Bundle.main.preferredLocalizations)"
            )
        } header: {
            Text(verbatim: "Localization (String Catalog)")
        } footer: {
            Text(verbatim: "FAIL with raw keys such as probe.hello means the catalog was not compiled into .lproj tables.")
        }
    }

    private var macroSection: some View {
        Section {
            #if TABULA_MACRO_PROBES
            ProbeRow(
                "@Observable",
                value: "ticks = \(tickProbe.ticks)",
                status: tickProbe.ticks > 0 ? .pass : .pending
            )
            Button {
                tickProbe.ticks += 1
            } label: {
                Text(verbatim: "Tick (row above must update)")
            }
            ProbeRow(
                "@Entry environment value",
                value: entryToken,
                status: entryToken == PlatformProbeConstants.injectedEntryToken ? .pass : .fail
            )
            #else
            ProbeRow("@Observable", value: "not built (base variant)", status: .info)
            ProbeRow("Environment value (plain EnvironmentKey, no @Entry)", value: entryToken, status: .info)
            #endif
            ProbeRow("AppIntent perform() in-process", value: model.intentInProcess, status: model.intentStatus)
            ProbeRow("AppIntent last run (any source)", value: model.intentLastRun)
            Button {
                Task { await model.runIntentInProcess() }
            } label: {
                Text(verbatim: "Run AppIntent in-process")
            }
            ProbeRow(
                "@Generable schema",
                value: GenerableProbe.schemaSummary(),
                status: GenerableProbe.isBuilt ? .pass : .info
            )
        } header: {
            Text(verbatim: "Macros & App Intents")
        } footer: {
            Text(verbatim: "Manual: open Shortcuts, search \"Tabula\"; are the App Shortcuts \"What's Next\" and \"Add Homework\" listed (TestFlight only, PHASE4_DEVICE B3.14)? The probe action is in the Shortcuts action library (DEBUG builds); run it, then tap Refresh read-backs.")
        }
        .onAppear { model.refreshReadBacks() }
    }
}
#endif // DEBUG
