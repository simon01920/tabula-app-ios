# Spike: AlarmKit + Time Sensitive notifications (Phase 0)

- **Date:** 2026-10-04. **Owner:** notifications-engineer. **Status:** docs research done. Probe written but **UNCOMPILED**. Device test pending.
- **Scope:** check the AlarmKit and Time Sensitive facts in Apple's docs, and write an on-device smoke-test probe. Not in scope: the planner, the rule model and feature code (those are Phase 1 and Phase 3).
- **Method:** the developer.apple.com DocC JSON endpoints (`/tutorials/data/documentation/<path>.json`) were read with a small renderer. Every symbol below was opened on its own page, and its declaration and availability were copied from there. A crawl of all 127 AlarmKit symbol pages checked availability. Only 5 symbols are not plain `iOS 26.0`; they are listed in §2.9. Community sources (Apple Developer Forums, which include DTS) are labelled as such.

## TL;DR

1. **No entitlement and no capability are needed for AlarmKit.** You only need a non-empty `NSAlarmKitUsageDescription` and the user's per-app authorization. `com.apple.developer.alarmkit` **does not exist**. An Apple engineer on the forums warns that LLMs invent it. Do not add it.
2. **A widget extension (a Live Activity on `AlarmAttributes<Metadata>`) is required for any countdown presentation.** That covers timers, pre-alert countdowns and **snooze** (snooze goes back to the countdown state). Without it, "the system may unexpectedly dismiss alarms and fail to alert." Plain alert-only alarms do not need it.
3. **There is no documented alarm-count limit.** The DTS FAQ says the limit is dynamic ("depending on device state, available resources"), and scheduling throws `AlarmManager.AlarmError.maximumLimitReached` when it is hit. The probe measures it on the device.
4. **Alarms break through Silent mode and all Focus modes** (docs and DTS FAQ). They persist through reboot, force-quit and app crash (DTS FAQ). They are forwarded to a paired Apple Watch (docs). **AlarmKit has no watchOS API**: it is available on iOS, iPadOS and Mac Catalyst 26.0 only.
5. **Alarms from hidden apps, or apps that need Face ID to open, silently fail** (DTS FAQ). Pressing **any physical button** stops all alerting alarms (DTS FAQ).
6. **Time Sensitive does NOT break through the Ring/Silent switch.** It only breaks through Focus and Scheduled Summary (HIG table), as the spec says. The HIG also says Time Sensitive is only for events "happening now or will happen within an hour", which conflicts with the spec's multi-day offsets (§8).
7. **The Time Sensitive capability is available to paid programs only** (ADP and ADEP, not free "Apple Developer" accounts). The entitlement key `com.apple.developer.usernotifications.time-sensitive` is **not in Apple's current entitlement reference**. It comes from community sources and Xcode's capability name, so check it against a CI-signed build.
8. **The 64 pending local-notification cap appears in Apple's docs only on the deprecated `UILocalNotification` page.** The page says the system keeps the 64 notifications that fire soonest and **silently discards the rest**, with a repeating notification counting as one. The `UNUserNotificationCenter` docs don't restate the cap. The probe measures it.
9. **API deltas since iOS 26.0:** `AlarmPresentation.Alert(title:stopButton:…)` is **deprecated in 26.1**, because the system now provides the stop button. The replacement, `init(title:secondaryButton:secondaryButtonBehavior:)`, is **iOS 26.1+**. iOS 27 adds `appEntityIdentifier:` overloads of all three configuration factories.

---

## 1. Verified-facts table

| # | Fact | Source | Confidence |
|---|------|--------|-----------|
| F1 | AlarmKit platforms: iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0. **No watchOS, no native macOS.** | [AlarmKit](https://developer.apple.com/documentation/alarmkit) | Apple docs |
| F2 | An alarm "overrides both a device's focus and silent mode, if necessary". | [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit) | Apple docs |
| F3 | No Focus mode blocks AlarmKit: "AlarmKit alarms can break through all focus modes." | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F4 | Alarms persist through reboot, force-quit and app crash once they are scheduled. | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F5 | There is no fixed alarm limit. The device may impose a limit based on state and resources, and scheduling then throws `maximumLimitReached`. | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158), [AlarmError.maximumLimitReached](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmerror/maximumlimitreached) | Apple DTS + docs |
| F6 | Alarms from hidden apps, or apps that need a passcode or Face ID to open, "will silently fail". | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F7 | Any physical button that triggers AlarmKit stops the alerting alarm, and pressing one dismisses **all** alerting alarms. | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F8 | When several apps' alarms fire at the same time, which one wins is non-deterministic. | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F9 | Dismissing an alarm calls the configured `stopIntent`. | [AlarmKit FAQ (DTS)](https://developer.apple.com/forums/thread/797158) | Apple DTS, forum |
| F10 | "The system forwards the alert presentation to a paired watch (if any)". | [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit). WWDC25 230 adds "right on Apple Watch, if it's paired to iPhone when the alarm fires". | Apple docs + WWDC |
| F11 | `NSAlarmKitUsageDescription` is required. If it is missing or empty, the app "can't schedule alarms". | [NSAlarmKitUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription) | Apple docs |
| F12 | Authorization is per app and opt-in. If it hasn't been requested yet, the first `schedule` asks for it automatically. Users can change it in Settings. If it is denied, "all attempts to schedule alarms fail". | [requestAuthorization()](https://developer.apple.com/documentation/alarmkit/alarmmanager/requestauthorization()), [sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [WWDC25 230](https://developer.apple.com/videos/play/wwdc2025/230/) | Apple docs |
| F13 | "AlarmKit expects a widget extension if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert." | [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit) | Apple docs |
| F14 | When the Live Activity can't be shown (for example after a restart, before first unlock), the system shows its own countdown presentation built from `AlarmPresentation.Countdown`/`.Paused`. | [WWDC25 230](https://developer.apple.com/videos/play/wwdc2025/230/) | WWDC |
| F15 | `.fixed(Date)` is absolute and does **not** follow time-zone changes. `.relative` is wall-clock time in the device's current time zone, with optional weekly recurrence. | [fixed(_:)](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum/fixed(_:)), [relative(_:)](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum/relative(_:)), [WWDC25 230](https://developer.apple.com/videos/play/wwdc2025/230/) | Apple docs |
| F16 | One-shot alarms are deleted from the daemon once they fire and are stopped. To know whether one fired, keep your own list and compare it with `alarms`. | [alarms](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms) | Apple docs |
| F17 | Secondary intents are "only available after first unlock". | [AlarmConfiguration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration) | Apple docs |
| F18 | Custom sound: `AlertConfiguration.AlertSound.named(_:)` (ActivityKit). The file goes in the main bundle or in `Library/Sounds` in the app container. The default is `.default`. | [AlertSound](https://developer.apple.com/documentation/activitykit/alertconfiguration/alertsound), [named(_:)](https://developer.apple.com/documentation/activitykit/alertconfiguration/alertsound/named(_:)) | Apple docs |
| F19 | WWDC best practice: alarms suit countdowns and scheduled alerts such as a wake-up alarm. They "are not a replacement for other prominent notifications, like critical alerts or time-sensitive notifications." | [WWDC25 230](https://developer.apple.com/videos/play/wwdc2025/230/) | WWDC |
| F20 | The App Review Guidelines (last updated 8 June 2026) don't mention AlarmKit or alarms (fetched and searched). | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Apple docs (absence) |
| F21 | No AlarmKit capability exists in the developer portal capability list. `com.apple.developer.alarmkit` is LLM-invented, per an Apple engineer: "LLMs making up non-existent entitlements". | [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [forum 797950](https://developer.apple.com/forums/thread/797950) | Apple docs + Apple engineer |
| F22 | Time Sensitive: delivered immediately and "breaks through system notification controls" (Focus and Notification Summary). The user can turn it off. | [UNNotificationInterruptionLevel.timeSensitive](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive) | Apple docs |
| F23 | HIG table: Time Sensitive overrides scheduled delivery **Yes**, breaks through Focus **Yes**, overrides the Ring/Silent switch **No**. Only Critical overrides it, and Critical needs an entitlement. | [HIG: Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications), [.critical](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical) | Apple docs |
| F24 | HIG: use Time Sensitive only for "an event that's happening now or will happen within an hour". The first delivery explains it and offers to turn it off, and the system re-asks periodically. Users can "Turn off Time Sensitive" on Apple Watch. | [HIG: Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications) | Apple docs |
| F25 | The Time Sensitive Notifications capability exists for ADP and ADEP members, **not** free Apple Developer accounts. | [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) (row "Time Sensitive Notifications") | Apple docs |
| F26 | You enable Time Sensitive with the Xcode capability. Entitlement key `com.apple.developer.usernotifications.time-sensitive` = `true`. | [WWDC21 10091](https://developer.apple.com/videos/play/wwdc2021/10091/) ("enable the associated capability via Xcode"). Key string from [forum 691183](https://developer.apple.com/forums/thread/691183) (developer post). It is **not** in the [entitlements index](https://developer.apple.com/documentation/bundleresources/entitlements). | Capability: Apple. Key string: community |
| F27 | `UNAuthorizationOptions.timeSensitive` is **deprecated**. Don't request it. | [UNAuthorizationOptions](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions) | Apple docs |
| F28 | 64 cap: "the system keeps the soonest-firing 64 notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest." | [UILocalNotification](https://developer.apple.com/documentation/uikit/uilocalnotification) (deprecated class). Not restated in [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter). | Apple docs (legacy page) |
| F29 | Live Activities need `NSSupportsLiveActivities = YES` in the app's Info.plist (general ActivityKit setup). AlarmKit's own docs don't mention the key. | [NSSupportsLiveActivities](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities), [Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) | Apple docs (not AlarmKit-specific) |

### Community reliability reports (not Apple statements; treat as risks)
- **Fixed-schedule alarms occasionally fire at exactly 00:00** on iOS 26.1–26.5, for about 1–2 users per several thousand per day. FB22327481, FB22638314 and FB24496055 are cited. No Apple answer. See [forum 820388](https://developer.apple.com/forums/thread/820388) and [forum 815714](https://developer.apple.com/forums/thread/815714). One developer fixed it by **giving alarms stable IDs and diffing the current set against the desired set**, instead of cancelling everything and rescheduling at every update. Another still saw it after that.
- **Dense back-to-back alarm sequences fire late (20 s to 4+ min) or not at all on a locked device**, worse after many rounds of schedule/cancel. Rebooting helps temporarily. See [forum 825427](https://developer.apple.com/forums/thread/825427).
- **A relative alarm very close to now (about 2 min) seemed to land on the next day.** A DTS engineer asked for a bug report. The reporter later suspected a UI-state effect: alarms "fire silently (no UI) when the phone is unlocked and the app is in the foreground". See [forum 797618](https://developer.apple.com/forums/thread/797618).

**What this means for Phase 3:** the AlarmKit adapter must **diff, not wipe and reschedule**. Use stable alarm IDs derived from the reminder ID, keep few alarms, and avoid dense sequences.

## 2. AlarmKit API surface (current docs: iOS 26.0 base, 26.1 and 27.0 deltas)

### 2.1 Manager and authorization
- `class AlarmManager`, `static let shared: AlarmManager`. Not documented as `Sendable`, and no conformances are listed. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager)
- `func requestAuthorization() async throws -> AlarmManager.AuthorizationState` [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/requestauthorization())
- `var authorizationState: AlarmManager.AuthorizationState { get }` [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/authorizationstate-swift.property)
- `var authorizationUpdates: some AsyncSequence<AlarmManager.AuthorizationState, Never> { get }` [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/authorizationupdates)
- `enum AuthorizationState { case authorized, denied, notDetermined }`: Sendable, Codable, Hashable. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/authorizationstate-swift.enum)

### 2.2 Scheduling
- `func schedule<Metadata>(id: Alarm.ID, configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata: AlarmMetadata`. Passing a countdown shows the countdown UI first. Passing a schedule alerts at that time. Passing both gives a countdown before each scheduled alert. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/schedule(id:configuration:))
- `struct AlarmConfiguration<Metadata> where Metadata: AlarmMetadata` [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration):
  - `static func alarm(schedule: Alarm.Schedule? = nil, attributes: AlarmAttributes<Metadata>, stopIntent: (any LiveActivityIntent)? = nil, secondaryIntent: (any LiveActivityIntent)? = nil, sound: AlertConfiguration.AlertSound = .default)`: a traditional alarm. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/alarm(schedule:attributes:stopintent:secondaryintent:sound:))
  - `static func timer(duration: TimeInterval, attributes:, stopIntent:, secondaryIntent:, sound:)`: starts immediately and alerts after `duration`. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/timer(duration:attributes:stopintent:secondaryintent:sound:))
  - `init(countdownDuration: Alarm.CountdownDuration? = nil, schedule: Alarm.Schedule? = nil, attributes:, stopIntent:, secondaryIntent:, sound:)`: the general form, needed for snooze. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/init(countdownduration:schedule:attributes:stopintent:secondaryintent:sound:))
  - **iOS 27.0:** the same three, each with an extra `appEntityIdentifier: EntityIdentifier? = nil`. [alarm](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/alarm(schedule:attributes:appentityidentifier:stopintent:secondaryintent:sound:)), [init](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/init(countdownduration:schedule:attributes:appentityidentifier:stopintent:secondaryintent:sound:)), [timer](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration/timer(duration:attributes:appentityidentifier:stopintent:secondaryintent:sound:))
- Intents are `LiveActivityIntent` (App Intents). The probe passes none (all `nil`), because App Intents metadata generation under xtool is unproven (PHASE-0 item F).

### 2.3 Alarm, Schedule and CountdownDuration
- `struct Alarm`: `id: UUID` (`Alarm.ID`), `state: Alarm.State`, `schedule: Alarm.Schedule?`, `countdownDuration: Alarm.CountdownDuration?`. Sendable and Codable. [link](https://developer.apple.com/documentation/alarmkit/alarm)
- `enum Alarm.State { alerting, countdown, paused, scheduled }` [link](https://developer.apple.com/documentation/alarmkit/alarm/state-swift.enum)
- `enum Alarm.Schedule { case fixed(Date); case relative(Alarm.Schedule.Relative) }` [link](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum)
- `Alarm.Schedule.Relative(time: Relative.Time, repeats: Relative.Recurrence)`, `Relative.Time(hour: Int, minute: Int)`, `Recurrence { case never; case weekly([Locale.Weekday]) }`. There is **no daily or monthly recurrence and no date**: a relative never-repeating alarm fires at the next occurrence of hour:minute. Use `.fixed` for anything more than 24 h ahead. [Relative](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum/relative), [Recurrence](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum/relative/recurrence), [Time](https://developer.apple.com/documentation/alarmkit/alarm/schedule-swift.enum/relative/time-swift.struct)
- `Alarm.CountdownDuration(preAlert: TimeInterval?, postAlert: TimeInterval?)`. `postAlert` is the countdown used after the alarm has alerted, i.e. snooze or repeat. [link](https://developer.apple.com/documentation/alarmkit/alarm/countdownduration-swift.struct)

### 2.4 Presentation, attributes and metadata
- `AlarmAttributes<Metadata>(presentation: AlarmPresentation, metadata: Metadata? = nil, tintColor: Color)`. Conforms to `ActivityAttributes`. `typealias ContentState = AlarmPresentationState`. [link](https://developer.apple.com/documentation/alarmkit/alarmattributes)
- `protocol AlarmMetadata: Decodable, Encodable, Hashable, Sendable`. It may be empty. [link](https://developer.apple.com/documentation/alarmkit/alarmmetadata)
- `AlarmPresentation(alert: Alert, countdown: Countdown? = nil, paused: Paused? = nil)` [link](https://developer.apple.com/documentation/alarmkit/alarmpresentation/init(alert:countdown:paused:))
- `AlarmPresentation.Alert`: "The system provides a stop button automatically." [link](https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct)
  - **iOS 26.1+:** `init(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: SecondaryButtonBehavior? = nil)` [link](https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct/init(title:secondarybutton:secondarybuttonbehavior:))
  - **iOS 26.0, deprecated 26.1** ("stopButton is deprecated and will no longer be used"): `init(title:stopButton:secondaryButton:secondaryButtonBehavior:)` [link](https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct/init(title:stopbutton:secondarybutton:secondarybuttonbehavior:)). The probe picks between them with `#available(iOS 26.1, *)`.
  - `SecondaryButtonBehavior { countdown, custom }`. `.countdown` gives Repeat/Snooze and goes back to countdown for `postAlert`. `.custom` runs `secondaryIntent`, for example to open the app. [link](https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct/secondarybuttonbehavior-swift.enum)
- `AlarmPresentation.Countdown(title:, pauseButton: AlarmButton? = nil)` and `AlarmPresentation.Paused(title:, resumeButton: AlarmButton)` [Countdown](https://developer.apple.com/documentation/alarmkit/alarmpresentation/countdown-swift.struct), [Paused](https://developer.apple.com/documentation/alarmkit/alarmpresentation/paused-swift.struct)
- `AlarmButton(text: LocalizedStringResource, textColor: Color, systemImageName: String)` [link](https://developer.apple.com/documentation/alarmkit/alarmbutton)
- `AlarmPresentationState(alarmID:, mode:)` is system-managed. `Mode { case alert(Mode.Alert), countdown(Mode.Countdown), paused(Mode.Paused) }`. `Mode.Countdown` has `totalCountdownDuration`, `previouslyElapsedDuration`, `startDate` and `fireDate`. `Mode.Paused` has `totalCountdownDuration` and `previouslyElapsedDuration`. `Mode.Alert` has `time: Alarm.Schedule.Relative.Time`. [state](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate), [mode](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate/mode-swift.enum), [Countdown](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate/mode-swift.enum/countdown), [Paused](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate/mode-swift.enum/paused)

### 2.5 Sound
- The `sound:` parameter is `ActivityKit.AlertConfiguration.AlertSound`, either `.default` or `.named(String)`. See F18. **Undocumented:** maximum sound length, alarm volume behaviour (ringer volume or a separate alarm volume), and haptics.

### 2.6 State changes
- `cancel(id:) throws` deletes the alarm, even a repeating one. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/cancel(id:))
- `stop(id:) throws` deletes a one-shot alarm and moves a repeating one to its next occurrence. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/stop(id:))
- `pause(id:)` works only in countdown. `resume(id:)` works only when paused. `countdown(id:)` works only while alerting. All three `throws`. [AlarmManager](https://developer.apple.com/documentation/alarmkit/alarmmanager)

### 2.7 Observation
- `var alarms: [Alarm] { get throws }` returns the alarms of the current client from the daemon. [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms)
- `var alarmUpdates: some AsyncSequence<Array<Alarm>, Never> { get }` emits when an alarm alerts, snoozes or is dismissed. "An Alarm that's not included in the alarmUpdates asynchronous stream is no longer scheduled." [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmupdates-swift.property)

### 2.8 Errors
- `enum AlarmManager.AlarmError: Error { case maximumLimitReached }` [link](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmerror)

### 2.9 Availability outliers (from the full crawl of 127 symbol pages)
| Symbol | Availability |
|---|---|
| `AlarmPresentation.Alert.init(title:secondaryButton:secondaryButtonBehavior:)` | iOS 26.1 |
| `AlarmPresentation.Alert.init(title:stopButton:secondaryButton:secondaryButtonBehavior:)` | iOS 26.0, deprecated 26.1 |
| `AlarmConfiguration.alarm/timer/init(... appEntityIdentifier: ...)` (3 symbols) | iOS 27.0 |

### 2.10 Doc inconsistencies spotted
- The [AlarmConfiguration overview](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration) example passes `alertConfiguration: AlertConfiguration(title:body:sound:)`, but no documented initializer has that parameter. It looks stale, so it is ignored.
- WWDC25 code and the sample article still use `stopButton:`, which is deprecated since 26.1.
- `Mode.Countdown.fireDate` is described as "The date the countdown starts". In context it is when the countdown **ends** (the alert time). The probe treats it as the end.

## 3. Widget extension / Live Activity requirement
- **Required for:** any alarm with a countdown presentation. That means `timer(...)`, any `countdownDuration.preAlert`, and **snooze/repeat** (`secondaryButtonBehavior: .countdown` together with `postAlert`). See F13.
- **Not required for:** alert-only alarms (`.alarm(schedule:attributes:)` with no countdown).
- **Shape:** `ActivityConfiguration(for: AlarmAttributes<YourMetadata>.self) { lockScreen } dynamicIsland: { ... }` in the widget extension. Switch on `context.state.mode` (WWDC25 230, 9:15 code). The app never calls `Activity.request`; the system drives it.
- **Probe implementation:** `WidgetExtension/Sources/AlarmLiveActivity.swift`. The shared metadata type `AlarmProbeMetadata` lives in `Packages/TimetableUI/Sources/TimetableUI/AlarmProbeMetadata.swift`, guarded by `#if canImport(AlarmKit)`, so **both the App and TabulaWidgets targets must link TimetableUI**.
- Live Activities also appear in StandBy (WWDC25) and, as general ActivityKit behaviour, in the Apple Watch Smart Stack ([ActivityKit](https://developer.apple.com/documentation/activitykit)). Whether *alarm* Live Activities show in the Smart Stack is **unverified**.

## 4. Entitlements, capabilities, Info.plist; free vs paid account
| Item | Target | Needed for | Free account? | Source |
|---|---|---|---|---|
| `NSAlarmKitUsageDescription` (non-empty string) | App Info.plist | AlarmKit, all alarms | yes (Info.plist only) | F11 |
| `NSSupportsLiveActivities` = `YES` | App Info.plist | Live Activities generally. Added defensively for AlarmKit countdowns; AlarmKit docs don't name it. | yes | F29 |
| Widget extension containing `AlarmLiveActivity` | TabulaWidgets | countdown, timer and snooze alarms | expected yes (unverified under xtool) | F13 |
| `com.apple.developer.usernotifications.time-sensitive` = `true` | App entitlements | Time Sensitive interruption level | **no: ADP/ADEP only** | F25, F26 |
| ~~`com.apple.developer.alarmkit`~~ | n/a | **does not exist. Never add it.** | n/a | F21 |
| ~~`com.apple.developer.usernotifications.critical-alerts`~~ | n/a | not used (spec: no Critical Alerts) | n/a | NOTIFICATIONS.md |

So with a free account, AlarmKit and the countdown Live Activity should be testable, but **Time Sensitive is not**. If the app sets `.timeSensitive` without the entitlement, what actually gets delivered is **unverified**. The probe shows `timeSensitiveSetting` so this can be observed.

**State of the repo (checked 2026-10-04):**
- `Config/App-Info.plist` already has `NSAlarmKitUsageDescription` and `NSSupportsLiveActivities`.
- `Config/Tabula.entitlements` intentionally does **not** have the Time Sensitive key, because xtool 1.20.1 cannot provision it and adding it would break xtool-signed installs (env-ci note in that file).
- Consequence: **local xtool builds can only run matrix rows E0 and E9** (no entitlement). The real Time Sensitive rows (E1–E8) need a CI/TestFlight build with a CI-only entitlements file and a paid account.
- The plist usage string mentions "an exam tomorrow". See §8, item 4 about framing.

## 5. Limits and system behaviour
| Topic | Finding | Status |
|---|---|---|
| Max scheduled alarms | No fixed number. Dynamic, by device state and resources. You get `maximumLimitReached` when it's hit (F5). | **Undocumented number.** Measure with the probe (matrix F1, F2). |
| Silent mode | Rings through (F2). | Docs. Verify A2. |
| Focus (DND, Sleep, custom) | Breaks through all (F3). | DTS. Verify A3–A5. |
| Low Power Mode | Not mentioned anywhere. | **Undocumented.** Verify A6. |
| Force-quit, crash, reboot | Alarms persist (F4). | DTS. Verify A7–A9. |
| Before first unlock after reboot | The system countdown UI replaces the Live Activity (F14). Secondary intents only after first unlock (F17). Whether alerts ring before first unlock is not stated. | Partly documented. Verify A9 and B7. |
| Time-zone change | `.fixed` keeps its absolute instant; `.relative` follows the wall clock (F15). | Docs. Verify C1 and C2. |
| DST | Not mentioned. It follows from F15: `.fixed` stays absolute, `.relative` follows the wall clock. Correct `.fixed` dates need explicit `Calendar`/`TimeZone` when computing them (CLAUDE.md). | Inferred. Verify C3. |
| Apple Watch | The alert is forwarded to a paired Watch (F10). There is no watchOS AlarmKit, so the Watch app cannot schedule alarms (F1). | Docs. Verify A17 and A18 on Series 7 / watchOS 26. |
| Hidden or Face ID-locked app | Alarms silently fail (F6). | DTS. Verify A13. |
| Physical buttons | Stop and dismiss all alerting alarms (F7). | DTS. Verify A12. |
| App in foreground and unlocked | Forum report says the alarm may fire silently with no UI. | **Community report.** Verify A10. |
| App Review | Guidelines silent (F20). WWDC says alarms are not a substitute for Time Sensitive or critical notifications (F19). | **Policy risk.** See §8, item 4. |

## 6. Time Sensitive notifications
- **API:** `UNMutableNotificationContent.interruptionLevel = .timeSensitive` (iOS 15+). [interruptionLevel](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/interruptionlevel), [timeSensitive](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)
- **Read the state:** `UNNotificationSettings.timeSensitiveSetting: UNNotificationSetting` (`.enabled`, `.disabled`, `.notSupported`). [link](https://developer.apple.com/documentation/usernotifications/unnotificationsettings/timesensitivesetting)
- **Entitlement:** `com.apple.developer.usernotifications.time-sensitive` (F26). Paid programs only (F25). There is no special authorization option to request; `.timeSensitive` in `UNAuthorizationOptions` is deprecated (F27).
- **User controls:** a per-app Time Sensitive toggle; per-Focus "Time Sensitive Notifications" allowance; a first-delivery explanation with an opt-out and periodic re-evaluation; "Turn off Time Sensitive" on Apple Watch (F22, F24).
- **Silent switch:** **does not break through** (F23). This confirms the spec.
- **Usage rule (HIG):** only for events "happening now or will happen within an hour", and never for marketing (F24).

## 7. Pending local-notification cap (64)
- Apple's only current statement is on the deprecated [`UILocalNotification`](https://developer.apple.com/documentation/uikit/uilocalnotification) page (F28): the soonest-firing 64 are kept, the rest are **discarded silently**, and a repeating notification counts as one. It is not restated in the UserNotifications docs, so treat it as "documented (legacy page), widely relied on". The probe measures it on iOS 26/27 (matrix F3).
- **Planner implication** (already in the spec): never schedule more than 64. With repeats counting as one, a repeating `UNCalendarNotificationTrigger` uses only one slot.

## 8. Where NOTIFICATIONS.md and the docs disagree (for the human; not changed)
1. **"same permission model as the Clock app"** is inaccurate. AlarmKit uses a separate per-app opt-in prompt (with `NSAlarmKitUsageDescription`) and a Settings toggle (F12). The Clock app needs no prompt.
2. **"AlarmKit alarms are budgeted separately by verified limits"**: there is **no fixed limit to verify** (F5). Proposal: the planner treats `maximumLimitReached` as a normal outcome, keeps a small self-imposed alarm budget (to set after measuring matrix F1/F2), and surfaces "couldn't schedule loud alarm" just as it surfaces notification saturation.
3. **Time Sensitive with multi-day offsets** (rule model: "3 days, 1 day, morning-of") conflicts with the HIG rule "happening now or within an hour" (F24). Users can turn it off and the system keeps asking. Proposal: the planner downgrades Time Sensitive to Standard for offsets over 60 minutes before the event, and the rule editor explains this. **Decision needed.**
4. **Loud alarm "recommended for exam tomorrow"** vs WWDC: alarms "are not a replacement for … time-sensitive notifications" (F19). The App Review Guidelines don't mention AlarmKit (F20), but a reminder app ringing full-screen alarms is a plausible rejection or user-complaint risk. Proposal: frame the tier as "an alarm at a time you choose" (for example, wake-up on exam morning). The user explicitly picks the exact time, it is never auto-generated from offsets, and the count stays small. **Decision needed.**
5. **Snooze on loud alarms needs the widget extension** (F13). Phase 3 loud-alarm snooze therefore depends on `AlarmLiveActivity` shipping in the same build. It exists from Phase 0. Keep it, and treat it as a hard dependency in Phase 3/4 planning.
6. **Notification actions (Mark done / Snooze) for alarms** need App Intents (`stopIntent`/`secondaryIntent` are `LiveActivityIntent`). Secondary intents only work after first unlock (F17), and App Intents metadata generation under xtool is unproven (PHASE-0 item F). Expect CI-only until it is proven.
7. **The spec's test matrix is missing cases:** a hidden or Face ID-locked app (F6); physical buttons (F7); the app in the foreground; before first unlock after reboot; "Haptics in Silent Mode". All are added in §11.
8. **Health check (spec "Permissions UX"):** add "a hidden or locked app makes alarms silently fail" (F6) and the Time Sensitive setting row. Whether an app can *detect* that it is hidden or locked is unknown.
9. **Watch:** the Watch app can't schedule loud alarms (no watchOS AlarmKit, F1). It only receives alerts forwarded from the iPhone (F10).
10. **Where facts go:** the spec says to record AlarmKit facts in `docs/ENVIRONMENT.md`. This spike keeps them here. env-ci or the orchestrator should link this file from ENVIRONMENT.md.
11. **New design rule for Phase 3** (from community reports in §1): the AlarmKit adapter diffs the desired and current alarm sets using stable IDs. No cancel-all-and-reschedule, no dense alarm sequences.

## 9. Open questions (unverified until the device test or a build)
- Q1. The real alarm limit on iPhone 16 Pro Max (matrix F1, F2). Does the number change after a reboot?
- Q2. Behaviour in Low Power Mode, before first unlock, in the foreground while unlocked, and at minimum ringer volume (A6, A9, A10, A11).
- Q3. On the Watch: is it haptic only or with sound, can you stop or snooze from the Watch, and what happens with the Watch on the charger or in its own Silent mode (A17, A18)? Does the countdown Live Activity show in the Smart Stack (B6)?
- Q4. What does iOS do with `.timeSensitive` when the entitlement is missing (E0, E9)? Which `timeSensitiveSetting` value appears?
- Q5. Is the 64 cap still enforced the same way on iOS 26/27, and does `add()` throw or silently drop (F3)?
- Q6. When AlarmKit authorization is revoked, are already-scheduled alarms removed (G1)?
- Q7. Is AlarmKit independent of notification permission (A15)?
- Q8. **Build-level unknowns (need an SDK build):**
  - With the iOS 27 SDK, do calls without `appEntityIdentifier:` resolve to the iOS 26 overloads? This is expected (fewer defaulted parameters), but if the compiler reports ambiguity, pass the arguments explicitly or add a wrapper.
  - Does `nonisolated struct/enum` need Swift 6.1 or later? The Xcode 27 toolchain satisfies this.
  - Are AlarmKit enums frozen? If they are, `@unknown default` only produces warnings.
  - Does ActivityKit match `AlarmAttributes<AlarmProbeMetadata>` across the app and extension through the shared TimetableUI type?
- Q9. Does the widget extension and Live Activity work in a free-account / xtool-signed build?

## 10. The probe
> **Update (Phase 3 Stage A, 2026-10-10):** `AlarmProbeMetadata` was replaced by the production type `TabulaAlarmMetadata` (`Packages/TimetableUI/Sources/TimetableUI/Reminders/TabulaAlarmMetadata.swift`, kind `.probe` for these probes); the Live Activity renders `AlarmAttributes<TabulaAlarmMetadata>`. The table below is the Phase 0 state.
| File | Purpose |
|---|---|
| `App/Sources/Debug/AlarmProbes.swift` | `struct AlarmProbesSection: View`, a group of `Section`s to put inside a `List`/`Form`. It shows AlarmKit authorization with a request button; a 60 s fixed alarm; a 60 s alarm with a 1-min Snooze; a 2-min countdown; fixed and relative alarms with an adjustable delay for time-zone/DST tests; the scheduled-alarm list with per-alarm and cancel-all buttons; notification authorization, Time Sensitive, alert and sound settings, and the pending count; 10 s Standard and Time Sensitive notifications; an AlarmKit limit probe (up to 200 far-future alarms, then cancel); a pending-cap probe (70 far-future notifications, count, remove); and the last-result line. |
| `WidgetExtension/Sources/AlarmLiveActivity.swift` | `struct AlarmLiveActivity: Widget` with Lock Screen, StandBy and Dynamic Island presentations for `AlarmAttributes<AlarmProbeMetadata>` (countdown live, paused frozen, alerting). |
| `Packages/TimetableUI/Sources/TimetableUI/AlarmProbeMetadata.swift` | The shared `public struct AlarmProbeMetadata: AlarmMetadata`, guarded by `#if canImport(AlarmKit)`. |

**Build requirements (env-ci), checked 2026-10-04:**
- ✔ The App and TabulaWidgets targets both depend on `TimetableUI` (`Package.swift`, `project.yml`).
- ✔ `TabulaWidgetBundle` lists `AlarmLiveActivity()`.
- ✔ The App Info.plist has `NSAlarmKitUsageDescription` and `NSSupportsLiveActivities`.
- ✔ `DebugScreen` embeds `AlarmProbesSection()` inside a `List`.
- ✘ (by design) No Time Sensitive entitlement in local builds. A CI-only entitlements file with `com.apple.developer.usernotifications.time-sensitive` is needed for matrix rows E1–E8.

Static evidence available without the iOS SDK:
- `swiftc -parse -swift-version 6` passes on all three files (Swift 6.4). A deliberately broken file fails, as a negative control.
- `swift build` of a scratch copy of `TimetableUI` + `TimetableCore` on WSL Linux (Swift 6.4) passes with `AlarmProbeMetadata.swift` included, which proves the `#if canImport(AlarmKit)` guard works.
- Type-checking against AlarmKit, SwiftUI and WidgetKit needs the macOS CI or xtool build.

**Design choices:**
- Uses `ObservableObject` and `@Published` instead of `@Observable`, because macros are unproven under xtool.
- All AlarmKit and UserNotifications calls run in `nonisolated static` helpers that return Sendable values. None of `AlarmManager`, `UNUserNotificationCenter` or `UNNotificationSettings` is documented as Sendable.
- Debug strings are verbatim, matching `TimetableUI.ProbeRow`. Alarm titles are `LocalizedStringResource` literals, so Xcode may extract them into the String Catalog. The localisation engineer should mark them "don't translate" or delete them with the probe.
- No App Intents (`stopIntent`/`secondaryIntent` are `nil`).

## 11. Device test matrix (the human runs this with the probe)
**Setup:**
- Install the build. Grant AlarmKit and notification permission (use the probe's buttons).
- Note the iOS version (Settings > General > About) and the watchOS version.
- iPhone 16 Pro Max has **no Ring/Silent switch**. Toggle Silent with the Action button (if assigned) or Control Center.
- Set "Haptics in Silent Mode" (Settings > Sounds & Haptics) and record its value, because it changes what you feel.
- Fill in the **Observed** column and mark ✔ (as expected), ✘ (not as expected) or ? (unclear).

**Defaults unless a row says otherwise:** phone locked and face up, Silent ON, no Focus, Low Power OFF, Watch off wrist.

iOS version: ________ · watchOS version: ________ · Haptics in Silent Mode: on / off · Tester: ________ · Date: ________

### A. AlarmKit: "Schedule alarm in 60 s" (alert-only)
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| A1 | Silent OFF, lock the phone | Full-screen alarm with the title "Tabula test alarm" and the app name. Sound plays. System stop control (iOS 26.1+). (F2, §2.4) | | |
| A2 | Silent ON, lock the phone | **Rings with sound** (F2) | | |
| A3 | Silent ON + Do Not Disturb Focus | Rings (F3) | | |
| A4 | Sleep Focus on (turn on manually) | Rings (F3) | | |
| A5 | Custom Focus (for example "School") with Tabula **not** allowed | Rings (F3) | | |
| A6 | Low Power Mode ON | Undocumented; expected to ring | | |
| A7 | Schedule, then force-quit Tabula (swipe it away in the app switcher) | Rings (F4) | | |
| A8 | Use a 5-min fixed alarm (§C button), reboot, unlock once, wait | Rings (F4) | | |
| A9 | Use a 5-min fixed alarm, reboot, **do not unlock** | Undocumented; record whether it rings | | |
| A10 | Phone **unlocked with Tabula in the foreground** when it fires | Undocumented. A forum report says it may be silent or show no UI. Record. | | |
| A11 | Ringer volume at minimum, Silent OFF | Undocumented. Record loudness (ringer vs alarm volume). | | |
| A12 | While it rings, press the side button (then repeat with a volume button) | Stops the alarm (F7) | | |
| A13 | Hide Tabula or set "Require Face ID" (long-press the icon), schedule, lock | **Does not ring: silent failure** (F6). Undo it afterwards. | | |
| A14 | Settings > Tabula: turn AlarmKit (Alarms) off, then tap schedule | `schedule` throws, nothing rings (F12). The result line shows the error. | | |
| A15 | Notifications denied for Tabula, AlarmKit allowed | Expected to ring (separate authorizations). Unverified. | | |
| A16 | Airplane mode ON | Rings (local scheduling) | | |
| A17 | Watch on wrist and unlocked, iPhone locked | The alert is forwarded to the Watch (F10). Record haptic/sound and whether you can stop it from the Watch. | | |
| A18 | Watch in its own Silent mode, then repeat with the Watch on the charger | Record | | |
| A19 | "Schedule alarm in 60 s with 1-min Snooze" → tap **Snooze** | A countdown Live Activity appears (probe "fixed+snooze"). It rings again after about 60 s. (§2.3, §2.4, F13) | | |
| A20 | After an alarm fires and you stop it, open "Scheduled alarms" | It is gone from the list (F16) | | |

### B. AlarmKit: "Schedule 2-min countdown" (needs the widget extension)
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| B1 | Start it and lock | The Lock Screen shows the **custom** Live Activity: title "Tabula test countdown", "Tabula probe · countdown", and a ticking timer (F13). If only a generic system UI or nothing appears, the widget extension is missing or broken. | | |
| B2 | Unlocked, another app open | The Dynamic Island shows the compact timer. Long-press shows the expanded view (icon, timer, title). | | |
| B3 | Look for a Pause control anywhere (Lock Screen or system UI) | Our Live Activity has no buttons. Record whether the system adds Pause. If it does, test Pause then Resume (the paused view shows a frozen time). | | |
| B4 | Let it reach 0 with Silent ON | Alerts with sound: "Tabula test countdown finished" (F2) | | |
| B5 | StandBy (charging, landscape, locked) | The Live Activity is visible in StandBy (WWDC25 230) | | |
| B6 | Watch on wrist during the countdown | Record whether it appears in the Watch Smart Stack | | |
| B7 | Start it, reboot, don't unlock | The system countdown UI ("Tabula test countdown" with Pause) instead of the custom one (F14). It still alerts at 0. | | |

### C. Time zone / DST ("Time zone / DST probes" section, delay 5 min)
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| C1 | Schedule **both** the fixed and the relative alarm. Settings > General > Date & Time: Set Automatically OFF, then pick a zone **1 h west** (for example London if you are in Bratislava). | The fixed alarm rings at the original instant (the clock now shows 1 h earlier). The relative alarm rings at the original wall-clock time in the new zone, about 1 h later in real time (F15). | | |
| C2 | Same, but a zone **1 h east** (for example Helsinki) | Fixed: original instant. Relative: that wall-clock time has already passed in the new zone, so expect it to move to **tomorrow**. Record it, then cancel it in the list. | | |
| C3 | DST proxy: set the date/time manually to 2026-10-25 02:50 (Europe fall-back at 03:00 CEST → 02:00 CET) and schedule both with a 15-min delay | Fixed: 15 real minutes later. Relative: at the wall-clock time, possibly about 1 h later in real time. Record. Restore Set Automatically afterwards. | | |
| C4 | Restore automatic time zone and time | The scheduled list matches what you expect, with no stray alarms | | |

### D. "Standard notification in 10 s"
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| D1 | Silent OFF, lock | Banner on the Lock Screen and the default sound | | |
| D2 | Silent ON | **No sound** (haptic only if Haptics in Silent Mode is on) (F23) | | |
| D3 | DND Focus, Tabula not allowed | Silenced. Appears in Notification Center later. (F23) | | |
| D4 | Sleep Focus | Silenced | | |
| D5 | Scheduled Summary includes Tabula | Held for the summary (F23) | | |
| D6 | Low Power Mode | Delivered (expected) | | |
| D7 | Schedule, force-quit Tabula | Delivered (local notifications don't need the app running) | | |
| D8 | Schedule, reboot immediately | Record (delivered after boot? when?) | | |
| D9 | Watch on wrist and unlocked, iPhone locked | Shows on the Watch (iPhone settings apply to the Watch by default) (HIG watchOS) | | |
| D10 | Notifications denied in Settings | Nothing is delivered. Record whether `add()` reported an error. | | |

### E. "Time Sensitive notification in 10 s"
> Local xtool builds have no Time Sensitive entitlement (see §4), so on those builds run only E0 and E9. Run E1–E8 on a CI/TestFlight build that has the entitlement.

| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| E0 | Read the "Time Sensitive setting" row before testing | `enabled` if the entitlement is in the build. Otherwise record the value (`notSupported`? `disabled`?). | | |
| E1 | Silent ON, no Focus | **No sound** (F23) | | |
| E2 | DND Focus, Tabula not allowed, Focus "Time Sensitive Notifications" allowed (Settings > Focus > Do Not Disturb > Apps) | **Breaks through**: banner and screen lights up. Still no sound if Silent is ON. (F22, F23) | | |
| E3 | Same, with the Focus Time Sensitive allowance OFF | Held like Standard (F24) | | |
| E4 | Sleep Focus | Record | | |
| E5 | Scheduled Summary includes Tabula | Delivered immediately, not held (F23) | | |
| E6 | The first Time Sensitive delivery ever | The system explains Time Sensitive and offers to turn it off (F24) | | |
| E7 | Watch on wrist | Delivered. Swiping left offers "Turn off Time Sensitive". (F24) | | |
| E8 | Settings > Notifications > Tabula > Time Sensitive OFF | Behaves like Standard. The row shows `disabled`. (F22) | | |
| E9 | (Only if E0 ≠ enabled) Repeat E2 | Record. This shows what iOS does without the entitlement. | | |

### F. Limit probes (run LAST, then reboot)
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| F1 | "Probe AlarmKit limit", run 1 | Stops with `maximumLimitReached` after N alarms, or reaches the probe's 200 cap. Cleanup cancels all of them. (F5) | N1 = | |
| F2 | Reboot, run it again | N2 may differ (the limit is dynamic, F5) | N2 = | |
| F3 | "Probe pending-notification cap" | "pending after adding" shows **64** total (if there were no others). Record whether `add()` threw for #65–70. (F28) | | |
| F4 | Reboot, open the probe | "Scheduled alarms" is empty and pending shows 0 from the probe. Nothing rings in the following days. | | |

### G. Permission revoked and re-granted
| ID | Condition / steps | Expected (source) | Observed | ✔/✘ |
|---|---|---|---|---|
| G1 | Schedule a 5-min fixed alarm, then turn AlarmKit off in Settings and return to the app | The authorization row updates to `denied` without relaunching (authorizationUpdates). Record whether the scheduled alarm stays in the list and whether it rings. | | |
| G2 | Turn it back on | The row shows `authorized`, and new alarms schedule again | | |
