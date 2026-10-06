#!/usr/bin/env bash
# Run TimetableCore tests on Linux/WSL with an ext4 scratch path (building on /mnt/c is slow).
# Usage (inside WSL):   bash scripts/core-test.sh [extra swift test args]
# From Windows (Git Bash / PowerShell):
#   wsl.exe -d Ubuntu -- bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/core-test.sh'
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
. "$REPO_ROOT/scripts/lib/toolchain.sh"
tabula_load_toolchain
tabula_require swift
SCRATCH="${TABULA_SCRATCH:-$HOME/.cache/tabula}/TimetableCore"

swift --version
swift test \
  --package-path "$REPO_ROOT/Packages/TimetableCore" \
  --scratch-path "$SCRATCH" \
  "$@"
