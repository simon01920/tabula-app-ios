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

/// What `AppModel.onChange` reports.
enum AppModelChange: Equatable, Sendable {
    /// The store finished loading.
    case loaded
    /// An accepted `apply(_:)`.
    case data
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

    // MARK: Derived state (rebuilt on every change of data, settings, time zone or locale)

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
    var appearance: AppearancePreference { AppearancePreference(settings.appearance) }
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

    // MARK: Write API

    /// Applies a change: stamps it, validates (new errors block, new warnings are returned), updates the snapshot
    /// and schedules a debounced save. Never touches the database when it returns anything but `.applied`.
    @discardableResult
    func apply(_ mutation: DatabaseMutation) -> ApplyResult {
        guard !isReadOnly, problem == nil, !isLoading else { return .readOnly }
        guard database != nil || mutation.replacesDatabase else { return .readOnly }
        lastMutationLabel = mutation.label
        let base = database ?? DatabaseMutation.emptyBase
        var candidateClock = clock
        let candidate: TabulaDatabase
        do {
            candidate = try mutation.apply(to: base, clock: &candidateClock, now: now)
        } catch {
            return .failed(error)
        }
        let candidateIssues = candidate.validate()
        // A replacing mutation starts from scratch: only its own errors count.
        switch MutationValidation.verdict(before: mutation.replacesDatabase ? [] : issues, after: candidateIssues) {
        case .rejected(let errors):
            show(.changeRejected)
            return .rejected(errors: errors)
        case .accepted(let warnings):
            clock = candidateClock
            environment.clockStore.save(clock)
            database = candidate
            issues = candidateIssues
            lastWarnings = warnings
            generation += 1
            rebuildDerived()
            scheduleSave()
            onChange?(.data)
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

    private func rebuildDerived() {
        let locale = environment.locale()
        calendarContext = CalendarEnvironment.context(settings: settings, deviceTimeZone: environment.deviceTimeZone(),
                                                      locale: locale)
        formatter = TimetableFormatter(settings: settings, context: calendarContext, locale: locale)
        renderer = LocalizedTextRenderer(formatter: formatter, lookup: environment.catalogLookup)
        let newToday = calendarContext.localDate(of: now)
        if newToday != today { today = newToday }
        if let database {
            let all = ScheduleResolver.all(database: database, context: calendarContext)
            resolvers = Dictionary(all.map { ($0.timetable.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            resolvers = [:]
        }
    }

    /// Rebuilds the calendar context and formatters (time zone, locale, first weekday or 12/24 h changed).
    /// Call when the scene becomes active, and on system time / zone / locale changes. Clears Foundation's cached
    /// system time zone first so `TimeZone.current` reflects a zone change made while the app was suspended.
    func refreshEnvironment() {
        NSTimeZone.resetSystemTimeZone()
        rebuildDerived()
        onChange?(.environment)
    }

    private func observeSystemChanges() {
        guard observers.isEmpty else { return }
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification,
                     UIApplication.significantTimeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshEnvironment() }
            })
        }
    }
}
