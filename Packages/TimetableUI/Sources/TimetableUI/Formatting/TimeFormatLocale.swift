// The app-wide time-format locale (Phase 4U U1, D4 / Opus review H1, Astra F22). Pure Foundation, Linux-tested.
//
// Effective time format = the app setting when it is 12-hour or 24-hour, else System (the device's
// Settings › General › Date & Time › 24-Hour Time, which `Locale.current` reflects). The stored setting is the open
// vocabulary `AppSettings.hourCycle` (`auto` / `h12` / `h24`): its default is already `auto` = System and unknown
// values (newer app versions) behave as `auto`, so no schema change is needed.
//
// The app root injects this locale with `.environment(\.locale, …)` (AppRootView), so every `DatePicker` and SwiftUI
// date text shows the same clock as the app's own `TimetableFormatter` text.
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
