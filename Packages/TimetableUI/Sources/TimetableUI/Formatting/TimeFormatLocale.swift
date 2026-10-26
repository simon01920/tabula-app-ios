// The app-wide time-format locale (Phase 4U U1, D4 / Opus review H1, Astra F22). Pure Foundation, Linux-tested.
//
// Effective time format = the app setting when it is 12-hour or 24-hour, else System (the device's
// Settings › General › Date & Time › 24-Hour Time, which `Locale.current` reflects). The stored setting is the open
// vocabulary `AppSettings.hourCycle` (`auto` / `h12` / `h24`): its default is already `auto` = System and unknown
// values (newer app versions) behave as `auto`, so no schema change is needed.
//
// The time pickers get this locale through `.hourCycleLocale(_:)` (TimeRow, the onboarding time picker), so they
// show the same clock as the app's own `TimetableFormatter` text. It is deliberately not injected at the app root
// (RISKS #87): there `\.locale` would also drive string lookup and replace the user's iOS region preferences.
// Linux tests: the script, region, calendar and first weekday survive the round trip (sr-Latn_RS, zh-Hans_CN, pt_BR).
// APIs (Apple docs JSON, checked 2026-10-23): Locale.Components.init(locale:), Locale.Components.hourCycle
//   (`Locale.HourCycle?`, iOS 16), Locale.init(components:) (iOS 16), Locale.hourCycle (iOS 16).
import Foundation
import TimetableCore

/// Builds the locale with the effective hour cycle.
public enum TimeFormatLocale {
    /// `system` with the setting's hour cycle applied; `system` itself when the setting is System (`auto`) or unknown.
    public static func locale(system: Locale, setting: HourCycle) -> Locale {
        TimetableFormatter.applying(setting, to: system)
    }

    /// The picker choice the setting resolves to (unknown stored values show System).
    public static func effectiveChoice(_ setting: HourCycle) -> HourCycleChoice {
        HourCycleChoice(setting)
    }
}
