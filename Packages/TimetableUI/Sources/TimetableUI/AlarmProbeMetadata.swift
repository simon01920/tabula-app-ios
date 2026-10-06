// COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629). Phase 0 AlarmKit probe; delete with the debug probes after sign-off.
// APIs used (checked 2026-10-04 against developer.apple.com JSON docs, see docs/spikes/ALARMKIT.md):
//   AlarmKit.AlarmMetadata (protocol: Decodable, Encodable, Hashable, Sendable; iOS/iPadOS/Mac Catalyst 26.0, NOT watchOS/macOS)
//
// Why this lives in TimetableUI: the app schedules alarms with `AlarmAttributes<AlarmProbeMetadata>` and the
// TabulaWidgets extension renders the countdown Live Activity with
// `ActivityConfiguration(for: AlarmAttributes<AlarmProbeMetadata>.self)`. Both sides must use the SAME metadata
// type, so it lives in a module that both targets link. The App and TabulaWidgets targets must depend on TimetableUI.
//
// TimetableUI also builds for watchOS and macOS, where AlarmKit does not exist, so the file is guarded.

#if canImport(AlarmKit) && os(iOS)
import AlarmKit

/// Metadata attached to every alarm the Phase 0 probe schedules. The Live Activity shows `probeKind`
/// so a tester can tell which probe produced the countdown they are looking at.
@available(iOS 26.0, macCatalyst 26.0, *)
public struct AlarmProbeMetadata: AlarmMetadata {
    /// Short, developer-facing tag, for example "countdown", "fixed+snooze" or "limit-probe".
    public var probeKind: String

    public init(probeKind: String) {
        self.probeKind = probeKind
    }
}
#endif
