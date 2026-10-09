// The visible optional fields of a lesson as display lines (icon + value), built on `VisibleLessonFields` so the
// PRODUCT.md field rule holds in every tile, row and detail screen: a disabled field is hidden, an enabled-but-empty
// field produces no line at all (no placeholder, dash or blank line). Pure, Linux-tested.
import Foundation
import TimetableCore

/// One optional field of a lesson, ready to display.
public enum LessonFieldLine: Equatable, Sendable, Identifiable {
    case room(String)
    case building(String)
    case teacher(String)
    case lessonType(LessonType)
    case notes(String)
    /// Non-empty bring list (user order).
    case bring([String])

    /// Which field it is.
    public var field: LessonField {
        switch self {
        case .room: return .room
        case .building: return .building
        case .teacher: return .teacher
        case .lessonType: return .lessonType
        case .notes: return .notes
        case .bring: return .bringList
        }
    }

    public var id: String { field.rawValue }

    /// SF Symbol shown before the value (decorative: VoiceOver reads `LessonAccessibilityLabel`).
    public var symbolName: String {
        switch self {
        case .room: return "door.left.hand.open"
        case .building: return "building.2"
        case .teacher: return "person"
        case .lessonType: return "tag"
        case .notes: return "note.text"
        case .bring: return "backpack"
        }
    }

    /// The value text. Lesson types use the catalog name (`lessonType.<raw>`), unknown types their raw value;
    /// the bring list is a locale list ("A, B and C").
    public func text(renderer: LocalizedTextRenderer) -> String {
        switch self {
        case .room(let value), .building(let value), .teacher(let value), .notes(let value):
            return value
        case .lessonType(let type):
            return VisibleLessonFields.nameKey(of: type).map(renderer.string(forKey:)) ?? type.rawValue
        case .bring(let items):
            return renderer.formatter.list(items)
        }
    }
}

/// Builds field lines in a fixed reading order.
public enum LessonFieldLines {
    /// Every visible, non-empty field of `fields` in the order room, building, teacher, type, notes, bring list,
    /// optionally restricted to `only` (e.g. a compact tile shows room + teacher).
    public static func make(_ fields: VisibleLessonFields, only: Set<LessonField>? = nil) -> [LessonFieldLine] {
        var lines: [LessonFieldLine] = []
        if let room = fields.room { lines.append(.room(room)) }
        if let building = fields.building { lines.append(.building(building)) }
        if let teacher = fields.teacher { lines.append(.teacher(teacher)) }
        if let type = fields.lessonType { lines.append(.lessonType(type)) }
        if let notes = fields.notes { lines.append(.notes(notes)) }
        if !fields.bringList.isEmpty { lines.append(.bring(fields.bringList)) }
        guard let only else { return lines }
        return lines.filter { only.contains($0.field) }
    }

    /// Shorthand: the lines of `lesson` under `visibility`.
    public static func make(lesson: ResolvedLesson, visibility: FieldVisibility,
                            only: Set<LessonField>? = nil) -> [LessonFieldLine] {
        make(VisibleLessonFields(lesson: lesson, visibility: visibility), only: only)
    }
}
