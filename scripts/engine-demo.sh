#!/usr/bin/env bash
# Build and run Tools/EngineDemo: runs the real TimetableCore engine on fixed sample data and writes an HTML
# report (engine output for inspection — NOT the app's UI) to docs/screenshots/current/engine-demo.html.
# Usage (inside WSL):   bash scripts/engine-demo.sh [output.html]
# From Windows Git Bash:
#   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/engine-demo.sh'
# Builds with an ext4 scratch path (building on /mnt/c is slow). Deterministic: re-running yields the same file.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
. "$REPO_ROOT/scripts/lib/toolchain.sh"
tabula_load_toolchain
tabula_require swift
SCRATCH="${TABULA_SCRATCH:-$HOME/.cache/tabula}/EngineDemo"
OUT="${1:-$REPO_ROOT/docs/screenshots/current/engine-demo.html}"

mkdir -p "$(dirname "$OUT")"
swift build --package-path "$REPO_ROOT/Tools/EngineDemo" --scratch-path "$SCRATCH" --product EngineDemo
BIN="$(swift build --package-path "$REPO_ROOT/Tools/EngineDemo" --scratch-path "$SCRATCH" --show-bin-path)/EngineDemo"
"$BIN" "$OUT" "$REPO_ROOT/Resources/Localizable.xcstrings"
