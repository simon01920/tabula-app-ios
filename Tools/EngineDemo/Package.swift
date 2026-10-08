// swift-tools-version: 6.0
// EngineDemo — runs the real TimetableCore engine on a fixed sample scenario and writes a self-contained HTML
// report for inspection. It is a developer tool, NOT the app's UI (that is Phase 2). Linux-runnable, no
// dependencies besides TimetableCore (by path). Run it with `bash scripts/engine-demo.sh`.
import PackageDescription

let package = Package(
    name: "EngineDemo",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: [
        .package(path: "../../Packages/TimetableCore"),
    ],
    targets: [
        .executableTarget(
            name: "EngineDemo",
            dependencies: [.product(name: "TimetableCore", package: "TimetableCore")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
