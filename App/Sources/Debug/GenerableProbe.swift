// Phase 0 FoundationModels macro probe. UNCOMPILED.
// Macro variant only (`#if TABULA_MACRO_PROBES`, see Package.swift / project.yml): the base app must build
// with zero macros (CLAUDE.md rule 5). xtool 1.20.1 ships FoundationModels macros via OpenAppleMacros
// (SDKBuilder.oamLibraries = FoundationModelsMacros, PreviewsMacros, SwiftUIMacros).
// If the macro variant builds and the debug row shows a schema, @Generable/@Guide expanded correctly.
// No model inference here (SystemLanguageModel availability is the import-ml agent's probe).
// APIs (docs checked): Generable(description:) iOS 26, Guide(description:) iOS 26,
//   Generable.generationSchema iOS 26.
#if TABULA_MACRO_PROBES
import FoundationModels

@Generable(description: "Phase 0 macro probe: one timetable slot")
struct Phase0GenerableSlot {
    @Guide(description: "Subject name exactly as printed on the timetable")
    var subject: String

    @Guide(description: "Lesson number within the day, starting at 1")
    var period: Int
}

enum GenerableProbe {
    static let isBuilt = true

    /// A short, human-readable dump of the macro-generated schema.
    static func schemaSummary(maxLength: Int = 240) -> String {
        let text = String(describing: Phase0GenerableSlot.generationSchema)
        return text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }
}
#else
enum GenerableProbe {
    static let isBuilt = false

    static func schemaSummary(maxLength: Int = 240) -> String {
        "not built (base variant; rebuild with scripts/xtool-dev.sh --macro-probes)"
    }
}
#endif
