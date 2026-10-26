// When an editor shows a validation message (Phase 4U U1, Opus review M5 and §3 "keep: Save stays disabled until
// required fields are filled, with a hint"). Pure, Linux-tested; the SwiftUI side is `ValidationMessage` /
// `EditorTitleField` in App/Sources/Editors/EditorSupport.swift.
//
// - A hint says what is still missing ("Enter a title to save the exam.", "Enter at least one change."). It is shown
//   from the moment the editor opens, in secondary text, next to the disabled Save, so the user knows why Save is off.
// - An error says a value is wrong ("The end is before the start."). It is shown in the correction colour only after
//   the user has edited the draft: never on a form nobody has touched (M5: red "Enter at least one change." on open).
// - Save stays disabled while the draft cannot be saved (`EditorScaffold`).
import Foundation

/// The kind of a validation message.
public enum ValidationSeverity: Sendable, Equatable {
    /// Something required is still missing (secondary text, always visible).
    case hint
    /// A value is wrong (correction colour, after the first edit).
    case error
}

/// The visibility rule of validation messages.
public enum ValidationVisibility {
    /// Errors become visible once the draft was edited (`EditorScaffold`: `edited != nil`).
    public static func errorsVisible(hasEdited: Bool) -> Bool { hasEdited }

    /// Whether a message of `severity` is shown.
    public static func isShown(_ severity: ValidationSeverity, hasEdited: Bool) -> Bool {
        switch severity {
        case .hint: return true
        case .error: return errorsVisible(hasEdited: hasEdited)
        }
    }
}
