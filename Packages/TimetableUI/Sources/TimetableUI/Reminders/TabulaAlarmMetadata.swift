// Metadata of every AlarmKit alarm the app schedules: production loud alarms (Phase 3 Stage A), the health check's
// test alarm and the DEBUG-only Phase 0 probes. Replaces the Phase 0 `AlarmProbeMetadata` (one type, no duplication).
// APIs (checked against developer.apple.com DocC JSON, docs/spikes/ALARMKIT.md §2.4):
//   AlarmKit.AlarmMetadata (protocol: Decodable, Encodable, Hashable, Sendable; iOS/iPadOS/Mac Catalyst 26.0, NOT watchOS/macOS)
//
// Why this lives in TimetableUI: the app schedules alarms with `AlarmAttributes<TabulaAlarmMetadata>` and the
// TabulaWidgets extension renders the countdown/snooze Live Activity with
// `ActivityConfiguration(for: AlarmAttributes<TabulaAlarmMetadata>.self)`. ActivityKit matches the attributes type, so
// both targets must use the SAME type: it lives in a module both link (App and TabulaWidgets depend on TimetableUI).
// TimetableUI also builds for watchOS, macOS and Linux, where AlarmKit does not exist, so the file is guarded.
//
// Keep the stored properties Codable-stable: a scheduled alarm carries its encoded metadata across app updates.
// New fields must be optional.

#if canImport(AlarmKit) && os(iOS)
import AlarmKit

/// Metadata attached to every alarm Tabula schedules.
@available(iOS 26.0, macCatalyst 26.0, *)
public struct TabulaAlarmMetadata: AlarmMetadata {
    /// What scheduled the alarm.
    public enum Kind: String, Codable, Hashable, Sendable {
        /// A loud-alarm reminder from the planner.
        case reminder
        /// The health check's "test alarm" button.
        case test
        /// A DEBUG-only Phase 0 probe.
        case probe
    }

    public var kind: Kind
    /// The planner's reminder id (`rem.…`); empty for tests/probes.
    public var reminderID: String
    /// `ReminderSource.rawValue` (`exam/<UUID>` …); empty for tests/probes.
    public var source: String
    /// Secondary line for the Live Activity (rendered at scheduling time), or the probe kind for probes.
    public var subtitle: String?

    public init(kind: Kind, reminderID: String = "", source: String = "", subtitle: String? = nil) {
        self.kind = kind
        self.reminderID = reminderID
        self.source = source
        self.subtitle = subtitle
    }
}
#endif
