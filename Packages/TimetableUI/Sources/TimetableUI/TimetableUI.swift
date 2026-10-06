// Phase 0 placeholder for shared SwiftUI components. UNCOMPILED for Apple platforms (no SDK yet).
// APIs used (checked against developer.apple.com JSON docs, see docs/ENVIRONMENT.md "API checks"):
//   SwiftUI.View, Text(verbatim:), Label, HStack, Image(systemName:), accessibilityElement(children:),
//   accessibilityLabel(_:)

/// Namespace marker so the module has a stable symbol on every platform (including Linux).
public enum TimetableUIInfo {
    public static let moduleName = "TimetableUI"
}

/// Keys shared between the app and its extensions for the Phase 0 App Group round-trip probe.
/// Temporary: delete together with the debug probes once Phase 0 is signed off.
public enum Phase0ProbeKeys {
    /// Written by the app (ISO-8601 timestamp string).
    public static let appWrite = "phase0.appGroup.appWrite"
    /// Written by the widget: "<value it read> @ <timestamp>".
    public static let widgetSaw = "phase0.appGroup.widgetSaw"
    /// Written by the App Intent probe when it runs (Unix time as Double).
    public static let intentRun = "phase0.appIntent.lastRun"
    /// File name used for the shared-container file round-trip.
    public static let fileName = "phase0-probe.txt"
}

#if canImport(SwiftUI)
import SwiftUI

/// Outcome of a single probe, rendered with icon + text so status is not conveyed by colour alone.
public enum ProbeStatus: Sendable, Equatable {
    case pass
    case fail
    case info
    case pending

    var symbolName: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.octagon.fill"
        case .info: "info.circle"
        case .pending: "hourglass"
        }
    }

    var word: String {
        switch self {
        case .pass: "PASS"
        case .fail: "FAIL"
        case .info: "INFO"
        case .pending: "PENDING"
        }
    }

    var tint: Color {
        switch self {
        case .pass: .green
        case .fail: .red
        case .info: .secondary
        case .pending: .orange
        }
    }
}

/// One row of a debug/probe screen. Developer-facing: strings are intentionally verbatim
/// (not localized) and the row is not shipped in release UI.
public struct ProbeRow: View {
    private let title: String
    private let value: String
    private let status: ProbeStatus

    public init(_ title: String, value: String, status: ProbeStatus = .info) {
        self.title = title
        self.value = value
        self.status = status
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    // .textSelection is unavailable on watchOS (verified in docs), so it is not used here.
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(status.word): \(title), \(value)"))
    }
}
#endif
