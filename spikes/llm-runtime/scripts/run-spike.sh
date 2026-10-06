#!/usr/bin/env bash
# Reproduce the llama.cpp-from-source SwiftPM spike on Linux (WSL2 Ubuntu, Swift 6.4).
# Copies the package to an ext4 work dir (builds on /mnt/c are slow), fetches llama.cpp at the pinned tag,
# builds with SwiftPM (default build system = swiftbuild in 6.4, as used by xtool) and runs the probe.
#   usage: scripts/run-spike.sh [workdir]        (default workdir: /root/spikes/llm-runtime)
#   env:   CONFIG=release|debug (default release), BUILD_SYSTEM=swiftbuild|native (default swiftbuild)
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${1:-/root/spikes/llm-runtime}"
CONFIG="${CONFIG:-release}"
BUILD_SYSTEM="${BUILD_SYSTEM:-swiftbuild}"
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

echo "== toolchain"; swift --version 2>&1 | head -2; uname -srm
echo "== copy $SRC -> $WORK"
mkdir -p "$WORK"
rm -rf "$WORK/LlamaSpike" "$WORK/scripts"
cp -r "$SRC/scripts" "$WORK/scripts"
mkdir -p "$WORK/LlamaSpike"
cp "$SRC/LlamaSpike/Package.swift" "$WORK/LlamaSpike/"
mkdir -p "$WORK/LlamaSpike/Sources/CLlama"
cp -r "$SRC/LlamaSpike/Sources/llama-probe" "$WORK/LlamaSpike/Sources/"
cp -r "$SRC/LlamaSpike/Sources/CLlama/shim" "$SRC/LlamaSpike/Sources/CLlama/include" "$WORK/LlamaSpike/Sources/CLlama/"
find "$WORK/LlamaSpike/Sources/CLlama/include" -name '*.h' -delete

echo "== fetch"
t0=$(date +%s.%N); bash "$WORK/scripts/fetch-llama.sh"; t1=$(date +%s.%N)
printf 'fetch: %.1fs\n' "$(echo "$t1 - $t0" | bc)"

cd "$WORK/LlamaSpike"
echo "== swift build -c $CONFIG --build-system $BUILD_SYSTEM -j $(nproc)"
t0=$(date +%s.%N)
swift build -c "$CONFIG" --build-system "$BUILD_SYSTEM" -j "$(nproc)" 2>&1 | tee "$WORK/build.log" | grep -E "error|Compiling|Build complete|Linking|warning: unhandled" | tail -15
status=${PIPESTATUS[0]}
t1=$(date +%s.%N)
printf 'swift build: exit=%s %.1fs (warnings: %s)\n' "$status" "$(echo "$t1 - $t0" | bc)" "$(grep -c 'warning:' "$WORK/build.log" || true)"
[ "$status" -eq 0 ] || exit "$status"

BIN="$(swift build -c "$CONFIG" --build-system "$BUILD_SYSTEM" --show-bin-path)/llama-probe"
ls -la "$BIN"
echo "== run: llama-probe"
"$BIN"
echo "== run: llama-probe <vocab-only GGUF> (grammar-constrained walk, no weights)"
"$BIN" "$WORK/LlamaSpike/Sources/CLlama/upstream/models/ggml-vocab-qwen2.gguf"
