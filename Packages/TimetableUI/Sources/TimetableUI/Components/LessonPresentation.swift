// View-independent presentation of a resolved lesson: the field rule, the status badge and the VoiceOver sentence.
// Pure (no SwiftUI), Linux-tested. Every lesson view (Today tiles, grid cells, day list, editors' previews) must use
// these so the PRODUCT.md field rule is implemented once:
//   a disabled field is hidden everywhere; an enabled-but-empty field is absent (no placeholder, dash or blank line).
import Foundation
import TimetableCore

/// The optional lesson fields that may be shown: visible in the timetable *and* non-empty, nothing else.
public struct VisibleLessonFields: Equatable, Sendable {
    public var room: String?
    public var building: String?
    public var teacher: String?
    public var lessonType: LessonType?
    public var notes: String?
    /// Non-blank items only; empty when hidden.
    public var bringList: [String]

    /// Applies the field rule to `lesson` with the timetable's `visibility`.
    public init(lesson: ResolvedLesson, visibility: FieldVisibility) {
        func text(_ value: String?, _ field: LessonField) -> String? {
            guard visibility.isVisible(field), let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        room = text(lesson.room, .room)
        building = text(lesson.building, .building)
        teacher = text(lesson.teacher, .teacher)
        lessonType = visibility.isVisible(.lessonType) ? lesson.lessonType.flatMap {
            $0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } : nil
        notes = text(lesson.notes, .notes)
        bringList = visibility.isVisible(.bringList)
            ? lesson.bringList.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            : []
    }

    /// `true` when no optional field is shown.
    public var isEmpty: Bool {
        room == nil && building == nil && teacher == nil && lessonType == nil && notes == nil && bringList.isEmpty
    }

    /// Catalog key of a lesson type's display name (`lessonType.<raw>`), or `nil` for a value this version does
    /// not know (show its raw text: it is user/newer-version data).
    public static func nameKey(of type: LessonType) -> String? {
        type.isKnown ? "lessonType.\(type.rawValue)" : nil
    }
}

/// The status badge of a lesson (modified / cancelled / added). Always icon + text, never colour alone.
public struct LessonStatusBadgeModel: Equatable, Sendable {
    /// Badge kind (drives the tint; the text and icon carry the meaning).
    public enum Kind: Equatable, Sendable { case modified, cancelled, added }

    public let kind: Kind
    /// SF Symbol.
    public let symbolName: String
    /// Catalog key of the short badge text.
    public let titleKey: String

    /// The badge for a lesson, or `nil` for a regular (`.scheduled`) lesson.
    /// A modified lesson with exactly one reason shows that reason ("Room changed"); several → "Changed".
    public static func make(status: ResolvedLesson.Status, reasons: [ModificationReason]) -> LessonStatusBadgeModel? {
        switch status {
        case .scheduled:
            return nil
        case .cancelled:
            return LessonStatusBadgeModel(kind: .cancelled, symbolName: "xmark.circle", titleKey: "lesson.status.cancelled")
        case .added:
            return LessonStatusBadgeModel(kind: .added, symbolName: "plus.circle", titleKey: "lesson.status.added")
        case .modified:
            let key = reasons.count == 1 ? reasons[0].l10nKey : "lesson.status.modified"
            return LessonStatusBadgeModel(kind: .modified, symbolName: "arrow.triangle.2.circlepath", titleKey: key)
        }
    }
}

/// Builds the single VoiceOver sentence of a lesson, e.g.
/// "Matematika, 2. hodina, 8:55 až 9:40, učebňa 214, zmenené: iná učebňa".
///
/// Each part is one complete catalog phrase (its own format with arguments); parts are joined with the catalog's
/// list separator (`a11y.separator`, ", " in English, "、" in Japanese). Hidden or empty fields are omitted.
public enum LessonAccessibilityLabel {
    /// The sentence for `lesson`.
    public static func make(lesson: ResolvedLesson, visibility: FieldVisibility, reasons: [ModificationReason],
                            renderer: LocalizedTextRenderer) -> String {
        parts(lesson: lesson, visibility: visibility, reasons: reasons, renderer: renderer)
            .joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    /// The individual phrases, in reading order (exposed for tests).
    public static func parts(lesson: ResolvedLesson, visibility: FieldVisibility, reasons: [ModificationReason],
                             renderer: LocalizedTextRenderer) -> [String] {
        let fields = VisibleLessonFields(lesson: lesson, visibility: visibility)
        let formatter = renderer.formatter
        var parts: [String] = [lesson.subject.name]
        if let number = lesson.periodNumber {
            parts.append(renderer.format(key: "a11y.lesson.period", arguments: [.integer(Int64(number))]))
        } else if let label = lesson.periodLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            parts.append(renderer.format(key: "a11y.lesson.periodLabel", arguments: [.text(label)]))
        }
        parts.append(renderer.format(key: "a11y.lesson.time", arguments: [
            .text(formatter.time(lesson.startTime)), .text(formatter.time(lesson.endTime)),
        ]))
        if let room = fields.room { parts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }
        if let building = fields.building {
            parts.append(renderer.format(key: "a11y.lesson.building", arguments: [.text(building)]))
        }
        if let teacher = fields.teacher {
            parts.append(renderer.format(key: "a11y.lesson.teacher", arguments: [.text(teacher)]))
        }
        if let type = fields.lessonType {
            parts.append(VisibleLessonFields.nameKey(of: type).map(renderer.string(forKey:)) ?? type.rawValue)
        }
        if let notes = fields.notes { parts.append(renderer.format(key: "a11y.lesson.notes", arguments: [.text(notes)])) }
        if !fields.bringList.isEmpty {
            parts.append(renderer.format(key: "a11y.lesson.bring", arguments: [.text(formatter.list(fields.bringList))]))
        }
        switch lesson.status {
        case .scheduled:
            break
        case .cancelled:
            parts.append(renderer.string(forKey: "a11y.lesson.cancelled"))
        case .added:
            parts.append(renderer.string(forKey: "a11y.lesson.added"))
        case .modified:
            if reasons.isEmpty {
                parts.append(renderer.string(forKey: "a11y.lesson.modified"))
            } else {
                let what = formatter.list(reasons.map { renderer.string(forKey: $0.l10nKey) })
                parts.append(renderer.format(key: "a11y.lesson.modifiedReasons", arguments: [.text(what)]))
            }
        }
        return parts
    }
}
