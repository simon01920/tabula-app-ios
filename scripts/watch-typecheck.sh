#!/usr/bin/env bash
# Local watchOS TYPE-CHECK (no linking, no packaging, no install) inside WSL.
#
# xtool's Darwin SDK defines no watchOS triple and its packer cannot produce watch apps, so the watch app is
# built only in CI (project.yml / xcodebuild). But the SDK bundle installed by `xtool sdk install` contains the
# full Xcode.app, including WatchOS.platform/…/WatchOS27.0.sdk. This script compiles the shared packages and
# type-checks the watch sources against it with plain `swiftc`, so watchOS-only API mistakes (e.g. using an
# iOS-only modifier in TimetableUI) surface in seconds instead of after a CI run.
#
# What it proves: Swift sources compile for arm64_32-apple-watchos26.0 (Series 7). What it does NOT prove:
# linking, asset catalogs, Info.plist, embedding, signing, runtime behaviour (all CI / device).
#
# Usage (inside WSL):  bash scripts/watch-typecheck.sh
# Env: TABULA_DARWIN_SDK (default ~/.swiftpm/swift-sdks/darwin.artifactbundle),
#      TABULA_WATCH_TARGET (default arm64_32-apple-watchos26.0; arm64-apple-watchos26.0 also works)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
. "$REPO_ROOT/scripts/lib/toolchain.sh"
tabula_load_toolchain
tabula_require swiftc

BUNDLE="${TABULA_DARWIN_SDK:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle}"
WATCH_SDK="$(ls -d "$BUNDLE"/Xcode.app/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS[0-9]*.sdk 2>/dev/null | sort -V | tail -1 || true)"
RESOURCE_DIR="$BUNDLE/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift"
TARGET="${TABULA_WATCH_TARGET:-arm64_32-apple-watchos26.0}"
OUT="${TABULA_SCRATCH:-$HOME/.cache/tabula}/watch-typecheck/$TARGET"

if [ -z "$WATCH_SDK" ] || [ ! -d "$RESOURCE_DIR" ]; then
  echo "error: watchOS SDK not found under $BUNDLE (run 'xtool sdk install <Xcode.xip>' first, without --slim)." >&2
  exit 2
fi
rm -rf "$OUT"; mkdir -p "$OUT/modcache"
COMMON=(-target "$TARGET" -sdk "$WATCH_SDK" -resource-dir "$RESOURCE_DIR" -swift-version 6
        -module-cache-path "$OUT/modcache" -I "$OUT" -parse-as-library
        -I "$REPO_ROOT/Packages/TimetableCore/Sources/CZlib")   # system zlib module map (Stage 2D share codec)
echo "+ watchOS SDK: $WATCH_SDK"
echo "+ target:      $TARGET"

srcs() { find "$REPO_ROOT/$1" -name '*.swift' -print0 | sort -z | xargs -0 printf '%s\n'; }

emit_module() { # emit_module <ModuleName> <source dir>
  local name="$1" dir="$2" files=()
  mapfile -t files < <(srcs "$dir")
  echo "+ swiftc -emit-module $name (${#files[@]} files)"
  swiftc "${COMMON[@]}" -module-name "$name" -emit-module -emit-module-path "$OUT/$name.swiftmodule" "${files[@]}"
}

emit_module TimetableCore Packages/TimetableCore/Sources/TimetableCore
emit_module TimetableUI Packages/TimetableUI/Sources/TimetableUI
mapfile -t WATCH_FILES < <(srcs WatchApp/Sources)
echo "+ swiftc -typecheck TabulaWatch (${#WATCH_FILES[@]} files)"
swiftc "${COMMON[@]}" -module-name TabulaWatch -typecheck "${WATCH_FILES[@]}"
echo "watchOS type-check OK ($TARGET)"
