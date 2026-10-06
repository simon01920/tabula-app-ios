// COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629). Not yet run on a device. Phase 0 AlarmKit probe; Phase 4 replaces it with the real design.
// APIs checked on 2026-10-04 against developer.apple.com JSON docs; citations in docs/spikes/ALARMKIT.md.
//
// APIs used
//   WidgetKit: Widget, ActivityConfiguration(for:content:dynamicIsland:) (iOS 16.1), ActivityViewContext (.attributes, .state),
//     DynamicIsland(expanded:compactLeading:compactTrailing:minimal:), DynamicIslandExpandedRegion(_:priority:content:)
//     with .leading / .trailing / .bottom, DynamicIsland.keylineTint(_:)
//   AlarmKit (iOS 26.0): AlarmAttributes<Metadata> (conforms to ActivityAttributes; ContentState = AlarmPresentationState),
//     .presentation (.alert.title, .countdown?.title, .paused?.title), .metadata, .tintColor,
//     AlarmPresentationState.mode: .countdown(Mode.Countdown: startDate, fireDate, totalCountdownDuration,
//     previouslyElapsedDuration), .paused(Mode.Paused: totalCountdownDuration, previouslyElapsedDuration), .alert(Mode.Alert)
//   SwiftUI: Text(timerInterval:pauseTime:countsDown:showsHours:), Text(LocalizedStringResource), Text(verbatim:)
//   TimetableUI: AlarmProbeMetadata (shared with the app; the TabulaWidgets target must link TimetableUI)
//
// Why this exists: Apple's AlarmKit sample says "AlarmKit expects a widget extension if an app supports a countdown
// presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert." Plain alert-only alarms
// (the 60 s probe) do not need it. Countdowns, timers and snooze (which goes back to a countdown) do.
// The system supplies AlarmPresentationState; the app never starts or updates this Live Activity itself.
//
// Strings are verbatim / taken from the alarm's own presentation: developer-facing probe, not in the String Catalog.

import ActivityKit
import AlarmKit
import SwiftUI
import TimetableUI
import WidgetKit

/// Lock Screen, StandBy and Dynamic Island presentation for alarms scheduled with
/// `AlarmAttributes<AlarmProbeMetadata>`. Registered in the TabulaWidgets `WidgetBundle`.
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmProbeMetadata>.self) { context in
            AlarmProbeLockScreenView(context: context)
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor
            let title = AlarmProbeDisplay.title(attributes: context.attributes, mode: context.state.mode)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AlarmProbeRemainingText(mode: context.state.mode)
                        .font(.title3.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(tint)
                    .accessibilityLabel(Text(verbatim: "Tabula alarm"))
            } compactTrailing: {
                AlarmProbeRemainingText(mode: context.state.mode)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(tint)
                    .accessibilityLabel(Text(verbatim: "Tabula alarm"))
            }
            .keylineTint(tint)
        }
    }
}

/// Lock Screen / StandBy banner. Text stays in the default foreground colour; the user-visible tint is only
/// used for the icon, so contrast does not depend on the alarm's tint colour.
struct AlarmProbeLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmProbeMetadata>>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(context.attributes.tintColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlarmProbeDisplay.title(attributes: context.attributes, mode: context.state.mode))
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: "Tabula probe · \(context.attributes.metadata?.probeKind ?? "no metadata")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AlarmProbeRemainingText(mode: context.state.mode)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

/// Remaining time: a live countdown while counting down, a frozen value while paused.
struct AlarmProbeRemainingText: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch AlarmProbeDisplay.state(for: mode) {
        case .countingDown(let interval):
            Text(timerInterval: interval, countsDown: true)
        case .paused(let remaining):
            let now = Date()
            Text(timerInterval: now...now.addingTimeInterval(remaining), pauseTime: now, countsDown: true)
        case .alerting:
            Text(verbatim: "Ringing")
        }
    }
}

/// Maps AlarmKit's state to a small local enum, so the view builders above switch over a type we own
/// (no `@unknown default` inside result builders).
enum AlarmProbeDisplay {
    enum State {
        case countingDown(ClosedRange<Date>)
        case paused(TimeInterval)
        case alerting
    }

    static func state(for mode: AlarmPresentationState.Mode) -> State {
        switch mode {
        case .countdown(let countdown):
            // startDate = most recent (re)start, fireDate = when it alerts. Guard against an inverted range,
            // which would trap when forming a ClosedRange.
            let start = min(countdown.startDate, countdown.fireDate)
            return .countingDown(start...countdown.fireDate)
        case .paused(let paused):
            return .paused(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration))
        case .alert:
            return .alerting
        @unknown default:
            return .alerting
        }
    }

    static func title(attributes: AlarmAttributes<AlarmProbeMetadata>,
                      mode: AlarmPresentationState.Mode) -> LocalizedStringResource {
        switch mode {
        case .countdown:
            return attributes.presentation.countdown?.title ?? attributes.presentation.alert.title
        case .paused:
            return attributes.presentation.paused?.title ?? attributes.presentation.alert.title
        case .alert:
            return attributes.presentation.alert.title
        @unknown default:
            return attributes.presentation.alert.title
        }
    }
}
