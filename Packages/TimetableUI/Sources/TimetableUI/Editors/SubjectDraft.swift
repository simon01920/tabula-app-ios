// Edit state of the subject editor: name, colour (palette pack colour or custom), symbol, defaults and the live
// contrast check of the tile preview. Pure, Linux-tested.
import Foundation
import TimetableCore

/// The subject editor's state.
public struct SubjectDraft: Equatable, Sendable {
    /// How the colour was chosen.
    public enum ColorChoice: Equatable, Sendable {
        /// A colour of a palette pack (`id` is `PaletteColor.id`).
        case palette(pack: PalettePackID, colorID: String)
        /// Any colour from the system colour picker.
        case custom(ColorValue)
    }

    /// Which kind of symbol the subject shows.
    public enum SymbolKind: String, Equatable, Sendable, CaseIterable { case none, emoji, systemImage }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable {
        case noName

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.subject.issue.\(rawValue)" }
    }

    /// WCAG AA for normal text; below this the tile preview shows a warning.
    public static let minimumContrast = 4.5

    /// SF Symbols offered by the symbol picker (names verified in SF Symbols 5/6).
    public static let symbolSuggestions: [String] = [
        "book.fill", "function", "atom", "testtube.2", "globe.europe.africa.fill", "music.note",
        "paintpalette.fill", "figure.run", "laptopcomputer", "pencil", "theatermasks.fill", "leaf.fill",
        "building.columns.fill", "character.book.closed.fill", "flag.fill", "hammer.fill", "camera.fill",
        "heart.fill", "star.fill", "brain.head.profile",
    ]

    public let subjectID: Subject.ID
    public let timetableID: Timetable.ID
    public let isNew: Bool
    public var name: String
    public var shortName: String
    public var colorChoice: ColorChoice
    public var symbolKind: SymbolKind
    public var emoji: String
    public var systemImage: String
    public var defaultRoom: String
    public var defaultBuilding: String
    public var defaultTeacher: String
    public var notes: String
    private let base: Subject

    /// Edits `subject`.
    public init(subject: Subject) {
        subjectID = subject.id
        timetableID = subject.timetableID
        isNew = false
        base = subject
        name = subject.name
        shortName = subject.shortName ?? ""
        colorChoice = Self.choice(for: subject.color)
        switch subject.symbol {
        case .emoji(let value)?:
            symbolKind = .emoji
            emoji = value
            systemImage = Self.symbolSuggestions[0]
        case .systemImage(let value)?:
            symbolKind = .systemImage
            emoji = ""
            systemImage = value
        case nil:
            symbolKind = .none
            emoji = ""
            systemImage = Self.symbolSuggestions[0]
        }
        defaultRoom = subject.defaultRoom ?? ""
        defaultBuilding = subject.defaultBuilding ?? ""
        defaultTeacher = subject.defaultTeacher ?? ""
        notes = subject.notes ?? ""
    }

    /// A new subject in `timetable`; the colour is the first palette colour not yet used by another subject.
    public init(newIn timetable: Timetable, pack: PalettePackID, usedColors: [ColorValue], id: Subject.ID) {
        subjectID = id
        timetableID = timetable.id
        isNew = true
        let colors = (PalettePack.pack(pack) ?? .classic).colors
        let first = colors.first { color in !usedColors.contains(color.value) } ?? colors[0]
        let packID = (PalettePack.pack(pack) ?? .classic).id
        colorChoice = .palette(pack: packID, colorID: first.id)
        name = ""
        shortName = ""
        symbolKind = .none
        emoji = ""
        systemImage = Self.symbolSuggestions[0]
        defaultRoom = ""
        defaultBuilding = ""
        defaultTeacher = ""
        notes = ""
        base = Subject(id: id, meta: EditorEntities.placeholderMeta, timetableID: timetable.id, name: "", color: first.value)
    }

    /// The palette entry with exactly `color`, else a custom choice.
    public static func choice(for color: ColorValue) -> ColorChoice {
        for pack in PalettePack.all {
            if let match = pack.colors.first(where: { $0.value == color }) { return .palette(pack: pack.id, colorID: match.id) }
        }
        return .custom(color)
    }

    /// The chosen colour.
    public var color: ColorValue {
        switch colorChoice {
        case .custom(let value): return value
        case let .palette(pack, id): return PalettePack.pack(pack)?.color(id)?.value ?? base.color
        }
    }

    /// The tile colours exactly as every lesson view draws them.
    public var tileStyle: LessonTileStyle { LessonTileStyle(color: color) }

    /// The text colour used on the tile (WCAG black or white).
    public var tileTextColor: ColorValue { tileStyle.foreground }

    /// Contrast ratio between the tile text and the (opaque) tile colour.
    public var contrastRatio: Double { tileStyle.textContrast }

    /// `true` when `ratio` is below AA for normal text.
    public static func isLowContrast(_ ratio: Double) -> Bool { ratio < minimumContrast }

    /// `true` when even the best text colour is below AA for normal text. Black or white always reaches about
    /// 4.58:1 on an opaque colour, so this is a safety net that stays silent for every colour the pickers produce;
    /// the editor additionally tells when the tile blends into the page (`blendsIntoBackground`).
    public var hasLowContrast: Bool { Self.isLowContrast(contrastRatio) }

    /// `true` when the tile is almost the page colour in light or dark mode (it then gets an outline).
    public var blendsIntoBackground: Bool { tileStyle.needsOutlineInLight || tileStyle.needsOutlineInDark }

    /// The symbol to store.
    public var symbol: SubjectSymbol? {
        switch symbolKind {
        case .none: return nil
        case .emoji: return EditorText.firstCharacter(emoji).map { SubjectSymbol.emoji($0) }
        case .systemImage: return EditorText.trimmedOrNil(systemImage).map { SubjectSymbol.systemImage($0) }
        }
    }

    /// Problems that block saving.
    public var issues: [Issue] { EditorText.trimmedOrNil(name) == nil ? [.noName] : [] }

    /// `true` when nothing blocks saving.
    public var canSave: Bool { issues.isEmpty }

    /// The subject to store.
    public func makeSubject() -> Subject? {
        guard let trimmedName = EditorText.trimmedOrNil(name) else { return nil }
        var subject = base
        subject.name = trimmedName
        subject.shortName = EditorText.trimmedOrNil(shortName)
        subject.color = color
        switch colorChoice {
        case .palette(let pack, let id):
            if let entry = PalettePack.pack(pack)?.color(id) { subject.colorName = .key(entry.nameKey) }
        case .custom:
            // Keep a name the user wrote earlier; the palette-name key no longer describes a custom colour.
            if case .key? = base.colorName { subject.colorName = nil }
        }
        subject.symbol = symbol
        subject.defaultRoom = EditorText.trimmedOrNil(defaultRoom)
        subject.defaultBuilding = EditorText.trimmedOrNil(defaultBuilding)
        subject.defaultTeacher = EditorText.trimmedOrNil(defaultTeacher)
        subject.notes = EditorText.trimmedOrNil(notes)
        return subject
    }

    /// The summary the tile preview shows.
    public var summary: SubjectSummary? {
        makeSubject().map(SubjectSummary.init)
    }
}
