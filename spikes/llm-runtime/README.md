# spikes/llm-runtime — llama.cpp from source via SwiftPM (Phase 0)

Throwaway feasibility spike. **Not** an app dependency, and it adds nothing to the app's `Package.swift`.
Full findings: [`docs/spikes/LLM_RUNTIME.md`](../../docs/spikes/LLM_RUNTIME.md).

What it proves on Linux (WSL2 Ubuntu 26.04, x86_64, Swift 6.4):

1. llama.cpp (pinned tag `b11382`, commit `11fe0215…`) compiles as a **plain SwiftPM C/C++ target**
   with the default `swiftbuild` build system (the one xtool uses with Swift 6.4) and with `native`.
2. A Swift 6 (strict concurrency) executable can call the C API: `llama_backend_init()`,
   `llama_print_system_info()`, ggml backend device enumeration.
3. **GBNF grammar-constrained sampling works through the C API.** The probe loads a *vocab-only* GGUF
   (tokenizer data that ships inside the llama.cpp repo, no weights), runs a model-free random walk
   under a timetable-cell grammar, and checks the output with `JSONSerialization`.

The Metal backend sources and the embedded Metal shader **source** (`GGML_METAL_EMBED_LIBRARY`) are
already wired into the package behind `__APPLE__` guards. On Linux they compile to empty translation
units. On iOS they are **UNVERIFIED** until an iOS SDK exists.

## Reproduce

From Windows (the repo path contains a space, so the script copies the package to ext4 first):

```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu --exec bash \
  "/mnt/c/Users/simon/Documents/Claude Code/school_timetable/spikes/llm-runtime/scripts/run-spike.sh" \
  /root/spikes/llm-runtime
```

Or from inside WSL: `bash spikes/llm-runtime/scripts/run-spike.sh [/root/spikes/llm-runtime]`.

Environment variables: `CONFIG=release|debug` (default `release`), `BUILD_SYSTEM=swiftbuild|native`
(default `swiftbuild`).

`run-spike.sh` does the following:

1. Copies `scripts/`, `LlamaSpike/Package.swift`, `Sources/llama-probe`, `Sources/CLlama/{shim,include}`
   to the work directory.
2. Runs `scripts/fetch-llama.sh`. This does a sparse, shallow clone of `ggml-org/llama.cpp` at
   `b11382` (it checks the commit hash) into `Sources/CLlama/upstream`, deletes `.git`, and generates
   the following:
   - `generated/{llama,ggml}-version.h`
   - `include/*.h` symlinks (symlinks, not copies, so `#pragma once` still de-duplicates)
   - `generated/metal/*.metal` and `generated/ggml-metal-embed.S`
3. Runs `swift build -c release --build-system swiftbuild -j$(nproc)`.
4. Runs `llama-probe` with no arguments, then with
   `Sources/CLlama/upstream/models/ggml-vocab-qwen2.gguf`.

Nothing from upstream is committed (see `.gitignore`). To pin a different build, set `LLAMA_TAG`
and `LLAMA_COMMIT_EXPECTED`, and also `GGML_VERSION` and `LLAMA_VERSION`.

## Recorded result (2026-10-04, Ryzen 7 3700X, 16 threads)

| Step | Result |
|---|---|
| fetch (sparse clone, 248 C/C++/ObjC files, 34 Metal kernel sources embedded) | 3.4 s |
| `swift build -c release` (swiftbuild, clean) | 50.2 s, 0 warnings |
| `swift build -c release --build-system native` (clean) | 56.9 s (native is deprecated in 6.4) |
| `swift build -c debug` (swiftbuild, clean) | 50.8 s |
| `llama-probe` binary | 42.1 MB unstripped / 3.73 MB stripped (CPU only, x86_64) |
| vocab-only load (Qwen2 vocab, 151 936 tokens) | 0.38 s |
| grammar walk, 33 tokens, full-vocab mask each step | 0.88 s (swiftbuild) / 0.72 s (native) |

Probe output (abridged):

```
llama_backend_init: ok (0.002682932 seconds)
llama_print_system_info: CPU : LLAMAFILE = 1 | REPACK = 1 |
llama_max_devices=16 supports_mmap=true supports_gpu_offload=false
ggml backend devices: 1
  [0] CPU | AMD Ryzen 7 3700X 8-Core Processor | type=0
malformed grammar rejected: true
constrained walk: steps=33 finished_with_eog=true (0.880440101 seconds)
output: {"day":"wed","period":2,"subject":", analys Safari还款註冊틋","room":":{"}
JSONSerialization accepts output: true
```

The `subject` and `room` values are random tokens, because no model is driving the walk. The point
is that only grammar-valid tokens were ever allowed, so the result is always schema-shaped JSON.

## Changes compared with upstream's CMake build

- **Per-arch CPU kernels.** SwiftPM cannot pick sources per architecture. `shim/cpu_arch_*.{c,cpp}`
  `#include` the x86 or arm file instead.
- **`src/models/clef.cpp`** is missing `#include <algorithm>`. Upstream compiles `src/models/*.cpp` as
  unity translation units, which hides the error. SwiftPM compiles files one by one, so the file is
  excluded and compiled through `shim/models_clef.cpp` instead.
- **Metal (Apple only).**
  - The Objective-C files use manual retain/release, so they need `-fno-objc-arc`. SwiftPM adds
    `-fobjc-arc` on Darwin. Tools-version 6.2 allows that `unsafeFlags` in dependency packages too.
  - `.metal` files must be **excluded** from the target. Otherwise SwiftPM/Swift Build treats them
    as resources to compile with Xcode's `metal` tool, which xtool does not have.
