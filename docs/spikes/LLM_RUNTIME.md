# Spike: on-device LLM runtime feasibility (llama.cpp vs MLX Swift) + Apple OCR/LLM APIs

**Phase 0 · import-ml-engineer · 2026-10-04 · status: runtime feasibility only** (no eval harness, no parser, no model selection, no weights downloaded)

Host: Windows 11 + WSL2 Ubuntu 26.04 x86_64, 16 threads, 15 GB, Swift 6.4 (swift-6.4-RELEASE). **No iOS SDK on this host yet**, so every iOS claim below is either *verified by source/docs* or explicitly **UNVERIFIED**. Spike code: [`spikes/llm-runtime/`](../../spikes/llm-runtime/README.md). On-device probe: `App/Sources/Debug/ImportProbes.swift` (**UNCOMPILED**).

## TL;DR

| Question | Verdict | Confidence |
|---|---|---|
| llama.cpp consumable from Swift today? | Yes. Official route = **prebuilt `llama-bNNNNN-xcframework.zip`** release asset as a SwiftPM `binaryTarget` (no `Package.swift` in the repo since 2025-03-05). | Verified (repo, release assets, SwiftPM resolve on Linux) |
| XCFramework binaryTarget when cross-compiling iOS from Linux? | **Should work**: slice selection is keyed to the *target* triple, not the host. Swift Build has no host guard, and its codesign check is a no-op off macOS. xtool explicitly embeds dynamic binary-target frameworks. | Verified by source reading. **End-to-end UNVERIFIED** (no SDK) |
| llama.cpp from source as SwiftPM target, Metal w/o Metal compiler? | **Yes on Linux CPU (built and ran, 50 s).** Metal works without `metal`: `GGML_METAL_EMBED_LIBRARY` embeds shader *source* and compiles it at runtime with `newLibraryWithSource`. The official iOS XCFramework already ships it this way. | CPU verified. Metal-from-source on iOS **UNVERIFIED** |
| Grammar-constrained generation in llama.cpp C API? | **Yes**: `llama_sampler_init_grammar` (GBNF) + lazy variants. Proven from Swift via a model-free walk that produced valid JSON. JSON-Schema→GBNF is C++ in `common/`, **not** in the C API or XCFramework. | Verified |
| MLX Swift under xtool/Linux? | **No (as source)**: 10 `.metal` kernels must become `default.metallib` at build time, and SwiftPM on Linux cannot find a Metal toolchain. Prebuilt XCFrameworks with metallib exist (0.32.3), but the LLM layer (`mlx-swift-lm`) is source-only against them. | Verified by README/source. Prebuilt route UNVERIFIED |
| MLX Swift under XcodeGen/macOS CI? | Yes (xcodebuild compiles the shaders). | Per upstream README |
| Licences | llama.cpp **MIT**, ggml **MIT**, mlx-swift **MIT**, mlx **MIT**, mlx-c **MIT**, mlx-swift-lm **MIT** | Verified (LICENSE files + GitHub API) |

**Recommendation:** Tier B runtime = **llama.cpp**, consumed as the official XCFramework `binaryTarget`. Pin a `bNNNNN` build with checksum, and make the dependency platform-conditional so Linux `swift test` stays green.

- **Fallback:** this spike's from-source SwiftPM target, which also gives Linux CI the *same C API* for golden tests.
- **Rejected:** MLX Swift as primary. It needs Xcode's Metal compiler or an awkward prebuilt-binary rewiring.
- **Future option:** Apple **Core AI + `LanguageModel`** (iOS 27+ only). Using it would require changing the minimum OS, which needs the human's approval.

---

## 1. llama.cpp

### 1.1 How Swift consumes it today (Oct 2026)

- **No `Package.swift` in the repo.** Last commit touching it: `a057897ad4` (2025-03-05, *"llama : add xcframework build script (#11996)"*), which removed it (GitHub API `commits?path=Package.swift`).
- **Official route = prebuilt XCFramework release asset.** See [`docs/xcframework.md`](https://github.com/ggml-org/llama.cpp/blob/b11382/docs/xcframework.md), which shows `.binaryTarget(name:url:checksum:)`. Every `bNNNNN` build publishes `llama-bNNNNN-xcframework.zip` ([releases](https://github.com/ggml-org/llama.cpp/releases)). These builds are marked *prerelease* and arrive about 5 per day.
- Separate semver releases now exist too (`v0.5.0`, 2026-09-23, not prerelease) but carry **no** XCFramework asset. Policy: pin the `bNNNNN` build at/after a semver release.
- **Pinned for this spike:** `b11382` = commit `11fe02151f79c41d0d4af7da708755d73b9c0da6` (2026-10-04). Versions: `LLAMA_VERSION 0.5.0-dev`, `GGML_VERSION 0.25.3`.
- **XCFramework contents (b11382)**, downloaded and inspected (library artefact, not weights):
  - zip 61.8 MB, sha256 `0de3e92dde4099208710b9ce03960bdc6a2adbe21dcf0a3d1b190e44efc512ab` (identical to `swift package compute-checksum`).
  - Slices: **`ios-arm64`** and `macos-arm64_x86_64` only. No simulator, tvOS or visionOS slices in this build; irrelevant for us, since we have no Simulator.
  - `ios-arm64/llama.framework/llama`: *Mach-O 64-bit arm64 dynamically linked shared library*, **11.35 MB**, `MinimumOSVersion 16.4`, dSYM shipped separately.
  - Module map: `framework module llama { umbrella "Headers"; link "c++"; link framework "Accelerate"; link framework "Metal"; link framework "Foundation" }`.
  - Headers include `llama.h`, `ggml*.h`, `gguf.h` **and `mtmd.h`/`mtmd-helper.h`**. The multimodal library is included, which means a future image-input VLM route exists.
  - **Metal is embedded as source, not metallib.**
    - `grep -c "kernel void"` → 164. Strings `#include <metal_stdlib>`, `__ggml_metallib`, `newLibraryWithSource:options:error:`. No `MTLLB` metallib magic.
    - Exports `_llama_sampler_init_grammar`, `_llama_sampler_init_grammar_lazy_patterns`.

### 1.2 SwiftPM XCFramework binaryTarget when cross-compiling iOS from Linux

Evidence (SwiftPM `release/6.4.x` @ `34946f99`, swift-build `main` @ `b0458a1a`, xtool `1.20.1` @ `916cdffb`):

- **SwiftPM native build system.**
  - `BuildPlan.parseXCFramework(for:triple:enableXCFrameworksOnLinux:)` only returns early for `triple.os == .linux`, i.e. when the *target* is Linux. The host does not matter.
  - Slice selection is `BinaryModule.parseXCFrameworks(for: triple)`. It matches `platform == "ios"`, variant `nil` and arch `arm64` (`Sources/SPMBuildCore/BinaryTarget+Extensions.swift`).
  - Artifact discovery recurses into subdirectories (`Workspace+BinaryArtifacts.swift`). The asset's nested `build-apple/llama.xcframework` layout is therefore found.
- **Swift Build** (SwiftPM 6.4's **default** build system: `Options.swift` `_buildSystem = .swiftbuild`).
  - `ProcessXCFrameworkTaskAction` has no host-OS guard. It even documents Linux slices.
  - Signature verification `CodeSignatureInfo.invokeCodesignVerification` is `#if os(macOS)` only (`Sources/SWBUtil/Signatures.swift`). Off macOS it is a no-op, and unsigned frameworks are allowed (`treatUnsignedAsError: false`).
- **xtool 1.20.1**
  - It uses `--build-system swiftbuild` whenever Swift ≥ 6.4 (`Sources/PackLib/BuildSettings.swift`, `BuildSystem.default()`), with `--triple arm64-apple-ios… --toolset toolset-swb.json`.
  - `Planner.swift` maps `moduleType == "BinaryTarget"` to `.binaryTarget(name:)`.
  - `Packer.swift` copies a **dynamic** `<name>.framework` into `Frameworks/` and signs it; static archives are skipped.
- **Linux experiment (run).** A package with the real `binaryTarget(url:…b11382…zip, checksum:)` behaves as follows:
  - `swift package resolve` downloads and verifies the zip in 7.2 s and extracts `.build/artifacts/xcf-consumer/llama/llama.xcframework`.
  - An executable with `.target(name: "llama", condition: .when(platforms: [.iOS, .macOS]))` **builds on Linux** (3.7 s) and prints `canImport(llama) == false`. This is the dual-path pattern the app needs.
- **Verdict:** nothing found that makes XCFramework binary targets Apple-host-only. **UNVERIFIED end-to-end** until the Xcode 27 SDK is installed for xtool. See §6 for the check.

### 1.3 From source as a SwiftPM C/C++ target (built + run on Linux)

Layout choice: a **C/C++ SwiftPM target compiling upstream sources directly**. I did not use a system-library target wrapping CMake output, because a CMake-built lib only proves "Linux links", while the from-source target proves the source layout works with SwiftPM itself. That is what xtool needs if the binaryTarget route fails. It also gives Linux CI the identical C API. The upstream tree is fetched by `scripts/fetch-llama.sh` at the pinned tag. It is never vendored.

**CMake baseline (CPU)**, `/root/spikes/llama`:

```
git clone --depth 1 --branch b11382 https://github.com/ggml-org/llama.cpp llama          # 4.3 s
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF   # 7.6 s
cmake --build build -j16                                                               # 122.1 s, 320 targets, maxrss 716 MB
./build/bin/llama-cli --version   ->  version: 0.5.0-dev (build 1, commit 11fe021) / built with GNU 15.2.0 for Linux x86_64
```

Libraries: `libllama.a` 9.7 MB, `libggml-base.a` 1.4 MB, `libggml-cpu.a` 1.9 MB, all unstripped x86_64.

Failed assumption, now logged: adding `-DLLAMA_BUILD_SERVER=OFF` breaks the link of the new unified `bin/llama` (`cannot find -lllama-server-impl`). Libraries built fine. Only that tool's option interaction fails.

**SwiftPM spike** (`spikes/llm-runtime/scripts/run-spike.sh`). Exact output is in the spike README.

| Step | Result |
|---|---|
| sparse fetch: 248 C/C++/ObjC files + 34 Metal kernel sources → `ggml-metal-embed.S` | 3.4 s |
| `swift build -c release` (swiftbuild, clean) | **Build complete! (50.19 secs)**, 0 warnings |
| `--build-system native` (clean) | 56.9 s (`native` is deprecated in 6.4) |
| `-c debug` (swiftbuild, clean) | 50.8 s |
| binary | 42.1 MB unstripped, **3.73 MB stripped** (libllama+ggml CPU, x86_64) |
| `llama_backend_init()` | ok, 2.7 ms |
| `llama_print_system_info()` | `CPU : LLAMAFILE = 1 \| REPACK = 1 \|` (portable build, no `-mavx2`) |
| devices | `[0] CPU \| AMD Ryzen 7 3700X 8-Core Processor` |
| vocab-only GGUF load (`models/ggml-vocab-qwen2.gguf`, tokenizer data, 0 tensors) | n_tokens = 151 936, 0.38 s |
| malformed GBNF | rejected (`llama_sampler_init_grammar` → NULL, `parse: error parsing grammar: expecting ')'`) |
| constrained walk under a timetable-cell GBNF (full-vocab mask per step) | 33 tokens, EOG reached, 0.88 s → `{"day":"wed","period":2,"subject":", analys Safari还款註冊틋","room":":{"}` → **JSONSerialization accepts: true** |

Changes required compared with CMake:

1. **Per-arch CPU kernel selection.** SwiftPM has no per-arch sources, so `shim/cpu_arch_{quants.c,repack.cpp}` `#include` the x86 or arm file.
2. **Upstream bug.** `src/models/clef.cpp` lacks `#include <algorithm>`. Upstream's CMake *unity* build of `src/models/*.cpp` hides this, but per-file compilation fails with `no member named 'find' in namespace 'std'`. The spike works around it with `shim/models_clef.cpp`. This is exactly the kind of silent breakage the from-source path will hit on version bumps.
3. **Metal from source without the Metal compiler** (wired, Apple-only, **UNVERIFIED**).
   - `GGML_METAL_EMBED_LIBRARY` (CMake default `ON` with Metal) concatenates each kernel source and emits `.incbin` assembly with `_ggml_metallib_<kind>_start/_end` symbols (`ggml/src/ggml-metal/CMakeLists.txt`).
   - At init, `ggml-metal-device.m` calls `ggml_metal_library_compile_all(...)`, which uses `newLibraryWithSource`.
   - `fetch-llama.sh` reproduces the `.incbin` step into `generated/ggml-metal-embed.S`. The kind list is read from the `GGML_METAL_LIBS` X-macro in `ggml-metal-device.m`.
   - The Objective-C sources use manual retain/release (28 explicit `release` calls), so they need `-fno-objc-arc`. SwiftPM adds `-fobjc-arc` on Darwin (`ClangModuleBuildDescription.swift:307`).
   - `unsafeFlags` are allowed in dependency packages for tools-version ≥ 6.2 (`PackageBuilder.swift`: *"unsafe flags check disabled in 6.2"*).
   - `.metal` files **must be excluded**. Otherwise SwiftPM auto-treats them as resources (`TargetSourcesBuilder` metal rule = `processResource`), and Swift Build adds them to the compile phase, which needs `metal`.
   - Cost to measure on device: **runtime shader compile at first init** (34 kernel libraries, 4.9 MB of source).
4. **Manifest is evaluated on the host.** Under xtool, `#if os(Linux)` in `Package.swift` would be *true* while building for iOS. Platform selection must use `.when(platforms:)` and preprocessor guards (done).

### 1.4 Structured output

- **C API:** `llama_sampler_init_grammar(vocab, grammar_str, root)` (GBNF), `llama_sampler_init_grammar_lazy_patterns(...)` (`include/llama.h` L1521–1547).
- **JSON Schema → GBNF** lives in `common/json-schema-to-grammar.cpp` (C++, depends on vendored nlohmann/json, MIT). It is **not** part of the C API or the XCFramework.
- **Plan for Phase 9:**
  - Hand-write the GBNF, or generate it once offline from our JSON Schema with upstream's converter.
  - Ship the grammar as a string in TimetableCore.
  - Golden-test it on Linux with the from-source package, which can run real constrained decoding once a model is chosen.
  - Validate the decoded JSON again in Swift. The grammar gives shape, not truth.

## 2. MLX Swift (`ml-explore/mlx-swift` 0.32.3, 2026-09-30)

- [README](https://github.com/ml-explore/mlx-swift/blob/0.32.3/README.md):
  - Verbatim: *"SwiftPM (command line) cannot build the Metal shaders so the ultimate build has to be done via Xcode."*
  - Verbatim: *"Although `SwiftPM` (command line) cannot build the Metal shaders, `xcodebuild` can"*.
- `Package.swift` (tools 6.3) on Apple platforms:
  - Compiles `Source/Cmlx/mlx-generated/metal/*.metal` (**10 kernels**: arg_reduce, conv, dot, layer_norm, random, rms_norm, rope, scaled_dot_product_attention, searchsorted, steel_attention) into `default.metallib` (`.define("METAL_PATH", to: "\"default.metallib\"")`, `SWIFTPM_BUNDLE "mlx-swift_Cmlx"`).
  - Everything else is JIT (`jit_kernels.cpp`, with `nojit_kernels.cpp` excluded).
  - A metallib is still mandatory.
- **Why it fails under SwiftPM on Linux:**
  - SwiftPM finds the Metal toolchain only via `/usr/bin/xcrun --find metal` for Darwin triples (`UserToolchain.deriveMetalToolchainPath`), which does not exist on Linux.
  - xtool's SDK extraction copies toolchain `usr/lib/{swift,swift_static,clang}` and platform SDKs only, with no Metal toolchain (`SDKBuilder.swift` `wanted`).
  - **Verdict (a) xtool/Linux: not buildable as source with working GPU.**
- **Prebuilt route (exists, not adopted):**
  - The 0.32.3 release assets ship `Cmlx/MLX/MLXNN/MLXOptimizers/cLogSupport.xcframework.zip`. I listed them via HTTP Range without downloading the full 213 MB.
  - `ios-arm64/Cmlx.framework` = 20.3 MB binary + **`default.metallib` 2.35 MB**. `MLX.framework` 1.06 MB with `arm64-apple-ios.swiftinterface`. `MLXNN` 0.57 MB.
  - **Blockers:**
    - The LLM layer `mlx-swift-lm` (MIT) depends on `mlx-swift` **by source URL**, so it would need a fork rewired to binary targets.
    - `mlx-swift-lm` uses Swift macros (swift-syntax 602–604). Macros under xtool are unverified (env-ci spike).
    - `MLX.framework` contains a **nested** `Frameworks/cLogSupport.framework`. Nested frameworks inside an iOS framework are a known App Store validation risk (UNVERIFIED for our case).
- **Verdict (b) XcodeGen/macOS CI:** builds (xcodebuild compiles the shaders), but local xtool iteration would be impossible, which violates "two build paths must stay in sync".
- **Structured output:** no built-in grammar decoding. `mlx-swift-lm` exposes a `LogitProcessor` hook (`GenerationComponents`), and its doc comment shows `GrammarProcessor(grammar:)` only as an example. We would have to write the JSON grammar masker ourselves.
- I did **not** run `swift build` of mlx-swift on Linux. The Linux path excludes all Metal sources and needs openblas/lapack/gfortran, so it cannot inform the iOS verdict.

## 3. Decision matrix

| Criterion | llama.cpp (XCFramework binaryTarget) | llama.cpp (from source, this spike) | MLX Swift |
|---|---|---|---|
| Builds under xtool/Linux | Expected yes: SwiftPM + Swift Build are triple-based and xtool embeds dynamic binary frameworks (UNVERIFIED e2e) | CPU yes on Linux (built). iOS UNVERIFIED (ObjC/Metal shims, libc++ headers in xtool SDK) | **No** as source (no Metal compiler). Prebuilt xcframeworks need a forked LLM layer |
| Builds under XcodeGen/CI | Yes (standard binaryTarget) | Expected yes (same SwiftPM target) | Yes |
| Metal acceleration | Yes, embedded shader *source* compiled at runtime (verified in binary) | Same mechanism, wired (UNVERIFIED) | Yes (prebuilt metallib) |
| Structured output | GBNF grammar sampler in C API (verified from Swift) | Same | None built in. Custom `LogitProcessor` |
| Licence | MIT | MIT | MIT (mlx-swift, mlx, mlx-c, mlx-swift-lm) |
| Binary size impact | +11.35 MB dynamic framework (arm64, incl. mtmd + Metal source), dSYM separate | Likely smaller (CPU-only code is 3.7 MB stripped on x86_64; +Metal ~5 MB source) | Cmlx 20.3 MB + metallib 2.35 MB + MLX 1.06 + MLXNN 0.57 MB + LLM layer + swift-syntax macro build cost |
| Maintenance | Very active (about 5 builds/day). Pin + checksum. Semver tags since v0.5.0 | We absorb upstream breakage (e.g. clef.cpp) on every bump | Active (Apple). Monthly-ish releases |
| Linux testability | Pure-Swift parts only (`canImport(llama)` false) | **Same C API on Linux** → real decoding tests in CI (Phase 9) | Linux CPU build exists, but different deps, no Metal |
| Model format | GGUF (broad availability of Qwen3/Phi-4-mini/Gemma 3/Llama 3.2 quantisations) | GGUF | MLX safetensors (mlx-community) |

**Recommendation:**

1. **Dependency.** Use llama.cpp as the Tier B runtime, consumed as `binaryTarget(url: …llama-bNNNNN-xcframework.zip, checksum: …)`.
2. **Package wiring.**
   - Link it only from a thin Apple-only adapter target (e.g. `LocalLLMRuntime`) through `.when(platforms: [.iOS])`.
   - TimetableCore owns the protocol (`LLMNormaliser`), prompt builder, GBNF strings and output validator. All of that is pure Swift and Linux-tested.
3. **Fallback.** Keep the from-source package from this spike in case xtool's swiftbuild path cannot handle the binary target. Optionally use it as a Linux-only test dependency for Phase 9 decoding goldens.
4. **Approval needed.** Per CLAUDE.md, adding the dependency needs the human's go-ahead at the Phase 0 gate. Justification: the only MIT runtime that builds under both paths and has grammar-constrained decoding.

**Alternative to put to the human (not recommended now):** iOS 27's **Core AI** plus the Foundation Models **`LanguageModel`** protocol.

- [Core AI](https://developer.apple.com/documentation/coreai) is iOS 27.0+. [`LanguageModel`](https://developer.apple.com/documentation/foundationmodels/languagemodel) is iOS 27.0+.
- [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session) says *"requires macOS 27, iOS 27, and Xcode 27"*.
- It would give `@Generable` guided generation on open models, but needs **min OS 27** (an "ask the human" item) and a per-platform model export toolchain (UNVERIFIED on Linux).

## 4. Apple Foundation Models (verified 2026-10-04)

Sources: [`SystemLanguageModel`](https://developer.apple.com/tutorials/data/documentation/foundationmodels/systemlanguagemodel.json) and child symbols (`…/availability-swift.enum/unavailablereason.json`, `…/supportedlanguages.json`, `…/supportslocale(_:).json`, `…/isavailable.json`, `…/contextsize.json`).

- **Core API (iOS 26.0+):**
  - `SystemLanguageModel.default` (`static var default: SystemLanguageModel`).
  - `availability: SystemLanguageModel.Availability` (`@frozen enum`: `.available`, `.unavailable(UnavailableReason)`).
  - `UnavailableReason` (**not frozen** → `@unknown default`): `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`.
  - `isAvailable: Bool`, `supportedLanguages: Set<Locale.Language>`.
  - **`supportsLocale(_ locale: Locale = Locale.current) -> Bool`**. Apple: use it over `supportedLanguages` because it applies language fallbacks.
  - `contextSize: Int` (`@backDeployed(before: iOS 26.4)`).
  - Guided generation: `@Generable`, `@Guide`, `GenerationSchema`, `DynamicGenerationSchema` ([framework page](https://developer.apple.com/tutorials/data/documentation/foundationmodels.json)).
- **Model versions:** 3 so far, for 26.0–26.3, 26.4 and 27.0. Prompts must be re-tested per version.
- **iOS 27 additions** ([updates](https://developer.apple.com/tutorials/data/documentation/updates/foundationmodels.json), June 2026):
  - **Image input:** [`Attachment`](https://developer.apple.com/tutorials/data/documentation/foundationmodels/attachment.json) / `ImageAttachmentContent` are **iOS 27.0+**. Apple's guide is *"Prompt an on-device model with images"* ([article](https://developer.apple.com/tutorials/data/documentation/foundationmodels/analyzing-images-with-multimodal-prompting.json)).
  - Vision tools for the model (`OCRTool`, `BarcodeReaderTool`), `PrivateCloudComputeLanguageModel`, the `LanguageModel` protocol (custom/Core AI models), and a new on-device model.
  - All of these must be `if #available(iOS 27, *)`. The probe only reports availability.
- **Languages** ([Apple support 121115](https://support.apple.com/en-us/121115), iOS 27): English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified), Chinese (traditional), Japanese, Korean.
  - Of our 12, **supported: en, de, fr, ja, zh-Hans/zh-Hant**.
  - **Not supported: sk, cs, pl, hu, ro, sr, uk.**
  - Devices: iPhone 15 Pro/Pro Max, iPhone 16 and later. Our iPhone 16 Pro Max is eligible.
  - **Tier A stays a bonus**, as the spec says.

## 5. Apple Vision `RecognizeDocumentsRequest` (verified 2026-10-04)

Sources: [`RecognizeDocumentsRequest`](https://developer.apple.com/tutorials/data/documentation/vision/recognizedocumentsrequest.json) (iOS 26.0+, `struct`, `ImageProcessingRequest`) and child JSONs below. Also [WWDC25 session 272](https://developer.apple.com/videos/play/wwdc2025/272/).

- **Creating and running the request:**
  - Creation: `init(_ revision: RecognizeDocumentsRequest.Revision? = nil)`. Only `.revision1` exists, even in the iOS 27 docs.
  - Execution: `perform(on: Data | CGImage | URL | CVPixelBuffer | CMSampleBuffer | CIImage, orientation: CGImagePropertyOrientation?) async throws -> Result`. The result is `[DocumentObservation]`.
- **Result structure:**
  - `DocumentObservation.confidence: Float` (0–1) and `.document: DocumentObservation.Container`.
  - `Container` has `.tables: [Container.Table]`, `.lists`, `.paragraphs`, `.text: Container.Text`, `.title`, `.barcodes`.
  - `Table` has `.rows: [[Table.Cell]]`, `.columns: [[Table.Cell]]`, `cell(row:col:) -> Cell?` and `.boundingRegion`.
  - `Cell` has **`.rowRange: ClosedRange<Int>`**, `.columnRange` (merged cells) and `.content: Container`. The content is recursive, so it can contain text, tables, lists and barcodes.
  - `Container.Text` has `.transcript: String`, `.lines: [RecognizedTextObservation]`, `.words`, `.detectedData`.
  - **Per-cell confidence** is not a cell property. Derive it from `lines[i].topCandidates(n) -> [RecognizedText]`, each with `.confidence: Float`. The probe uses the min over lines.
- **Languages:**
  - `RecognizeDocumentsRequest.supportedRecognitionLanguages: [Locale.Language]` is an **instance** property on the request. `RecognizeTextRequest` has its own (iOS 18+).
  - WWDC25 says document recognition supports **26 languages** but does not list them. The runtime list is the only source → probe (a).
  - Historical context: a published iOS 16 `VNRecognizeTextRequest` list was en, fr, it, de, es, pt, zh-Hans, zh-Hant, yue, ko, ja, ru, uk, with no cs/pl/sk/hu/ro/sr ([zenn.dev write-up](https://zenn.dev/_ds_store/articles/0bb40f96eca3e7); see also [Apple forum 121048](https://developer.apple.com/forums/thread/121048)). Measurement is essential.
- **Options** (`TextRecognitionOptions`):
  - `recognitionLanguages: [Locale.Language]` (priority order), `automaticallyDetectLanguage: Bool`.
  - `useLanguageCorrection: Bool` (false = raw, faster, less accurate).
  - **`customWords: [String]`**, which takes precedence over the lexicon and is ignored when `useLanguageCorrection == false`. Useful to feed subject names/abbreviations from the user's existing timetable.
  - `maximumCandidateCount`, `minimumTextHeightFraction`.

## 6. Memory

- [`com.apple.developer.kernel.increased-memory-limit`](https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit.json) (iOS 15+) tells the system core features *"may perform better by exceeding the default app memory limit on supported devices"*. It is *"only available on some device models"*: call `os_proc_available_memory()`, and the app must behave correctly without it.
- **Account requirement.** Apple's [capabilities-by-membership table](https://developer.apple.com/help/account/reference/supported-capabilities-ios) (parsed 2026-10-04) lists *Increased Debugging Memory Limit* for ADP/ADEP but **not** for the free tier. It has no row named "Increased Memory Limit". Treat this as **paid ADP + App ID capability**, and the human must verify it in the portal.
- **xtool risk (verified in source).**
  - `DeveloperServicesAddAppOperation.swift` syncs App ID capabilities to the entitlements it knows, and **deletes capabilities it does not map**. Its capability list has no memory-limit entry.
  - Under xtool the entitlement therefore probably cannot be provisioned without patching xtool, and manually enabling the capability in the portal would be undone. CI/Xcode signing is unaffected.
- [`os_proc_available_memory()`](https://developer.apple.com/tutorials/data/documentation/os/os_proc_available_memory.json) (iOS 13+) returns bytes before hitting the limit (limit − footprint), and 0 if already over. It is advisory, so don't cache it. The probe shows it.

## 7. On-device probe (`App/Sources/Debug/ImportProbes.swift`, UNCOMPILED)

`struct ImportProbesSection: View` (a group of `Section`s for the debug `List`). Swift 6 strict concurrency; helpers are `nonisolated` and work runs in `@concurrent` functions. iOS 26.0 minimum; iOS 27 is only touched via `#available`. All text uses `Text(verbatim:)` (debug only, nothing extracted to String Catalogs). It needs no other app files.

- **(a)** Vision `supportedRecognitionLanguages` for documents and text, flags for en sk cs pl hu ro de fr uk sr-Latn sr-Cyrl ja zh-Hans zh-Hant, and full lists.
- **(b)** PhotosPicker → `RecognizeDocumentsRequest` (default options), showing:
  - elapsed ms and image px/bytes
  - observations, tables, first table rows × cols, paragraphs
  - first 20 cells with row/col ranges, transcript and min line confidence
- **(c)** `SystemLanguageModel.default`: availability + reason, `isAvailable`, `supportsLocale(.current)` and each of our 14 locale tags, `supportedLanguages`, and an iOS 27 image-prompt availability note.
- **(d)** `os_proc_available_memory()` and `physicalMemory`.
- **Export:** a "Share probe report" `ShareLink` exports everything as plain text for the gate report.
- `swiftc -parse -swift-version 6` passes on Linux (syntax only; no type-check without an SDK).
- **Info.plist keys: none required.** PhotosPicker runs out of process and needs no Photos authorization. [PhotoKit privacy article](https://developer.apple.com/tutorials/data/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app.json): *"The user doesn't need to explicitly authorize your app to select photos"*. Vision and Foundation Models need no usage strings. Add `NSPhotoLibraryUsageDescription` only if we ever use `PHPhotoLibrary` directly.

## 8. What remains unverified, and how to verify it once the SDK and device exist

1. **xtool + binaryTarget e2e.**
   - Add the XCFramework dependency (gated as above) and a debug row that calls `llama_backend_init()` + `llama_print_system_info()` and lists ggml devices. No weights are needed.
   - Expect a `MTL`/Metal device besides CPU.
   - Run `xtool dev`, confirm `Frameworks/llama.framework` is embedded and signed, and launch on the iPhone 16 Pro Max.
   - Repeat via XcodeGen CI.
2. **Runtime Metal shader compile cost.** Time the first `ggml_backend` Metal init (`ggml_metal_library_compile_all`) and check whether it is cached across launches. If it is slow, initialise lazily on the import screen, never at app launch.
3. **From-source fallback on iOS** (only if 1 fails):
   - `swift build` via xtool of `spikes/llm-runtime` for `arm64-apple-ios`.
   - Watch for ObjC shims with `-fno-objc-arc`, libc++ headers in the xtool-extracted SDK, `-fmodules` with C++ on Darwin, and `.S` handling under Swift Build.
4. **Memory.**
   - Record `os_proc_available_memory()` at idle and during import (probe d).
   - Compare with and without the entitlement on the CI-signed build.
   - In Phase 9, measure whether mmapped GGUF weights count toward the footprint.
5. **OCR languages, Foundation Models availability and languages.** Run the probe on the device; the human pastes the report.
6. **Performance** (tokens/s, latency per timetable, peak memory). Phase 9, with real weights after model selection.

## 9. Things in `docs/specs/AI_IMPORT.md` that are wrong or impractical

1. **`SystemLanguageModel.isSupported` does not exist.**
   - Use `availability`/`isAvailable` for device/AI state and `supportsLocale(_:)` (preferred) or `supportedLanguages` for language.
   - Also: `UnavailableReason` is non-frozen and needs `@unknown default`.
2. **"Image understanding arriving in a newer OS release" has arrived.** `Attachment` is iOS 27.0+ and on-device. It is still not usable as primary: languages (§4), device eligibility, and our iOS 26 minimum.
3. **Ukrainian is also unsupported** by Apple Intelligence. The spec lists pl/cs/hu/ro (+sk); add uk and sr. Of our 12, only en/de/fr/ja/zh are covered.
4. **"Output = JSON constrained by grammar/schema".**
   - llama.cpp gives GBNF in the C API. Schema→grammar conversion is C++ in `common/` and not shipped in the XCFramework.
   - Plan for an offline-generated/hand-written GBNF plus a Swift-side validator.
   - With MLX there is no constrained decoding at all.
5. **Memory budget "≲ 2 GB" vs model size "≲ 2.5 GB" conflict.** A 4-bit 4B model (~2.3–2.6 GB GGUF) plus KV cache will not fit 2 GB unless mmapped weights don't count toward the jetsam footprint (UNVERIFIED). Realistically Qwen3-1.7B-class models fit, and 4B models need the increased-memory entitlement, which xtool cannot provision today (§6).
6. **"Pick runtime by spike (… memory, speed …)" cannot happen in Phase 0.** Memory and speed need SDK + device + weights. Phase 0 can only decide build feasibility and structured output, and that decision is llama.cpp.
7. **OCR coverage is the bigger risk.** If Vision lacks cs/pl/sk/hu/ro/sr, no LLM can restore diacritics it never saw: it must not invent, and copies verbatim. Phase 9 should budget for a decision (accept, `customWords`, or a second OCR engine) once probe (a) results exist.

## 10. Suggested additions to `docs/RISKS.md` (owner: orchestrator)

- **xtool deletes App ID capabilities it doesn't map.** The increased-memory-limit entitlement is not provisionable via xtool 1.20.1. Mitigation: CI-signed builds for memory tests, or upstream an xtool patch.
- **Runtime Metal shader compile on first llama.cpp init.** Latency is unknown. Mitigation: lazy init on the import screen; measure.
- **llama.cpp churn** (about 5 builds/day). Mitigation: pin `bNNNNN` + checksum, update deliberately, run the Linux golden tests on bump.
- **The from-source fallback breaks on upstream changes** (e.g. missing includes masked by unity builds).

## Evidence index (commands)

- `git ls-remote --tags https://github.com/ggml-org/llama.cpp`, `curl https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5`
- `curl …/commits?path=Package.swift` → `a057897ad4 2025-03-05 llama : add xcframework build script (#11996)`
- CMake build: §1.3. SwiftPM spike: `spikes/llm-runtime/scripts/run-spike.sh` (logs: `/root/spikes/run2.log`, `/root/spikes/llm-runtime/build*.log` in WSL)
- XCFramework inspection: `unzip`, `file`, `grep -c "kernel void"`, `strings | grep newLibraryWithSource`, `nm -g`, `plistlib` on `Info.plist`
- Linux binaryTarget consumer: `swift package resolve && swift build` with `.when(platforms: [.iOS, .macOS])` → `canImport(llama) == false`
- MLX asset listing: an HTTP-Range zip central-directory reader (no full download)
- Source reading: SwiftPM `release/6.4.x` @ 34946f99, swift-build @ b0458a1a, xtool 1.20.1 @ 916cdffb, mlx-swift 0.32.3 @ 19601207, mlx-swift-lm @ 5e46681b
- Apple docs: `https://developer.apple.com/tutorials/data/documentation/<symbol>.json` (fetched 2026-10-04)
