// swift-tools-version: 6.2
// Phase 0 spike (import-ml-engineer): build llama.cpp *from source* as a SwiftPM C/C++ target and call
// its C API from Swift. Not an app dependency. Upstream sources are fetched by ../scripts/fetch-llama.sh
// (pinned tag) into Sources/CLlama/upstream and are never committed.
//
// tools-version 6.2: SwiftPM >= 6.2 no longer rejects unsafeFlags in dependency packages
// (PackageBuilder.swift: "unsafe flags check disabled in 6.2"), which the Apple-only -fno-objc-arc needs.
//
// IMPORTANT: Package.swift is evaluated on the *host*. Under xtool the host is Linux while the target is
// iOS, so `#if os(...)` here would be wrong. Platform selection is done with `.when(platforms:)` for
// settings and with preprocessor guards inside Sources/CLlama/shim/* for sources.
import PackageDescription

let up = "upstream"
let ggmlSrc = "\(up)/ggml/src"
let ggmlCPU = "\(ggmlSrc)/ggml-cpu"
let apple: [Platform] = [.iOS, .macOS]

let headerPaths = [
    "\(up)/include", "\(up)/ggml/include", "\(up)/ggml", ggmlSrc, ggmlCPU, "\(up)/src", "generated",
]

let commonDefines: [String] = [
    "GGML_USE_CPU", "GGML_USE_CPU_REPACK", "GGML_USE_LLAMAFILE",
]

func cDefines() -> [CSetting] {
    var s: [CSetting] = headerPaths.map { .headerSearchPath($0) }
    s += commonDefines.map { .define($0) }
    s += [
        .define("GGML_SCHED_MAX_COPIES", to: "4"),
        .define("NDEBUG", .when(configuration: .release)),
        .define("_GNU_SOURCE", .when(platforms: [.linux])),
        // Apple: CPU via Accelerate + Metal backend with the shader *source* embedded (no metal compiler).
        .define("GGML_USE_ACCELERATE", .when(platforms: apple)),
        .define("ACCELERATE_NEW_LAPACK", .when(platforms: apple)),
        .define("ACCELERATE_LAPACK_ILP64", .when(platforms: apple)),
        .define("GGML_USE_METAL", .when(platforms: apple)),
        .define("GGML_METAL_EMBED_LIBRARY", .when(platforms: apple)),
        .define("TABULA_LLAMA_METAL", .when(platforms: apple)),
        // ggml's Objective-C uses manual retain/release; SwiftPM adds -fobjc-arc on Darwin.
        .unsafeFlags(["-fno-objc-arc"], .when(platforms: apple)),
    ]
    return s
}

func cxxDefines() -> [CXXSetting] {
    var s: [CXXSetting] = headerPaths.map { .headerSearchPath($0) }
    s += commonDefines.map { .define($0) }
    s += [
        .define("GGML_SCHED_MAX_COPIES", to: "4"),
        .define("NDEBUG", .when(configuration: .release)),
        .define("_GNU_SOURCE", .when(platforms: [.linux])),
        .define("GGML_USE_ACCELERATE", .when(platforms: apple)),
        .define("ACCELERATE_NEW_LAPACK", .when(platforms: apple)),
        .define("ACCELERATE_LAPACK_ILP64", .when(platforms: apple)),
        .define("GGML_USE_METAL", .when(platforms: apple)),
        .define("GGML_METAL_EMBED_LIBRARY", .when(platforms: apple)),
        .define("TABULA_LLAMA_METAL", .when(platforms: apple)),
    ]
    return s
}

let package = Package(
    name: "LlamaSpike",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "CLlama", targets: ["CLlama"]),
        .executable(name: "llama-probe", targets: ["llama-probe"]),
    ],
    targets: [
        .target(
            name: "CLlama",
            path: "Sources/CLlama",
            exclude: [
                "UPSTREAM_PIN",
                // Metal kernels are embedded as text by generated/ggml-metal-embed.S; SwiftPM must never see
                // them as .metal resources (that would require Xcode's metal compiler).
                "generated/metal",
                "\(ggmlSrc)/ggml-metal/kernels",
                "\(up)/models",
                "\(up)/LICENSE",
                // compiled via shim/models_clef.cpp (upstream missing #include <algorithm>, masked by unity builds)
                "\(up)/src/models/clef.cpp",
            ],
            sources: [
                // libllama
                "\(up)/src",
                // ggml-base + backend registry
                "\(ggmlSrc)/ggml.c", "\(ggmlSrc)/ggml.cpp", "\(ggmlSrc)/ggml-alloc.c",
                "\(ggmlSrc)/ggml-backend.cpp", "\(ggmlSrc)/ggml-backend-meta.cpp", "\(ggmlSrc)/ggml-opt.cpp",
                "\(ggmlSrc)/ggml-threading.cpp", "\(ggmlSrc)/ggml-quants.c", "\(ggmlSrc)/gguf.cpp",
                "\(ggmlSrc)/ggml-backend-reg.cpp", "\(ggmlSrc)/ggml-backend-dl.cpp",
                // ggml-cpu (arch-independent part; same list as upstream CMake)
                "\(ggmlCPU)/ggml-cpu.c", "\(ggmlCPU)/ggml-cpu.cpp", "\(ggmlCPU)/repack.cpp", "\(ggmlCPU)/hbm.cpp",
                "\(ggmlCPU)/quants.c", "\(ggmlCPU)/traits.cpp", "\(ggmlCPU)/binary-ops.cpp",
                "\(ggmlCPU)/unary-ops.cpp", "\(ggmlCPU)/vec.cpp", "\(ggmlCPU)/ops.cpp",
                "\(ggmlCPU)/amx", "\(ggmlCPU)/tiled", "\(ggmlCPU)/llamafile",
                // per-arch CPU kernels + Metal backend, selected by preprocessor guards (see comments in shim/*)
                "shim",
                // embedded Metal shader source (Apple only; empty translation unit elsewhere)
                "generated/ggml-metal-embed.S",
            ],
            publicHeadersPath: "include",
            cSettings: cDefines(),
            cxxSettings: cxxDefines(),
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedFramework("Foundation", .when(platforms: apple)),
                .linkedFramework("Metal", .when(platforms: apple)),
                .linkedFramework("MetalKit", .when(platforms: apple)),
                .linkedFramework("Accelerate", .when(platforms: apple)),
            ]
        ),
        .executableTarget(
            name: "llama-probe",
            dependencies: ["CLlama"],
            path: "Sources/llama-probe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .cxx17
)
