// swift-tools-version: 6.0
// Root SwiftPM package for the LOCAL xtool build path (see xtool.yml).
// xtool requires each app/extension to be an *automatic* library product of this root package;
// it generates a stub executable per product and links it (Sources/PackLib/Planner.swift + Packer.swift).
// The CI path (project.yml / XcodeGen) compiles the SAME source folders: App/Sources, WidgetExtension/Sources,
// and the same local packages. Keep both in sync; scripts/validate.sh checks the folder mapping.
import PackageDescription

// Macro isolation (CLAUDE.md rule 5): the default app build uses NO Swift macros, so one unsupported
// macro under xtool cannot block every device check. Setting TABULA_MACRO_PROBES=1 in the environment
// when the manifest is evaluated compiles the macro-probe variant (@Observable, @Entry, @State, @Generable).
// Used by `scripts/xtool-dev.sh --macro-probes`. The XcodeGen/CI path always defines it (project.yml).
let macroProbes = Context.environment["TABULA_MACRO_PROBES"] == "1"
let appSwiftSettings: [SwiftSetting] = macroProbes ? [.define("TABULA_MACRO_PROBES")] : []

let package = Package(
    name: "Tabula",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(name: "TabulaApp", targets: ["TabulaApp"]),
        .library(name: "TabulaWidgets", targets: ["TabulaWidgets"]),
    ],
    dependencies: [
        .package(path: "Packages/TimetableCore"),
        .package(path: "Packages/TimetableUI"),
    ],
    targets: [
        .target(
            name: "TabulaApp",
            dependencies: [
                .product(name: "TimetableCore", package: "TimetableCore"),
                .product(name: "TimetableUI", package: "TimetableUI"),
            ],
            path: "App/Sources",
            swiftSettings: appSwiftSettings
        ),
        .target(
            name: "TabulaWidgets",
            dependencies: [
                .product(name: "TimetableCore", package: "TimetableCore"),
                .product(name: "TimetableUI", package: "TimetableUI"),
            ],
            path: "WidgetExtension/Sources"
        ),
    ],
    swiftLanguageModes: [.v6]
)
