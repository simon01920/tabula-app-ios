// The app's single source of truth (PHASE2_PLAN §0.4): owns the `TabulaDatabase` snapshot, applies every change
// through `apply(_:)` (stamp → validate → debounced serial save) and exposes derived, read-only state for views.
// Thin by design: the decisions live in TimetableUI (DatabaseMutation, MutationValidation, PersistenceController,
// StoreLoadOutcome, ShellPhase, ActiveTimetable, CalendarEnvironment, TimetableFormatter), which are Linux-tested.
//
// Views:   @Environment(AppModel.self) private var model
//          model.database / model.activeTimetable / model.resolver(for:) / model.calendarContext / model.now
//          model.formatter / model.renderer / model.entitlements
//          model.apply(.upsert(lesson))   → ApplyResult (.applied(warnings) / .rejected / .failed)
// Reminders: every accepted change and every environment refresh calls `onChange`; the ReminderCoordinator re-plans
//          from it (debounced), so editors never schedule notifications themselves.
// APIs: Observation.Observable (macro; allowed in app code per PHASE2_PLAN §0.1), Task.sleep(for:),
//       NotificationCenter.addObserver(forName:object:queue:using:), MainActor.assumeIsolated,
//       NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification,
//       UIApplication.significantTimeChangeNotification (midnight, carrier time update, DST), NSTimeZone.resetSystemTimeZone()
//       (docs checked 2026-10-10).
import Foundation
import Observation
import UIKit
import TimetableCore
import TimetableUI

/// What `AppModel.apply(_:)` did.
enum ApplyResult: Equatable {
    /// Applied (save scheduled). `warnings` are validation warnings the change introduced (show, never block).
    case applied(warnings: [ValidationIssue])
    /// Refused: the change would introduce validation errors; nothing changed.
    case rejected(errors: [ValidationIssue])
    /// Refused: the store is read-only (newer app version) or not loaded.
    case readOnly
    /// The mutation itself failed (e.g. deleting an unknown ID); nothing changed.
    case failed(MutationError)
}

/// Who asked for a change (`AppModel.apply(_:origin:)`).
enum ApplyOrigin: Equatable, Sendable {
    /// The user saved a task or exam (editor Save, quick add, lesson detail "Add homework", onboarding finish): the
    /// re-plan after it may offer the notification pre-explainer in context (ReminderPermissionOffer, QA fix Q1).
    case userSave
    /// Everything else (toggles, completion, deletes, settings, notification actions, debug tools).
    case other
    /// Data merged from iCloud (`DatabaseMutation.mergeRemote`, Phase 6 S1). Never rejected for validation errors: the
    /// data already exists on another device, and a batch may reference entities of a later batch.
    case sync
}

/// What `AppModel.onChange` reports.
enum AppModelChange: Equatable, Sendable {
    /// The store finished loading.
    case loaded
    /// An accepted `apply(_:origin:)`, with its origin.
    case data(ApplyOrigin)
    /// Calendar context / formatters rebuilt (zone, locale, significant time change, scene active).
    case environment
}

@MainActor
@Observable
final class AppModel {
    // MARK: Stored state

    /// The current snapshot; `nil` before loading finished or when nothing is stored yet.
    private(set) var database: TabulaDatabase?
    private(set) var isLoading = true
    /// Set when nothing can be shown (blocking screen; onboarding is never offered then).
    private(set) var problem: StoreProblem?
    /// Banners in display order; the first is shown.
    private(set) var banners: [StoreBanner] = []
    /// `true` while the stored file belongs to a newer app version.
    private(set) var isReadOnly = false
    /// Warnings introduced by the last accepted change.
    private(set) var lastWarnings: [ValidationIssue] = []
    /// Developer diagnostics (debug screen).
    private(set) var lastSaveOutcome: SaveOutcome?
    private(set) var lastMutationLabel: String?
    /// What the one-time stranded-data migration did this launch (`nil` when it did not run; RISKS #47).
    private(set) var strandedMigration: StrandedStoreMigration.Outcome?

    // MARK: Derived state (rebuilt when data, settings, time zone or locale change what it depends on)
    // Phase 10 P2: each value is assigned only when its inputs changed (`DerivedStateRebuild`), because Observation
    // notifies readers on every assignment, also of an equal value (that re-rendered every tab after each change).

    private(set) var calendarContext: CalendarContext
    private(set) var formatter: TimetableFormatter
    private(set) var renderer: LocalizedTextRenderer
    /// The local date of `now`. Stored (not computed) so views re-render when it changes: it is refreshed at
    /// midnight / DST / clock changes (`significantTimeChangeNotification`), on time-zone and locale changes and
    /// whenever the scene becomes active (`refreshEnvironment()`).
    private(set) var today: LocalDate
    /// One resolver per live timetable.
    private(set) var resolvers: [Timetable.ID: ScheduleResolver] = [:]

    // MARK: Dependencies

    @ObservationIgnored let environment: AppEnvironment
    @ObservationIgnored private var clock: HybridLogicalClock
    @ObservationIgnored private var issues: [ValidationIssue] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The inputs the derived state was last built from (`nil` before the first build).
    @ObservationIgnored private var derivedInputs: DerivedStateInputs?
    /// Environment at the last derived-state build, and when the environment was last refreshed (Phase 10 P5).
    @ObservationIgnored private var derivedFingerprint: EnvironmentFingerprint?
    @ObservationIgnored private var lastEnvironmentRefreshAt: Date?
    /// Refreshes `today` at the next midnight of the calendar context's zone (`significantTimeChangeNotification`
    /// only fires at the device's midnight; a fixed timetable zone can be hours ahead or behind).
    @ObservationIgnored private var dayRolloverTask: Task<Void, Never>?
    /// The scene went to the background since it was last active (`true` until the first activation).
    @ObservationIgnored private var sceneWasInBackground = true
    /// Called after the store loaded, after every accepted change and after every environment refresh (time zone,
    /// locale, day change, scene activation). The reminder coordinator re-plans from it (debounced).
    @ObservationIgnored var onChange: (@MainActor (AppModelChange) -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        var generator = SystemRandomNumberGenerator()
        clock = environment.clockStore.load() ?? HybridLogicalClock(randomNodeUsing: &generator)
        let settings = AppSettings.untouchedDefaults
        let context = CalendarEnvironment.context(settings: settings, deviceTimeZone: environment.deviceTimeZone(),
                                                  locale: environment.locale())
        calendarContext = context
        let formatter = TimetableFormatter(settings: settings, context: context, locale: environment.locale())
        self.formatter = formatter
        renderer = LocalizedTextRenderer(formatter: formatter, lookup: environment.catalogLookup)
        today = context.localDate(of: environment.nowProvider.now())
    }

    // MARK: Read API

    /// "Now" (fixed in screenshot mode).
    var now: Date { environment.nowProvider.now() }
    /// `true` in screenshot mode: pause live countdowns at `now`.
    var isClockFixed: Bool { environment.nowProvider.isFixed }
    var entitlements: any EntitlementsProvider { environment.entitlements }
    var settings: AppSettings { database?.settings ?? .untouchedDefaults }
    var phase: ShellPhase { ShellPhase.derive(isLoading: isLoading, problem: problem, database: database) }
    /// Always the system appearance (D3, Phase 4U U5a): the in-app Light/Dark override was removed (HIG Dark Mode: avoid an
    /// app-specific appearance setting). `AppSettings.appearance` stays in the frozen schema, is never read here and is
    /// never written by the UI; values stored by older builds are ignored and kept untouched.
    var appearance: AppearancePreference { .system }
    /// The timetable the app shows (settings' active one, else the first).
    var activeTimetable: Timetable? { database.flatMap(ActiveTimetable.resolve) }
    /// Live timetables in display order.
    var timetables: [Timetable] { database.map(ActiveTimetable.ordered) ?? [] }
    /// The resolver of `timetableID` (nil for unknown/deleted timetables).
    func resolver(for timetableID: Timetable.ID) -> ScheduleResolver? { resolvers[timetableID] }

    // MARK: Lifecycle

    /// Loads the store once and starts observing time-zone / locale changes. Single-flight: concurrent callers (the
    /// window's `.task`, a notification action or a background refresh that launched the app) all await the same load.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        guard isLoading else { return }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        if let stranded = environment.strandedStore {
            strandedMigration = await StrandedStoreMigration.run(fallbackDirectory: stranded.fallback,
                                                                 groupDirectory: stranded.group, now: now)
        }
        let outcome = await environment.persistence.load()
        switch outcome {
        case let .loaded(database, banners, isReadOnly):
            self.database = database
            self.banners = banners
            self.isReadOnly = isReadOnly
        case .empty:
            database = nil
        case .failed(let problem):
            self.problem = problem
        }
        var generator = SystemRandomNumberGenerator()
        clock = ClockBootstrap.resume(stored: environment.clockStore.load(), database: database, now: now,
                                      generator: &generator)
        environment.clockStore.save(clock)
        issues = database?.validate() ?? []
        isLoading = false
        rebuildDerived()
        observeSystemChanges()
        onChange?(.loaded)
    }

    /// Writes pending changes now (scene going to the background).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await persist()
    }

    /// Writes pending changes now and reports whether the current snapshot is on disk. iCloud sync calls it before it
    /// records that the server holds something (Phase 6 S1): data must never be acknowledged before it is saved.
    func flushForSync() async -> Bool {
        await flush()
        switch lastSaveOutcome {
        case .saved?, .skippedStale?: return true
        default: return database == nil
        }
    }

    // MARK: Write API

    /// Applies a change: stamps it, validates (new errors block, new warnings are returned), updates the snapshot
    /// and schedules a debounced save. Never touches the database when it returns anything but `.applied`.
    /// `origin: .userSave` only for the task / exam saves listed at `ApplyOrigin.userSave`.
    @discardableResult
    func apply(_ mutation: DatabaseMutation, origin: ApplyOrigin = .other) -> ApplyResult {
        guard !isReadOnly, problem == nil, !isLoading else { return .readOnly }
        guard database != nil || mutation.replacesDatabase else { return .readOnly }
        if lastMutationLabel != mutation.label { lastMutationLabel = mutation.label }
        let base = database ?? DatabaseMutation.emptyBase
        var candidateClock = clock
        let candidate: TabulaDatabase
        do {
            candidate = try mutation.apply(to: base, clock: &candidateClock, now: now)
        } catch {
            return .failed(error)
        }
        if origin == .sync && candidate == database { return .applied(warnings: []) }   // re-applied data: no save, no re-plan
        let candidateIssues = candidate.validate()
        // A replacing mutation starts from scratch: only its own errors count.
        var verdict = MutationValidation.verdict(before: mutation.replacesDatabase ? [] : issues, after: candidateIssues)
        if origin == .sync, case .rejected = verdict { verdict = .accepted(newWarnings: []) }
        switch verdict {
        case .rejected(let errors):
            show(.changeRejected)
            return .rejected(errors: errors)
        case .accepted(let warnings):
            clock = candidateClock
            environment.clockStore.save(clock)
            database = candidate
            issues = candidateIssues
            if lastWarnings != warnings { lastWarnings = warnings }
            generation += 1
            rebuildDerived()
            scheduleSave()
            onChange?(.data(origin))
            return .applied(warnings: warnings)
        }
    }

    /// Hides the first banner (if dismissible).
    func dismissBanner() {
        guard let first = banners.first, first.isDismissible else { return }
        banners.removeFirst()
    }

    // MARK: Internals

    private func show(_ banner: StoreBanner) {
        banners.removeAll { $0 == banner }
        banners.insert(banner, at: banners.first.map { $0.isDismissible ? 0 : 1 } ?? 0)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = environment.saveDebounce
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() async {
        guard let database, !isReadOnly else { return }
        let outcome = await environment.persistence.save(database, generation: generation)
        lastSaveOutcome = outcome
        switch outcome {
        case .saved:
            banners.removeAll { $0 == .saveFailed }
        case .skippedStale:
            break
        case .readOnly:
            isReadOnly = true
            show(.readOnly(fileSchemaVersion: database.schemaVersion))
        case .failed:
            show(.saveFailed)
        }
    }

    /// Rebuilds (and assigns) only what changed: context, formatter + renderer, resolvers (`DerivedStateRebuild`).
    /// `forceEnvironment` rebuilds the context, formatter and renderer even when the inputs compare equal (a locale
    /// preference change `Locale ==` may not see; QA fix after Phase 10).
    private func rebuildDerived(forceEnvironment: Bool = false) {
        let settings = self.settings
        let deviceTimeZone = environment.deviceTimeZone()
        let locale = environment.locale()
        let inputs = DerivedStateInputs(settings: settings, database: database, deviceTimeZone: deviceTimeZone,
                                        locale: locale)
        let rebuild = DerivedStateRebuild.needed(from: derivedInputs, to: inputs, forceEnvironment: forceEnvironment)
        derivedInputs = inputs
        derivedFingerprint = EnvironmentFingerprint(settings: settings, deviceTimeZone: deviceTimeZone, locale: locale,
                                                    now: now)
        if rebuild.context { calendarContext = inputs.context }
        if rebuild.formatter {
            formatter = TimetableFormatter(settings: settings, context: inputs.context, locale: locale)
            renderer = LocalizedTextRenderer(formatter: formatter, lookup: environment.catalogLookup)
        }
        let newToday = inputs.context.localDate(of: now)
        if newToday != today { today = newToday }
        scheduleDayRollover(context: inputs.context)
        if rebuild.resolvers {
            if let database {
                let all = ScheduleResolver.all(database: database, context: inputs.context)
                resolvers = Dictionary(all.map { ($0.timetable.id, $0) }, uniquingKeysWith: { first, _ in first })
            } else if !resolvers.isEmpty {
                resolvers = [:]
            }
        }
    }

    /// Re-arms `dayRolloverTask` for the next midnight in `context`'s zone (not in screenshot mode: the clock is fixed).
    private func scheduleDayRollover(context: CalendarContext) {
        guard !environment.nowProvider.isFixed else { return }
        dayRolloverTask?.cancel()
        let current = now
        let delay = context.startOfNextDay(after: current).timeIntervalSince(current) + 1   // + 1 s: safely past midnight
        dayRolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshEnvironment()
        }
    }

    /// Rebuilds the calendar context and formatters (time zone, locale, first weekday or 12/24 h changed).
    /// Call on system time / zone / locale changes (always) and, through `sceneDidBecomeActive()`, when the scene
    /// becomes active. Clears Foundation's cached system time zone first so `TimeZone.current` reflects a zone change
    /// made while the app was suspended. `forceEnvironment`: see `rebuildDerived(forceEnvironment:)`; `true` on the
    /// locale-change notification and on a real return from the background.
    func refreshEnvironment(forceEnvironment: Bool = false) {
        NSTimeZone.resetSystemTimeZone()
        rebuildDerived(forceEnvironment: forceEnvironment)
        lastEnvironmentRefreshAt = now
        onChange?(.environment)
    }

    /// The scene became active (TabulaApp). After a background stay (and at the first activation) this always
    /// refreshes, as before; after a short `.inactive` blip (Notification Centre, Face ID, a call banner) only when the
    /// zone, locale, hour cycle, week start or local day changed, or the last refresh is 5+ minutes old
    /// (`ForegroundRefreshPolicy`, Phase 10 P5). A return from the background also rebuilds the context and
    /// formatters without the equality shortcut (Region / 24-Hour Time may have changed while suspended).
    func sceneDidBecomeActive() {
        NSTimeZone.resetSystemTimeZone()
        let returning = sceneWasInBackground
        sceneWasInBackground = false
        let current = EnvironmentFingerprint(settings: settings, deviceTimeZone: environment.deviceTimeZone(),
                                             locale: environment.locale(), now: now)
        if ForegroundRefreshPolicy.shouldRefresh(returningFromBackground: returning, last: derivedFingerprint,
                                                 lastRefreshAt: lastEnvironmentRefreshAt, current: current, now: now) {
            refreshEnvironment(forceEnvironment: returning)
        }
    }

    /// The scene entered the background (TabulaApp): the next activation is a real foreground and always refreshes.
    func sceneDidEnterBackground() {
        sceneWasInBackground = true
    }

    private func observeSystemChanges() {
        guard observers.isEmpty else { return }
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification,
                     UIApplication.significantTimeChangeNotification] {
            // A locale change always rebuilds the formatter: `Locale ==` may miss a preference-only change.
            let forceEnvironment = name == NSLocale.currentLocaleDidChangeNotification
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshEnvironment(forceEnvironment: forceEnvironment) }
            })
        }
    }
}
