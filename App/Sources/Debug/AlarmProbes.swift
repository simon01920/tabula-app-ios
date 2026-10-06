// UNCOMPILED (written on Windows/WSL without the iOS SDK). Phase 0 debug probe only; delete after the Phase 0 gate.
// Every API below was checked on 2026-10-04 against developer.apple.com JSON docs; citations in docs/spikes/ALARMKIT.md.
//
// APIs used
//   AlarmKit (iOS 26.0 unless noted): AlarmManager.shared, .authorizationState, .authorizationUpdates,
//     .requestAuthorization() async throws, .alarms { get throws }, .alarmUpdates, .schedule(id:configuration:) async throws,
//     .cancel(id:) throws, AlarmManager.AlarmConfiguration<M>.alarm(schedule:attributes:) / .timer(duration:attributes:) /
//     init(countdownDuration:schedule:attributes:), AlarmManager.AlarmError.maximumLimitReached,
//     Alarm (.id, .state, .schedule, .countdownDuration), Alarm.Schedule.fixed(Date) / .relative(_:),
//     Alarm.Schedule.Relative(time:repeats:), Alarm.Schedule.Relative.Time(hour:minute:), Recurrence.never,
//     Alarm.CountdownDuration(preAlert:postAlert:), AlarmAttributes(presentation:metadata:tintColor:),
//     AlarmPresentation(alert:countdown:paused:), AlarmPresentation.Countdown(title:pauseButton:),
//     AlarmPresentation.Paused(title:resumeButton:), AlarmButton(text:textColor:systemImageName:),
//     AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)             -- iOS 26.1+
//     AlarmPresentation.Alert(title:stopButton:secondaryButton:secondaryButtonBehavior:)  -- iOS 26.0, deprecated 26.1
//   UserNotifications: UNUserNotificationCenter.current(), requestAuthorization(options:) async throws -> Bool,
//     notificationSettings() async, pendingNotificationRequests() async, add(_:) async throws,
//     removePendingNotificationRequests(withIdentifiers:), UNMutableNotificationContent (title, body, sound,
//     interruptionLevel), UNNotificationSound.default, UNTimeIntervalNotificationTrigger(timeInterval:repeats:),
//     UNNotificationRequest(identifier:content:trigger:), UNNotificationSettings (.authorizationStatus,
//     .alertSetting, .soundSetting, .timeSensitiveSetting), UNNotificationInterruptionLevel (.active, .timeSensitive)
//   SwiftUI: Section(content:header:footer:), Button, Stepper, Text(verbatim:), ProgressView, @StateObject,
//     onChange(of:initial:_:) (iOS 17), scenePhase. TimetableUI: ProbeRow, ProbeStatus, AlarmProbeMetadata.
//
// Concurrency (Swift 6): AlarmManager, UNUserNotificationCenter and UNNotificationSettings are NOT documented as
// Sendable. All calls into them therefore happen inside `nonisolated static` helpers that return only Sendable values
// (String, UUID, Int, small structs). The view model is @MainActor. Conservative choice: ObservableObject/@Published
// (property wrappers) instead of the @Observable macro, because macros under xtool are not proven yet (CLAUDE.md rule 5).
//
// Strings: developer-facing debug screen, so strings are verbatim and deliberately NOT in the String Catalog
// (same convention as TimetableUI.ProbeRow). Never ship this screen in release UI.
//
// Build requirements (owned by env-ci): App target links TimetableUI; App Info.plist has a non-empty
// NSAlarmKitUsageDescription and NSSupportsLiveActivities = YES; the TabulaWidgets extension registers
// AlarmLiveActivity() (needed for the countdown and snooze probes); Time Sensitive needs the entitlement
// com.apple.developer.usernotifications.time-sensitive = true (paid Developer Program only).

import AlarmKit
import Combine
import SwiftUI
import TimetableUI
import UserNotifications

// MARK: - View

/// AlarmKit + notification smoke-test probe. The body is a group of `Section`s: place it inside a `List` or `Form`.
struct AlarmProbesSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AlarmProbeModel()

    var body: some View {
        Group {
            instructionsSection
            alarmKitSection
            timeZoneSection
            scheduledAlarmsSection
            notificationsSection
            limitProbesSection
            resultSection
        }
        // Group forwards these modifiers to every child Section. startIfNeeded() is idempotent and
        // refreshSoon() is debounced, so the repeated calls are harmless.
        .onAppear { model.startIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.refreshSoon()
            }
        }
    }

    // MARK: Sections

    private var instructionsSection: some View {
        Section {
            Text(verbatim: """
            1. Turn Silent Mode ON. (iPhone 16 Pro Max has no switch: use the Action button or Control Center.)
            2. Tap ONE probe below.
            3. Lock the phone and put it down. Wear the Apple Watch if you are testing Watch behaviour.
            4. Wait. Note sound, vibration, full-screen alert, Lock Screen / Dynamic Island, Watch.
            5. Record expected vs observed in docs/spikes/ALARMKIT.md (device test matrix).
            """)
            .font(.footnote)
        } header: {
            Text(verbatim: "Lock the phone, turn Silent on, wait")
        }
    }

    private var alarmKitSection: some View {
        Section {
            ProbeRow("AlarmKit authorization",
                     value: model.alarmAuthorization,
                     status: Self.status(for: model.alarmAuthorization))
            Button { model.requestAlarmAuthorization() } label: {
                Text(verbatim: "Request AlarmKit authorization")
            }
            Button { model.scheduleFixedAlarm(seconds: 60, snooze: false) } label: {
                Text(verbatim: "Schedule alarm in 60 s")
            }
            Button { model.scheduleFixedAlarm(seconds: 60, snooze: true) } label: {
                Text(verbatim: "Schedule alarm in 60 s with 1-min Snooze")
            }
            Button { model.scheduleCountdown(seconds: 120) } label: {
                Text(verbatim: "Schedule 2-min countdown")
            }
        } header: {
            Text(verbatim: "AlarmKit (loud alarm tier)")
        } footer: {
            Text(verbatim: """
            The plain 60 s alarm is alert-only and does not need the widget extension. Snooze and countdown use a \
            countdown presentation, which needs the TabulaWidgets Live Activity (AlarmLiveActivity). Without it, \
            Apple says the system may dismiss the alarm and fail to alert. If authorization is notDetermined, \
            the first schedule call shows the system prompt.
            """)
        }
        .disabled(model.isBusy)
    }

    private var timeZoneSection: some View {
        Section {
            Stepper(value: $model.delayMinutes, in: 3...30) {
                Text(verbatim: "Delay: \(model.delayMinutes) min")
            }
            Button {
                model.scheduleFixedAlarm(seconds: TimeInterval(model.delayMinutes * 60), snooze: false)
            } label: {
                Text(verbatim: "Fixed alarm in \(model.delayMinutes) min (absolute instant)")
            }
            Button { model.scheduleRelativeAlarm(minutes: model.delayMinutes) } label: {
                Text(verbatim: "Relative alarm at now + \(model.delayMinutes) min (wall clock)")
            }
        } header: {
            Text(verbatim: "Time zone / DST probes")
        } footer: {
            Text(verbatim: """
            Schedule both, then change Settings > General > Date & Time > Time Zone. Expected from Apple's docs: \
            the fixed alarm rings at the same absolute instant; the relative alarm rings at the same wall-clock time \
            in the new time zone. Keep the delay at 3 min or more (forum reports of very near relative alarms \
            moving to the next day).
            """)
        }
        .disabled(model.isBusy)
    }

    private var scheduledAlarmsSection: some View {
        Section {
            if model.alarmRows.isEmpty {
                Text(verbatim: "No alarms scheduled by this app.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.alarmRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "\(row.state) · \(AlarmProbeActions.shortID(row.id))")
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: row.detail)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(role: .destructive) { model.cancelAlarm(row.id) } label: {
                            Text(verbatim: "Cancel")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: "Cancel alarm \(AlarmProbeActions.shortID(row.id))"))
                    }
                }
                Button(role: .destructive) { model.cancelAllAlarms() } label: {
                    Text(verbatim: "Cancel all alarms from this app")
                }
            }
            Button { model.refreshNow() } label: {
                Text(verbatim: "Refresh")
            }
        } header: {
            Text(verbatim: "Scheduled alarms (\(model.alarmRows.count))")
        } footer: {
            Text(verbatim: "Apple: an alarm missing from alarmUpdates is no longer scheduled; one-shot alarms disappear once they fire and stop.")
        }
        .disabled(model.isBusy)
    }

    private var notificationsSection: some View {
        Section {
            ProbeRow("Notification authorization",
                     value: model.notifications.authorization,
                     status: Self.status(for: model.notifications.authorization))
            ProbeRow("Time Sensitive setting",
                     value: model.notifications.timeSensitive,
                     status: Self.status(for: model.notifications.timeSensitive))
            ProbeRow("Alert / sound settings",
                     value: "alert \(model.notifications.alert), sound \(model.notifications.sound)")
            ProbeRow("Pending notifications",
                     value: "\(model.notifications.pendingTotal) total, \(model.notifications.pendingFromProbe) from this probe (documented cap: 64)")
            Button { model.requestNotificationAuthorization() } label: {
                Text(verbatim: "Request notification permission")
            }
            Button { model.scheduleNotification(timeSensitive: false) } label: {
                Text(verbatim: "Standard notification in 10 s")
            }
            Button { model.scheduleNotification(timeSensitive: true) } label: {
                Text(verbatim: "Time Sensitive notification in 10 s")
            }
            Button { model.refreshNow() } label: {
                Text(verbatim: "Refresh")
            }
        } header: {
            Text(verbatim: "Notifications (Standard / Time Sensitive tiers)")
        } footer: {
            Text(verbatim: """
            Expected (Apple HIG): with Silent on, NEITHER notification plays a sound. Time Sensitive only breaks \
            through Focus and Scheduled Summary. A Time Sensitive setting other than "enabled" (for example \
            notSupported) probably means the build lacks the Time Sensitive entitlement; record what you see.
            """)
        }
        .disabled(model.isBusy)
    }

    private var limitProbesSection: some View {
        Section {
            Button { model.probeAlarmLimit() } label: {
                Text(verbatim: "Probe AlarmKit limit (schedule up to \(AlarmProbeModel.alarmLimitAttempts), then cancel)")
            }
            Button { model.probePendingCap() } label: {
                Text(verbatim: "Probe pending-notification cap (add \(AlarmProbeModel.pendingCapAttempts), count, remove)")
            }
        } header: {
            Text(verbatim: "Limit probes (run these LAST)")
        } footer: {
            Text(verbatim: """
            The alarm probe schedules alarms about 400 days ahead until AlarmKit throws maximumLimitReached, \
            records the count, then cancels everything it scheduled. Apple says the limit is not fixed and depends \
            on device state, so run it twice. Forum reports link heavy schedule/cancel churn to misfires, so \
            REBOOT the phone afterwards and check "Scheduled alarms" is empty.
            """)
        }
        .disabled(model.isBusy)
    }

    private var resultSection: some View {
        Section {
            if model.isBusy {
                ProgressView()
            }
            Text(verbatim: model.lastResult)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        } header: {
            Text(verbatim: "Last result")
        }
    }

    // MARK: Helpers

    /// Maps a described state to an icon/word status, so status is never conveyed by colour alone.
    private static func status(for described: String) -> ProbeStatus {
        switch described {
        case "authorized", "enabled": .pass
        case "denied", "disabled": .fail
        case "notSupported": .fail
        default: .info
        }
    }
}

// MARK: - View model

@MainActor
final class AlarmProbeModel: ObservableObject {
    static let alarmLimitAttempts = 200
    static let pendingCapAttempts = 70

    @Published private(set) var alarmAuthorization = "not read yet"
    @Published private(set) var alarmRows: [AlarmProbeRow] = []
    @Published private(set) var notifications = NotificationProbeSnapshot.placeholder
    @Published private(set) var lastResult = "No probe run yet."
    @Published private(set) var isBusy = false
    @Published var delayMinutes = 5

    private var isObserving = false
    private var lastRefresh = Date.distantPast

    /// Starts the AlarmKit observation streams once and does a first refresh.
    func startIfNeeded() {
        guard !isObserving else { return }
        isObserving = true

        // Apple: alarmUpdates keeps the app current even if alarm state changed while the app was not running.
        Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                self.alarmRows = AlarmProbeActions.rows(for: alarms)
            }
        }
        Task { [weak self] in
            for await state in AlarmManager.shared.authorizationUpdates {
                guard let self else { return }
                self.alarmAuthorization = AlarmProbeActions.describe(state)
            }
        }
        refreshNow()
    }

    func refreshNow() {
        Task { await refresh(force: true) }
    }

    func refreshSoon() {
        Task { await refresh(force: false) }
    }

    private func refresh(force: Bool) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastRefresh) > 1 else { return }
        lastRefresh = now
        alarmAuthorization = AlarmProbeActions.describe(AlarmManager.shared.authorizationState)
        alarmRows = AlarmProbeActions.currentAlarmRows()
        notifications = await AlarmProbeActions.fetchNotificationSnapshot()
    }

    // MARK: Actions

    func requestAlarmAuthorization() {
        run { await AlarmProbeActions.requestAlarmAuthorization() }
    }

    func scheduleFixedAlarm(seconds: TimeInterval, snooze: Bool) {
        run { await AlarmProbeActions.scheduleFixedAlarm(after: seconds, snoozeSeconds: snooze ? 60 : nil) }
    }

    func scheduleRelativeAlarm(minutes: Int) {
        run { await AlarmProbeActions.scheduleRelativeAlarm(afterMinutes: minutes) }
    }

    func scheduleCountdown(seconds: TimeInterval) {
        run { await AlarmProbeActions.scheduleCountdown(seconds: seconds) }
    }

    func cancelAlarm(_ id: UUID) {
        run { AlarmProbeActions.cancelAlarm(id) }
    }

    func cancelAllAlarms() {
        run { AlarmProbeActions.cancelAllAlarms() }
    }

    func requestNotificationAuthorization() {
        run { await AlarmProbeActions.requestNotificationAuthorization() }
    }

    func scheduleNotification(timeSensitive: Bool) {
        run { await AlarmProbeActions.scheduleTestNotification(timeSensitive: timeSensitive, delay: 10) }
    }

    func probeAlarmLimit() {
        run { await AlarmProbeActions.probeAlarmLimit(maxAttempts: AlarmProbeModel.alarmLimitAttempts) }
    }

    func probePendingCap() {
        run { await AlarmProbeActions.probePendingNotificationCap(count: AlarmProbeModel.pendingCapAttempts) }
    }

    /// Runs one probe at a time, publishes its result line, then refreshes the status rows.
    private func run(_ work: @escaping @MainActor () async -> String) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            let message = await work()
            self.lastResult = "[\(AlarmProbeActions.clock(Date()))] \(message)"
            self.isBusy = false
            await self.refresh(force: true)
        }
    }
}

// MARK: - Sendable value types

nonisolated struct AlarmProbeRow: Identifiable, Sendable, Equatable {
    let id: UUID
    let state: String
    let detail: String
    let sortDate: Date
}

nonisolated struct NotificationProbeSnapshot: Sendable, Equatable {
    var authorization: String
    var alert: String
    var sound: String
    var timeSensitive: String
    var pendingTotal: Int
    var pendingFromProbe: Int

    static let placeholder = NotificationProbeSnapshot(
        authorization: "not read yet", alert: "?", sound: "?", timeSensitive: "not read yet",
        pendingTotal: 0, pendingFromProbe: 0)
}

// MARK: - Framework calls (nonisolated, Sendable in / Sendable out)

nonisolated enum AlarmProbeActions {
    static let notificationPrefix = "tabula.probe.notification."
    static let capProbePrefix = "tabula.probe.cap."

    // MARK: AlarmKit authorization

    static func requestAlarmAuthorization() async -> String {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return "AlarmKit requestAuthorization() -> \(describe(state))"
        } catch {
            return "AlarmKit requestAuthorization() threw: \(String(describing: error))"
        }
    }

    // MARK: AlarmKit scheduling

    /// One-shot alarm at an absolute instant. With `snoozeSeconds`, the alert gets a Snooze button
    /// (secondary button with `.countdown` behaviour); that path uses a countdown presentation and so
    /// also depends on the TabulaWidgets Live Activity.
    static func scheduleFixedAlarm(after seconds: TimeInterval, snoozeSeconds: TimeInterval?) async -> String {
        let id = UUID()
        let fireDate = Date().addingTimeInterval(seconds)
        let kind = snoozeSeconds == nil ? "fixed" : "fixed+snooze"
        do {
            if let snoozeSeconds {
                let presentation = AlarmPresentation(
                    alert: makeAlert(
                        title: "Tabula test alarm (snooze)",
                        secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
                        secondaryButtonBehavior: .countdown),
                    countdown: AlarmPresentation.Countdown(title: "Tabula test alarm snoozed", pauseButton: nil),
                    paused: nil)
                let attributes = AlarmAttributes<AlarmProbeMetadata>(
                    presentation: presentation,
                    metadata: AlarmProbeMetadata(probeKind: kind),
                    tintColor: Color.orange)
                let configuration = AlarmManager.AlarmConfiguration<AlarmProbeMetadata>(
                    countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeSeconds),
                    schedule: .fixed(fireDate),
                    attributes: attributes)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            } else {
                let attributes = AlarmAttributes<AlarmProbeMetadata>(
                    presentation: AlarmPresentation(alert: makeAlert(title: "Tabula test alarm")),
                    metadata: AlarmProbeMetadata(probeKind: kind),
                    tintColor: Color.orange)
                let configuration = AlarmManager.AlarmConfiguration<AlarmProbeMetadata>.alarm(
                    schedule: .fixed(fireDate),
                    attributes: attributes)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            }
            return "Scheduled \(kind) alarm \(shortID(id)) for \(clock(fireDate)) (in \(Int(seconds)) s)."
        } catch {
            return "schedule(\(kind)) threw: \(String(describing: error))"
        }
    }

    /// One-shot alarm at a wall-clock hour:minute in the device's current time zone (`Alarm.Schedule.relative`).
    static func scheduleRelativeAlarm(afterMinutes minutes: Int) async -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let parts = calendar.dateComponents([.hour, .minute], from: target)
        guard let hour = parts.hour, let minute = parts.minute else {
            return "Could not compute the wall-clock time for the relative alarm."
        }
        let id = UUID()
        let relative = Alarm.Schedule.Relative(
            time: Alarm.Schedule.Relative.Time(hour: hour, minute: minute),
            repeats: .never)
        let attributes = AlarmAttributes<AlarmProbeMetadata>(
            presentation: AlarmPresentation(alert: makeAlert(title: "Tabula test alarm (relative)")),
            metadata: AlarmProbeMetadata(probeKind: "relative"),
            tintColor: Color.orange)
        let configuration = AlarmManager.AlarmConfiguration<AlarmProbeMetadata>.alarm(
            schedule: .relative(relative),
            attributes: attributes)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return "Scheduled relative alarm \(shortID(id)) for \(pad2(hour)):\(pad2(minute)) wall clock (\(calendar.timeZone.identifier))."
        } catch {
            return "schedule(relative) threw: \(String(describing: error))"
        }
    }

    /// Timer-style countdown: starts immediately, Live Activity countdown, alerts at 0.
    static func scheduleCountdown(seconds: TimeInterval) async -> String {
        let id = UUID()
        let presentation = AlarmPresentation(
            alert: makeAlert(title: "Tabula test countdown finished"),
            countdown: AlarmPresentation.Countdown(
                title: "Tabula test countdown",
                pauseButton: AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.fill")),
            paused: AlarmPresentation.Paused(
                title: "Tabula test countdown paused",
                resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")))
        let attributes = AlarmAttributes<AlarmProbeMetadata>(
            presentation: presentation,
            metadata: AlarmProbeMetadata(probeKind: "countdown"),
            tintColor: Color.blue)
        let configuration = AlarmManager.AlarmConfiguration<AlarmProbeMetadata>.timer(
            duration: seconds,
            attributes: attributes)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return "Started \(Int(seconds)) s countdown \(shortID(id)); should alert at \(clock(Date().addingTimeInterval(seconds)))."
        } catch {
            return "schedule(countdown) threw: \(String(describing: error))"
        }
    }

    /// iOS 26.1 removed the app-provided stop button (the system now provides it). iOS 26.0 still needs one.
    static func makeAlert(
        title: LocalizedStringResource,
        secondaryButton: AlarmButton? = nil,
        secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = nil
    ) -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButtonBehavior)
        } else {
            return AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButtonBehavior)
        }
    }

    // MARK: AlarmKit state

    static func cancelAlarm(_ id: UUID) -> String {
        do {
            try AlarmManager.shared.cancel(id: id)
            return "Cancelled alarm \(shortID(id))."
        } catch {
            return "cancel(\(shortID(id))) threw: \(String(describing: error))"
        }
    }

    static func cancelAllAlarms() -> String {
        let alarms: [Alarm]
        do {
            alarms = try AlarmManager.shared.alarms
        } catch {
            return "AlarmManager.alarms threw: \(String(describing: error))"
        }
        var failures = 0
        for alarm in alarms {
            do {
                try AlarmManager.shared.cancel(id: alarm.id)
            } catch {
                failures += 1
            }
        }
        return "Cancelled \(alarms.count - failures) of \(alarms.count) alarms (\(failures) failed)."
    }

    static func currentAlarmRows() -> [AlarmProbeRow] {
        do {
            return rows(for: try AlarmManager.shared.alarms)
        } catch {
            return [AlarmProbeRow(id: UUID(), state: "error",
                                  detail: "AlarmManager.alarms threw: \(String(describing: error))",
                                  sortDate: .distantPast)]
        }
    }

    static func rows(for alarms: [Alarm]) -> [AlarmProbeRow] {
        alarms.map(row(for:)).sorted { $0.sortDate < $1.sortDate }
    }

    static func row(for alarm: Alarm) -> AlarmProbeRow {
        var parts: [String] = []
        var sortDate = Date.distantFuture
        if let schedule = alarm.schedule {
            switch schedule {
            case .fixed(let date):
                parts.append("fixed \(date.formatted(date: .abbreviated, time: .standard))")
                sortDate = date
            case .relative(let relative):
                parts.append("relative \(pad2(relative.time.hour)):\(pad2(relative.time.minute))")
            @unknown default:
                parts.append("schedule \(String(describing: schedule))")
            }
        } else {
            parts.append("no schedule (timer)")
        }
        if let countdown = alarm.countdownDuration {
            let pre = countdown.preAlert.map { "\(Int($0)) s" } ?? "none"
            let post = countdown.postAlert.map { "\(Int($0)) s" } ?? "none"
            parts.append("countdown pre \(pre) / post \(post)")
        }
        return AlarmProbeRow(
            id: alarm.id,
            state: String(describing: alarm.state),
            detail: parts.joined(separator: " · "),
            sortDate: sortDate)
    }

    static func describe(_ state: AlarmManager.AuthorizationState) -> String {
        switch state {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown (\(String(describing: state)))"
        }
    }

    // MARK: AlarmKit limit probe

    /// Schedules far-future one-shot alarms until AlarmKit refuses, then cancels everything it scheduled.
    static func probeAlarmLimit(maxAttempts: Int) async -> String {
        let preExisting = (try? AlarmManager.shared.alarms.count) ?? -1
        let base = Date().addingTimeInterval(400 * 24 * 60 * 60)
        let attributes = AlarmAttributes<AlarmProbeMetadata>(
            presentation: AlarmPresentation(alert: makeAlert(title: "Tabula limit probe (should never ring)")),
            metadata: AlarmProbeMetadata(probeKind: "limit-probe"),
            tintColor: Color.gray)
        var scheduled: [UUID] = []
        var stopReason = "hit the probe's own cap of \(maxAttempts) with no error"
        for index in 0..<maxAttempts {
            let id = UUID()
            let configuration = AlarmManager.AlarmConfiguration<AlarmProbeMetadata>.alarm(
                schedule: .fixed(base.addingTimeInterval(TimeInterval(index * 60))),
                attributes: attributes)
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                scheduled.append(id)
            } catch AlarmManager.AlarmError.maximumLimitReached {
                stopReason = "maximumLimitReached"
                break
            } catch {
                stopReason = "other error: \(String(describing: error))"
                break
            }
        }
        var cancelFailures = 0
        for id in scheduled {
            do {
                try AlarmManager.shared.cancel(id: id)
            } catch {
                cancelFailures += 1
            }
        }
        let remaining = (try? AlarmManager.shared.alarms.count) ?? -1
        return """
        AlarmKit limit probe: \(preExisting) alarms already scheduled; probe added \(scheduled.count) more \
        (total \(preExisting + scheduled.count)); stopped because: \(stopReason). Cleanup: cancelled \
        \(scheduled.count - cancelFailures), failed \(cancelFailures); alarms now scheduled: \(remaining).
        """
    }

    // MARK: Notifications

    static func requestNotificationAuthorization() async -> String {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return "Notification requestAuthorization -> \(granted ? "granted" : "not granted")"
        } catch {
            return "Notification requestAuthorization threw: \(String(describing: error))"
        }
    }

    static func scheduleTestNotification(timeSensitive: Bool, delay: TimeInterval) async -> String {
        let tier = timeSensitive ? "Time Sensitive" : "Standard"
        let content = UNMutableNotificationContent()
        content.title = "Tabula test: \(tier)"
        content.body = "Scheduled \(Int(delay)) s earlier. Did it make a sound? Vibrate? Show on the Watch?"
        content.sound = UNNotificationSound.default
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationPrefix + UUID().uuidString,
            content: content,
            trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return "Scheduled \(tier) notification for \(clock(Date().addingTimeInterval(delay))). Lock the phone now."
        } catch {
            return "add(\(tier) notification) threw: \(String(describing: error))"
        }
    }

    static func fetchNotificationSnapshot() async -> NotificationProbeSnapshot {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let fromProbe = pending.filter {
            $0.identifier.hasPrefix(notificationPrefix) || $0.identifier.hasPrefix(capProbePrefix)
        }.count
        return NotificationProbeSnapshot(
            authorization: describe(settings.authorizationStatus),
            alert: describe(settings.alertSetting),
            sound: describe(settings.soundSetting),
            timeSensitive: describe(settings.timeSensitiveSetting),
            pendingTotal: pending.count,
            pendingFromProbe: fromProbe)
    }

    /// Adds `count` far-future notifications, reads back how many iOS kept, then removes them.
    /// Apple's (legacy) docs say the system keeps the soonest-firing 64 and discards the rest.
    static func probePendingNotificationCap(count: Int) async -> String {
        let center = UNUserNotificationCenter.current()
        let before = await center.pendingNotificationRequests().count
        var identifiers: [String] = []
        var addErrors: [String] = []
        for index in 0..<count {
            let content = UNMutableNotificationContent()
            content.title = "Tabula cap probe \(index)"
            content.body = "Should never be delivered: scheduled about 30 days ahead and removed right away."
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(30 * 24 * 60 * 60 + index * 60),
                repeats: false)
            let identifier = "\(capProbePrefix)\(index).\(UUID().uuidString)"
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                identifiers.append(identifier)
            } catch {
                addErrors.append(String(describing: error))
            }
        }
        let pendingAfterAdd = await center.pendingNotificationRequests()
        let keptFromProbe = pendingAfterAdd.filter { $0.identifier.hasPrefix(capProbePrefix) }.count
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let afterCleanup = await center.pendingNotificationRequests().count
        let errorSummary = addErrors.isEmpty ? "none" : "\(addErrors.count) (first: \(addErrors[0]))"
        return """
        Pending cap probe: \(before) pending before; add() succeeded \(identifiers.count)/\(count) times; \
        add errors: \(errorSummary); pending after adding: \(pendingAfterAdd.count) total, \(keptFromProbe) \
        from probe; pending after cleanup: \(afterCleanup) (removal may lag a moment; tap Refresh).
        """
    }

    static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }

    static func describe(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .notSupported: return "notSupported"
        @unknown default: return "unknown (\(setting.rawValue))"
        }
    }

    // MARK: Formatting

    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    static func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
